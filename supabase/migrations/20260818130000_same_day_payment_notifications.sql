begin;

-- A delivery is consolidated and claimed atomically once per device and local day.
create table public.payment_notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null references public.fcm_devices(id) on delete cascade,
  notification_date date not null,
  notification_type text not null default 'same_day_payments'
    check (notification_type = 'same_day_payments'),
  invoice_count integer not null check (invoice_count > 0),
  status text not null default 'processing'
    check (status in ('processing','sent','failed','invalid_token')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  provider_message_id text,
  failure_code text,
  attempted_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,user_id,device_id,notification_date,notification_type)
);

alter table public.payment_notification_deliveries enable row level security;
revoke all on public.payment_notification_deliveries from public,anon,authenticated;
grant select,insert,update on public.payment_notification_deliveries to service_role;

create function public.list_same_day_payment_notification_invoices()
returns table(
  organization_id uuid, reminder_id uuid, factura_id text,
  invoice_number text, cliente text, balance numeric, notification_date date
)
language sql stable security definer set search_path = '' as $$
  with invoice_rows as (
    select rv.organization_id,rv.ref_fact,
      bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA') cancelled,
      coalesce(sum((select coalesce(sum(value::numeric),0)
        from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0) paid,
      count(*) monthly_rows
    from public.reportes_ventas rv
    where nullif(trim(rv.ref_fact),'') is not null
    group by rv.organization_id,rv.ref_fact
  ), local_today as (
    select timezone('America/Guayaquil',clock_timestamp())::date value
  )
  select r.organization_id,r.id,r.factura_id,coalesce(f.nro_fact,''),
    f.cliente,greatest(f.venta-ir.paid,0),t.value
  from public.payment_reminders r
  join public.organizations o on o.id=r.organization_id and o.active
  join public.facturas_maestras f
    on f.organization_id=r.organization_id and f.ref_fact=r.factura_id
  join invoice_rows ir
    on ir.organization_id=f.organization_id and ir.ref_fact=f.ref_fact
  cross join local_today t
  where r.active and r.payment_date=t.value and not ir.cancelled
    and ir.monthly_rows>0 and f.venta-ir.paid>0.005
  order by r.organization_id,r.factura_id;
$$;

create function public.claim_same_day_payment_delivery(
  p_organization_id uuid,p_user_id uuid,p_device_id uuid,
  p_notification_date date,p_invoice_count integer
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  if p_notification_date is distinct from timezone('America/Guayaquil',clock_timestamp())::date
     or p_invoice_count<=0 then return null; end if;
  insert into public.payment_notification_deliveries(
    organization_id,user_id,device_id,notification_date,invoice_count)
  select p_organization_id,p_user_id,p_device_id,p_notification_date,p_invoice_count
  where exists(select 1 from public.organizations o where o.id=p_organization_id and o.active)
    and exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=p_user_id and m.active)
    and exists(select 1 from public.fcm_devices d where d.id=p_device_id and d.organization_id=p_organization_id and d.user_id=p_user_id and d.active)
  on conflict do nothing returning id into result;
  return result;
end;
$$;

revoke all on function public.list_same_day_payment_notification_invoices() from public,anon,authenticated;
revoke all on function public.claim_same_day_payment_delivery(uuid,uuid,uuid,date,integer) from public,anon,authenticated;
grant execute on function public.list_same_day_payment_notification_invoices() to service_role;
grant execute on function public.claim_same_day_payment_delivery(uuid,uuid,uuid,date,integer) to service_role;

-- Disable all queued legacy 1/3-day deliveries without deleting history.
update public.payment_notification_events set status='cancelled',next_retry_at=null,
  last_error_code='LEGACY_NOTICE_DISABLED',updated_at=clock_timestamp()
where status in ('pending','processing','temporary_failure','no_devices');

commit;
