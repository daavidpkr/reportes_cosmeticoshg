begin;

create table public.enterprise_requests (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  action text not null,
  result jsonb,
  created_at timestamptz not null default clock_timestamp(),
  primary key (organization_id, request_id)
);
alter table public.enterprise_requests enable row level security;
revoke all on public.enterprise_requests from public, anon, authenticated;
grant select, insert, update on public.enterprise_requests to service_role;

create function public.calculate_enterprise_payment_date(invoice_date date, term_days integer)
returns date language sql immutable strict set search_path = '' as $$
  select public.next_weekday(invoice_date + term_days);
$$;

create function public.sync_enterprise_reminder(
  p_organization_id uuid, p_factura_id text, p_request_id uuid, p_reason text
) returns date language plpgsql security definer set search_path = '' as $$
declare terms public.invoice_payment_terms%rowtype;
declare customer public.billing_customers%rowtype;
declare old_reminder public.payment_reminders%rowtype;
declare current_reminder public.payment_reminders%rowtype;
declare invoice_date date;
declare days integer;
declare effective date;
declare source text;
begin
  if p_organization_id is distinct from public.require_current_organization_id() then
    raise exception 'organization mismatch';
  end if;
  select * into terms from public.invoice_payment_terms
    where organization_id=p_organization_id and factura_id=p_factura_id for update;
  if not found or not terms.active then return null; end if;
  select f.fecha into invoice_date from public.facturas_maestras f
    where f.ref_fact=p_factura_id and f.organization_id=p_organization_id;
  if not found then raise exception 'enterprise invoice not found'; end if;
  select * into customer from public.billing_customers
    where id=terms.customer_id and organization_id=p_organization_id;
  days := coalesce(terms.exceptional_term_days, customer.payment_term_days);
  if days is null then return null; end if;
  effective := public.calculate_enterprise_payment_date(invoice_date, days);
  source := case when terms.exceptional_term_days is null then 'customer_term' else 'invoice_exception' end;

  select * into old_reminder from public.payment_reminders
    where organization_id=p_organization_id and factura_id=p_factura_id for update;
  if found and old_reminder.date_source='manual' then
    raise exception 'manual schedule confirmation required';
  end if;

  insert into public.payment_reminders
    (organization_id,user_id,factura_id,payment_date,active,notify_three_days,
     notify_one_day,date_source,calculated_term_days)
  values (p_organization_id,auth.uid(),p_factura_id,effective,true,true,true,source,days)
  on conflict (organization_id,factura_id) where organization_id is not null
  do update set payment_date=excluded.payment_date, date_source=excluded.date_source,
                calculated_term_days=excluded.calculated_term_days
  returning * into current_reminder;

  if old_reminder.id is not null and old_reminder.payment_date is distinct from effective then
    update public.payment_notification_events set status='cancelled', next_retry_at=null,
      last_error_code='SCHEDULE_CHANGED', updated_at=clock_timestamp()
    where reminder_id=old_reminder.id and schedule_version=old_reminder.schedule_version
      and status in ('pending','processing','temporary_failure','no_devices');
    insert into public.payment_followups
      (organization_id,reminder_id,request_id,comment,action_type,
       previous_payment_date,requested_payment_date,effective_payment_date,created_by)
    values (p_organization_id,current_reminder.id,p_request_id,p_reason,'reschedule',
            old_reminder.payment_date,effective,effective,auth.uid())
    on conflict (reminder_id,request_id) do nothing;
  end if;
  return effective;
end;
$$;

create function public.enterprise_upsert_invoice(
  p_request_id uuid, p_ref_fact text, p_cliente text, p_nombre_comercial text,
  p_fecha date, p_nro_fact text, p_venta numeric
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare org uuid := public.require_current_organization_id();
declare existing_org uuid; declare customer_id uuid; declare result jsonb;
begin
  if nullif(trim(p_ref_fact),'') is null or nullif(trim(p_cliente),'') is null
     or p_fecha is null then raise exception 'invalid invoice'; end if;
  select r.result into result from public.enterprise_requests r
    where r.organization_id=org and r.request_id=p_request_id and r.action='upsert_invoice';
  if found then return result; end if;
  select organization_id into existing_org from public.facturas_maestras
    where ref_fact=trim(p_ref_fact) for update;
  if found and existing_org is null then raise exception 'historical invoice assignment required'; end if;
  if found and existing_org <> org then raise exception 'invoice belongs to another organization'; end if;

  insert into public.facturas_maestras
    (organization_id,ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta)
  values (org,trim(p_ref_fact),trim(p_cliente),trim(coalesce(p_nombre_comercial,'')),
          p_fecha,trim(p_nro_fact),p_venta)
  on conflict (ref_fact) do update set cliente=excluded.cliente,
    nombre_comercial=excluded.nombre_comercial,fecha=excluded.fecha,
    nro_fact=excluded.nro_fact,venta=excluded.venta
  where public.facturas_maestras.organization_id=org;

  insert into public.billing_customers
    (organization_id,name,commercial_name,updated_by)
  values (org,trim(p_cliente),trim(coalesce(p_nombre_comercial,'')),auth.uid())
  on conflict (organization_id,normalized_name,normalized_commercial_name)
  do update set name=excluded.name,commercial_name=excluded.commercial_name,
                updated_at=clock_timestamp(),updated_by=auth.uid()
  returning id into customer_id;
  insert into public.invoice_payment_terms
    (organization_id,factura_id,customer_id,active,updated_by)
  values (org,trim(p_ref_fact),customer_id,true,auth.uid())
  on conflict (organization_id,factura_id) do update set
    customer_id=excluded.customer_id,updated_at=clock_timestamp(),updated_by=auth.uid();
  perform public.sync_enterprise_reminder(org,trim(p_ref_fact),p_request_id,'Reprogramación automática por datos de factura');
  result := jsonb_build_object('factura_id',trim(p_ref_fact),'customer_id',customer_id);
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'upsert_invoice',result);
  return result;
end;
$$;

create function public.preview_enterprise_customer_term(p_customer_id uuid,p_days integer)
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.invoice_payment_terms t
  join public.facturas_maestras f on f.ref_fact=t.factura_id and f.organization_id=t.organization_id
  left join public.payment_reminders r on r.organization_id=t.organization_id and r.factura_id=t.factura_id
  where t.organization_id=public.require_current_organization_id()
    and t.customer_id=p_customer_id and t.active and t.exceptional_term_days is null
    and p_days>=0 and (r.id is null or (r.date_source<>'manual' and
      r.payment_date is distinct from public.calculate_enterprise_payment_date(f.fecha,p_days)));
$$;

create function public.save_enterprise_customer_term(
  p_request_id uuid,p_customer_id uuid,p_days integer,p_apply boolean
) returns integer language plpgsql security definer set search_path = '' as $$
declare org uuid:=public.require_current_organization_id(); declare item record;
declare affected integer:=0;
begin
  if p_days is null or p_days<0 then raise exception 'invalid payment term'; end if;
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then
    return coalesce((select (result->>'affected')::integer from public.enterprise_requests
      where organization_id=org and request_id=p_request_id),0);
  end if;
  update public.billing_customers set payment_term_days=p_days,updated_at=clock_timestamp(),updated_by=auth.uid()
    where id=p_customer_id and organization_id=org;
  if not found then raise exception 'enterprise customer not found'; end if;
  if p_apply then
    for item in select factura_id from public.invoice_payment_terms
      where organization_id=org and customer_id=p_customer_id and active
        and exceptional_term_days is null loop
      perform public.sync_enterprise_reminder(org,item.factura_id,p_request_id,
        'Reprogramación automática por plazo habitual');
      affected:=affected+1;
    end loop;
  end if;
  insert into public.enterprise_requests values
    (org,p_request_id,'save_customer_term',jsonb_build_object('affected',affected),clock_timestamp());
  return affected;
end;
$$;

create function public.save_enterprise_invoice_exception(
  p_request_id uuid,p_factura_id text,p_exceptional_days integer,
  p_confirm_manual_override boolean default false
) returns date language plpgsql security definer set search_path = '' as $$
declare org uuid:=public.require_current_organization_id();
declare terms public.invoice_payment_terms%rowtype;
declare customer public.billing_customers%rowtype;
declare reminder public.payment_reminders%rowtype;
declare applicable integer; declare effective date; declare invoice_date date;
begin
  if p_exceptional_days is not null and p_exceptional_days<0 then raise exception 'invalid exception'; end if;
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then
    return (select nullif(result->>'effective_date','')::date from public.enterprise_requests
      where organization_id=org and request_id=p_request_id);
  end if;
  select * into terms from public.invoice_payment_terms
    where organization_id=org and factura_id=p_factura_id for update;
  if not found then raise exception 'enterprise invoice terms not found'; end if;
  select * into customer from public.billing_customers
    where id=terms.customer_id and organization_id=org;
  select * into reminder from public.payment_reminders
    where organization_id=org and factura_id=p_factura_id for update;
  select fecha into invoice_date from public.facturas_maestras
    where organization_id=org and ref_fact=p_factura_id;
  applicable:=coalesce(p_exceptional_days,customer.payment_term_days);
  effective:=case when applicable is null then null
    else public.calculate_enterprise_payment_date(invoice_date,applicable) end;
  if reminder.id is not null and reminder.date_source='manual'
     and reminder.payment_date is distinct from effective and not p_confirm_manual_override then
    raise exception 'manual schedule confirmation required';
  end if;
  update public.invoice_payment_terms set exceptional_term_days=p_exceptional_days,
    updated_at=clock_timestamp(),updated_by=auth.uid()
    where organization_id=org and factura_id=p_factura_id;
  if reminder.id is not null and reminder.date_source='manual' and p_confirm_manual_override then
    update public.payment_reminders set date_source='customer_term'
      where id=reminder.id;
  end if;
  if effective is null then
    if reminder.id is not null and reminder.date_source<>'manual' then
      update public.payment_reminders set active=false,calculated_term_days=null where id=reminder.id;
      update public.payment_notification_events set status='cancelled',next_retry_at=null,
        last_error_code='PAYMENT_TERM_PENDING',updated_at=clock_timestamp()
      where reminder_id=reminder.id and schedule_version=reminder.schedule_version
        and status in ('pending','processing','temporary_failure','no_devices');
      insert into public.payment_followups
        (organization_id,reminder_id,request_id,comment,action_type,
         previous_payment_date,created_by)
      values(org,reminder.id,p_request_id,'Plazo pendiente; programación automática desactivada',
             'reschedule',reminder.payment_date,auth.uid())
      on conflict(reminder_id,request_id) do nothing;
    end if;
  elsif reminder.id is not null and reminder.date_source='manual'
        and reminder.payment_date is not distinct from effective then
    null; -- Preserve the manual source when the effective date is unchanged.
  else
    perform public.sync_enterprise_reminder(org,p_factura_id,p_request_id,
      case when p_exceptional_days is null then 'Retiro de excepción; retorno al plazo habitual'
           else 'Plazo excepcional de factura' end);
  end if;
  insert into public.enterprise_requests values
    (org,p_request_id,'save_invoice_exception',
     jsonb_build_object('effective_date',coalesce(effective::text,'')),clock_timestamp());
  return effective;
end;
$$;

revoke all on function public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric) from public,anon;
revoke all on function public.preview_enterprise_customer_term(uuid,integer) from public,anon;
revoke all on function public.save_enterprise_customer_term(uuid,uuid,integer,boolean) from public,anon;
revoke all on function public.save_enterprise_invoice_exception(uuid,text,integer,boolean) from public,anon;
revoke all on function public.sync_enterprise_reminder(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric) to authenticated;
grant execute on function public.preview_enterprise_customer_term(uuid,integer) to authenticated;
grant execute on function public.save_enterprise_customer_term(uuid,uuid,integer,boolean) to authenticated;
grant execute on function public.save_enterprise_invoice_exception(uuid,text,integer,boolean) to authenticated;
revoke all on function public.calculate_enterprise_payment_date(date,integer) from public,anon,authenticated;

commit;
