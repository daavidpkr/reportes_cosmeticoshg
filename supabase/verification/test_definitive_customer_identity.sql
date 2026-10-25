-- Run in a transaction against a disposable/local database. Every assertion
-- rolls back, including concurrent/conflict fixtures created by the harness.
begin;
do $$
begin
  if not exists (select 1 from pg_indexes where schemaname='public'
    and indexname='billing_customers_org_buyer_identity_key'
    and indexdef like '%UNIQUE%buyer_identification_normalized%') then
    raise exception 'missing canonical identity unique index';
  end if;
  if has_table_privilege('authenticated','public.billing_customers','insert')
     or has_table_privilege('authenticated','public.billing_customers','update')
     or has_table_privilege('authenticated','public.billing_customers','delete') then
    raise exception 'direct customer writes are exposed';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and has_function_privilege(
      'authenticated',p.oid,'execute') and pg_get_functiondef(p.oid)
      like '%insert into public.billing_customers%') then
    raise exception 'an authenticated RPC bypasses canonical customer write';
  end if;
end $$;
rollback;
