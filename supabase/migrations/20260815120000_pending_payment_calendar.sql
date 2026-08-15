begin;

alter table public.payment_reminders
  add column calendar_comment text not null default '';

alter table public.payment_reminders
  add constraint payment_reminders_calendar_comment_length
  check (char_length(calendar_comment) <= 500);

create function public.list_pending_payment_calendar(p_month date)
returns table(
  reminder_id uuid,
  factura_id text,
  invoice_number text,
  cliente text,
  nombre_comercial text,
  invoice_date date,
  reminder_date date,
  balance numeric,
  comment text
)
language sql stable security definer set search_path = '' as $$
  with invoice_rows as (
    select rv.organization_id, rv.ref_fact,
      bool_or(upper(trim(coalesce(rv.vendedor,''))) = 'ANULADA') as cancelled,
      coalesce(sum((select coalesce(sum(value::numeric),0)
                    from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0) as paid
    from public.reportes_ventas rv
    where rv.organization_id = public.require_current_organization_id()
      and nullif(trim(rv.ref_fact),'') is not null
    group by rv.organization_id, rv.ref_fact
  )
  select r.id, r.factura_id, coalesce(f.nro_fact,''), f.cliente,
    coalesce(f.nombre_comercial,''), f.fecha, r.payment_date,
    greatest(f.venta - ir.paid, 0), r.calendar_comment
  from public.payment_reminders r
  join public.facturas_maestras f
    on f.organization_id=r.organization_id and f.ref_fact=r.factura_id
  join invoice_rows ir
    on ir.organization_id=f.organization_id and ir.ref_fact=f.ref_fact
  where r.organization_id=public.require_current_organization_id()
    and r.active and not ir.cancelled
    and f.venta - ir.paid > 0.005
    and r.payment_date >= date_trunc('month',p_month)::date
    and r.payment_date < (date_trunc('month',p_month)+interval '1 month')::date
  order by r.payment_date,r.factura_id;
$$;

create function public.update_payment_calendar_reminder(
  p_request_id uuid,
  p_reminder_id uuid,
  p_requested_payment_date date,
  p_comment text default ''
) returns table(effective_payment_date date, comment text)
language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  reminder public.payment_reminders%rowtype;
  effective date;
  clean_comment text := trim(coalesce(p_comment,''));
  stored jsonb;
begin
  if p_requested_payment_date is null then raise exception 'invalid payment date'; end if;
  if char_length(clean_comment)>500 then raise exception 'comment too long'; end if;

  select er.result into stored from public.enterprise_requests er
  where er.organization_id=org and er.request_id=p_request_id
    and er.action='update_payment_calendar_reminder';
  if found then
    return query select (stored->>'effective_payment_date')::date,
      coalesce(stored->>'comment','');
    return;
  end if;

  select * into reminder from public.payment_reminders
  where id=p_reminder_id and organization_id=org for update;
  if not found then raise exception 'enterprise reminder not found'; end if;
  effective := public.next_weekday(p_requested_payment_date);

  update public.payment_reminders set payment_date=effective,
    calendar_comment=clean_comment,date_source='manual',calculated_term_days=null
  where id=p_reminder_id;

  if effective is distinct from reminder.payment_date then
    update public.payment_notification_events set status='cancelled',next_retry_at=null,
      last_error_code='SCHEDULE_CHANGED',updated_at=clock_timestamp()
    where reminder_id=p_reminder_id and schedule_version=reminder.schedule_version
      and status in('pending','processing','temporary_failure','no_devices');
  end if;

  insert into public.payment_followups(organization_id,reminder_id,request_id,
    comment,action_type,previous_payment_date,requested_payment_date,
    effective_payment_date,created_by)
  values(org,p_reminder_id,p_request_id,nullif(clean_comment,''),
    case when effective is distinct from reminder.payment_date then 'comment_and_reschedule' else 'comment' end,
    case when effective is distinct from reminder.payment_date then reminder.payment_date end,
    case when effective is distinct from reminder.payment_date then p_requested_payment_date end,
    case when effective is distinct from reminder.payment_date then effective end,auth.uid());

  stored:=jsonb_build_object('effective_payment_date',effective,'comment',clean_comment);
  insert into public.enterprise_requests(organization_id,request_id,action,result)
  values(org,p_request_id,'update_payment_calendar_reminder',stored);
  return query select effective,clean_comment;
end;
$$;

revoke all on function public.list_pending_payment_calendar(date) from public,anon;
revoke all on function public.update_payment_calendar_reminder(uuid,uuid,date,text) from public,anon;
grant execute on function public.list_pending_payment_calendar(date) to authenticated;
grant execute on function public.update_payment_calendar_reminder(uuid,uuid,date,text) to authenticated;

commit;
