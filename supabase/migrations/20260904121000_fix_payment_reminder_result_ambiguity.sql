-- Independent regression fix: the deployed RPC declares a PL/pgSQL variable
-- named result and also selects enterprise_requests.result without qualifying
-- it. PostgreSQL correctly rejects that reference as ambiguous.
begin;

create or replace function public.enterprise_save_payment_reminder(
  p_request_id uuid,p_factura_id text,p_payment_date date,p_active boolean,
  p_notify_three_days boolean,p_notify_one_day boolean
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id();
  reminder_id_value uuid;
begin
  if not p_notify_three_days and not p_notify_one_day then raise exception 'notice required'; end if;
  if exists(select 1 from public.enterprise_requests er where er.organization_id=org and er.request_id=p_request_id) then
    return (select (er.result->>'reminder_id')::uuid from public.enterprise_requests er where er.organization_id=org and er.request_id=p_request_id);
  end if;
  if not exists(select 1 from public.facturas_maestras f where f.organization_id=org and f.ref_fact=p_factura_id) then raise exception 'enterprise invoice not found'; end if;
  select pr.id into reminder_id_value from public.payment_reminders pr where pr.organization_id=org and pr.factura_id=p_factura_id for update;
  if found then
    update public.payment_reminders set payment_date=p_payment_date,active=p_active,notify_three_days=p_notify_three_days,notify_one_day=p_notify_one_day,date_source='manual',calculated_term_days=null where id=reminder_id_value;
  else
    insert into public.payment_reminders(organization_id,user_id,factura_id,payment_date,active,notify_three_days,notify_one_day,date_source)
    values(org,auth.uid(),p_factura_id,p_payment_date,p_active,p_notify_three_days,p_notify_one_day,'manual') returning id into reminder_id_value;
  end if;
  insert into public.enterprise_requests(organization_id,request_id,action,result)
  values(org,p_request_id,'save_payment_reminder',jsonb_build_object('reminder_id',reminder_id_value));
  return reminder_id_value;
end $$;
revoke all on function public.enterprise_save_payment_reminder(uuid,text,date,boolean,boolean,boolean) from public,anon;
grant execute on function public.enterprise_save_payment_reminder(uuid,text,date,boolean,boolean,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
