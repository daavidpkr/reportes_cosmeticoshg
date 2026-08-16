begin;

-- A retained inactive row is the smallest safe deletion marker. The customer FK
-- is RESTRICT (never CASCADE), so invoice-term history remains intact, while a
-- later invoice upsert cannot resurrect the configuration or its former term.
alter table public.billing_customers
  add column configuration_active boolean not null default true;

create index billing_customers_active_list_idx
  on public.billing_customers(organization_id,name)
  where configuration_active;

create function public.delete_enterprise_customer_configuration(
  p_request_id uuid,p_name text,p_commercial_name text
) returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id();
begin
  if p_request_id is null or nullif(trim(p_name),'') is null then
    raise exception 'invalid customer identity';
  end if;
  if exists(select 1 from public.enterprise_requests
    where organization_id=org and request_id=p_request_id) then return; end if;

  update public.billing_customers
    set configuration_active=false,payment_term_days=null,
        updated_at=clock_timestamp(),updated_by=auth.uid()
  where organization_id=org
    and normalized_name=public.normalize_customer_identity(p_name)
    and normalized_commercial_name=public.normalize_customer_identity(p_commercial_name)
    and configuration_active;
  if not found then raise exception 'enterprise customer not found'; end if;

  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'delete_customer_configuration','{"deleted":true}'::jsonb);
end; $$;

create function public.schedule_enterprise_customer_pending(
  p_request_id uuid,p_name text,p_commercial_name text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id(); customer public.billing_customers%rowtype;
  item record; result jsonb; total_count integer:=0; existing_count integer:=0;
  created_count integer:=0; before_count integer; scheduled date;
begin
  if p_request_id is null or nullif(trim(p_name),'') is null then
    raise exception 'invalid customer identity';
  end if;
  select r.result into result from public.enterprise_requests r
    where r.organization_id=org and r.request_id=p_request_id;
  if found then return result; end if;

  select * into customer from public.billing_customers c
    where c.organization_id=org
      and c.normalized_name=public.normalize_customer_identity(p_name)
      and c.normalized_commercial_name=public.normalize_customer_identity(p_commercial_name)
      and c.configuration_active for update;
  if not found then raise exception 'enterprise customer not found'; end if;
  if customer.payment_term_days is null then raise exception 'customer payment term is pending'; end if;

  select count(*)::integer,
    count(*) filter(where exists(select 1 from public.payment_reminders r
      where r.organization_id=t.organization_id and r.factura_id=t.factura_id))::integer
    into total_count,existing_count
  from public.invoice_payment_terms t
  where t.organization_id=org and t.customer_id=customer.id and t.active;

  for item in select t.factura_id from public.invoice_payment_terms t
    where t.organization_id=org and t.customer_id=customer.id and t.active
      and not exists(select 1 from public.payment_reminders r
        where r.organization_id=org and r.factura_id=t.factura_id)
  loop
    select count(*)::integer into before_count from public.payment_reminders r
      where r.organization_id=org and r.factura_id=item.factura_id;
    scheduled:=public.sync_enterprise_reminder(org,item.factura_id,p_request_id,
      'manual customer reminder recovery');
    if scheduled is not null and before_count=0 and exists(select 1
      from public.payment_reminders r where r.organization_id=org
      and r.factura_id=item.factura_id) then created_count:=created_count+1; end if;
  end loop;

  result:=jsonb_build_object(
    'eligible_count',created_count,
    'created_count',created_count,
    'skipped_existing_count',existing_count,
    'skipped_count',greatest(total_count-existing_count-created_count,0));
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'schedule_customer_pending',result);
  return result;
end; $$;

revoke all on function public.delete_enterprise_customer_configuration(uuid,text,text)
  from public,anon;
revoke all on function public.schedule_enterprise_customer_pending(uuid,text,text)
  from public,anon;
grant execute on function public.delete_enterprise_customer_configuration(uuid,text,text)
  to authenticated;
grant execute on function public.schedule_enterprise_customer_pending(uuid,text,text)
  to authenticated;

notify pgrst, 'reload schema';
commit;
