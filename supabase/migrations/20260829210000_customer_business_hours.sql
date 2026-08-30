begin;

alter table public.billing_customers
  add column if not exists horario_atencion text;

alter table public.billing_customers
  drop constraint if exists billing_customers_horario_atencion_length;
alter table public.billing_customers
  add constraint billing_customers_horario_atencion_length
  check (horario_atencion is null or length(horario_atencion) <= 120);

create or replace function public.get_customer_profile(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare org uuid := public.require_current_organization_id(); result jsonb;
begin
  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'commercial_name', c.commercial_name,
    'payment_term_days', c.payment_term_days,
    'horario_atencion', c.horario_atencion,
    'configuration_active', c.configuration_active
  ) into result
  from public.billing_customers c
  where c.id = p_customer_id and c.organization_id = org;
  if result is null then raise exception 'enterprise customer not found'; end if;
  return result;
end;
$$;

create or replace function public.update_customer_business_hours(
  p_customer_id uuid, p_business_hours text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  normalized text := nullif(trim(p_business_hours), '');
  result jsonb;
begin
  if normalized is not null and length(normalized) > 120 then
    raise exception 'business hours exceed 120 characters';
  end if;

  update public.billing_customers c
  set horario_atencion = normalized,
      updated_at = clock_timestamp(),
      updated_by = auth.uid()
  where c.id = p_customer_id
    and c.organization_id = org
    and c.configuration_active
  returning jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'commercial_name', c.commercial_name,
    'payment_term_days', c.payment_term_days,
    'horario_atencion', c.horario_atencion,
    'configuration_active', c.configuration_active
  ) into result;
  if result is null then raise exception 'enterprise customer not available for editing'; end if;
  return result;
end;
$$;

-- The existing history RPC used to reject retained inactive customers. Remove
-- only that predicate so historical invoices stay available without restoring
-- the customer to the active list.
do $$
declare definition text;
begin
  select pg_get_functiondef(
    'public.list_customer_invoice_history(uuid,integer,integer,text,text,text)'::regprocedure)
  into definition;
  definition := replace(definition,
    'and c.organization_id = org and c.configuration_active;',
    'and c.organization_id = org;');
  execute definition;
end;
$$;

revoke all on function public.get_customer_profile(uuid) from public, anon;
revoke all on function public.update_customer_business_hours(uuid,text) from public, anon;
grant execute on function public.get_customer_profile(uuid) to authenticated;
grant execute on function public.update_customer_business_hours(uuid,text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'billing_customers'
  ) then
    alter publication supabase_realtime add table public.billing_customers;
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
