with table_info as (
  select jsonb_build_object('exists', true, 'rls', c.relrowsecurity) value
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='payment_followups'
), columns_info as (
  select jsonb_agg(jsonb_build_object(
    'name', column_name, 'type', data_type, 'udt', udt_name,
    'nullable', is_nullable, 'default', column_default
  ) order by ordinal_position) value
  from information_schema.columns
  where table_schema='public' and table_name='payment_followups'
), constraints_info as (
  select jsonb_agg(jsonb_build_object(
    'name', con.conname, 'definition', pg_get_constraintdef(con.oid)
  ) order by con.conname) value
  from pg_constraint con join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='payment_followups'
), indexes_info as (
  select jsonb_agg(jsonb_build_object('name', indexname, 'definition', indexdef)
                   order by indexname) value
  from pg_indexes where schemaname='public' and tablename='payment_followups'
), policies_info as (
  select jsonb_agg(jsonb_build_object(
    'name', policyname, 'command', cmd, 'roles', roles,
    'using', qual, 'check', with_check
  ) order by policyname) value
  from pg_policies where schemaname='public' and tablename='payment_followups'
), rpc_info as (
  select jsonb_build_object(
    'exists', true, 'security_definer', p.prosecdef, 'config', p.proconfig,
    'anon_execute', has_function_privilege('anon', p.oid, 'execute'),
    'authenticated_execute', has_function_privilege('authenticated', p.oid, 'execute'),
    'service_execute', has_function_privilege('service_role', p.oid, 'execute'),
    'definition_uses_auth_uid', position('auth.uid()' in pg_get_functiondef(p.oid)) > 0,
    'definition_accepts_created_by', position('p_created_by' in pg_get_function_arguments(p.oid)) > 0
  ) value
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='add_payment_followup'
), events_constraint as (
  select pg_get_constraintdef(con.oid) value
  from pg_constraint con join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='payment_notification_events'
    and con.conname='payment_notification_events_status_check'
), cron_info as (
  select jsonb_agg(jsonb_build_object('name',jobname,'schedule',schedule,'active',active)) value
  from cron.job where jobname='process-payment-reminders-production'
)
select table_info.value table_info, columns_info.value columns,
       constraints_info.value constraints, indexes_info.value indexes,
       policies_info.value policies, rpc_info.value rpc,
       events_constraint.value event_status_constraint, cron_info.value cron
from table_info, columns_info, constraints_info, indexes_info,
     policies_info, rpc_info, events_constraint, cron_info;
