begin;

-- Keep p_apply for wire compatibility with deployed clients, but configuring a
-- customer term now always schedules every eligible invoice lacking a reminder.
create or replace function public.save_enterprise_customer_term(
  p_request_id uuid,p_customer_id uuid,p_days integer,p_apply boolean
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  org uuid:=public.require_current_organization_id();
  item record;
  affected integer:=0;
  scheduled date;
begin
  if p_days is null or p_days<0 then raise exception 'invalid payment term'; end if;
  if exists(select 1 from public.enterprise_requests
            where organization_id=org and request_id=p_request_id) then
    return coalesce((select (result->>'affected')::integer
      from public.enterprise_requests where organization_id=org and request_id=p_request_id),0);
  end if;
  update public.billing_customers set payment_term_days=p_days,
    updated_at=clock_timestamp(),updated_by=auth.uid()
    where id=p_customer_id and organization_id=org;
  if not found then raise exception 'enterprise customer not found'; end if;

  for item in
    select t.factura_id from public.invoice_payment_terms t
    where t.organization_id=org and t.customer_id=p_customer_id and t.active
      and t.exceptional_term_days is null
      and not exists(select 1 from public.payment_reminders r
        where r.organization_id=org and r.factura_id=t.factura_id)
  loop
    scheduled:=public.sync_enterprise_reminder(org,item.factura_id,p_request_id,
      'automatic customer payment term');
    if scheduled is not null then affected:=affected+1; end if;
  end loop;

  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'save_customer_term',jsonb_build_object('affected',affected));
  return affected;
end;
$$;

revoke all on function public.save_enterprise_customer_term(uuid,uuid,integer,boolean)
  from public,anon;
grant execute on function public.save_enterprise_customer_term(uuid,uuid,integer,boolean)
  to authenticated;

notify pgrst, 'reload schema';
commit;
