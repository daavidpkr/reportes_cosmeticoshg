with table_info as (
  select jsonb_build_object(
    'rls', c.relrowsecurity,
    'forced_rls', c.relforcerowsecurity
  ) value
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='facturas_maestras'
), columns_info as (
  select jsonb_agg(jsonb_build_object(
    'name', column_name, 'type', data_type, 'nullable', is_nullable
  ) order by ordinal_position) value
  from information_schema.columns
  where table_schema='public' and table_name='facturas_maestras'
), policies_info as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', policyname, 'command', cmd, 'roles', roles,
    'using', qual, 'check', with_check
  )), '[]'::jsonb) value
  from pg_policies
  where schemaname='public' and tablename='facturas_maestras'
), grants_info as (
  select jsonb_agg(jsonb_build_object(
    'role', grantee, 'privilege', privilege_type
  ) order by grantee, privilege_type) value
  from information_schema.role_table_grants
  where table_schema='public' and table_name='facturas_maestras'
    and grantee in ('anon','authenticated','service_role')
)
select table_info.value table_info, columns_info.value columns,
       policies_info.value policies, grants_info.value grants
from table_info, columns_info, policies_info, grants_info;
