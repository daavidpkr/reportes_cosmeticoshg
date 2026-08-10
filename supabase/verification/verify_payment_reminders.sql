-- Solo lectura: ejecutar después de que la migración confirme COMMIT.

-- Tablas y RLS.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('payment_reminders', 'fcm_devices', 'payment_notification_events')
order by c.relname;

-- Columnas, tipos, nulabilidad y valores predeterminados.
select table_name, ordinal_position, column_name, data_type, udt_name,
       is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('payment_reminders', 'fcm_devices', 'payment_notification_events')
order by table_name, ordinal_position;

-- Restricciones y claves foráneas.
select con.conname, source.relname as source_table, con.contype,
       target.relname as target_table, pg_get_constraintdef(con.oid) as definition
from pg_catalog.pg_constraint con
join pg_catalog.pg_class source on source.oid = con.conrelid
join pg_catalog.pg_namespace n on n.oid = source.relnamespace
left join pg_catalog.pg_class target on target.oid = con.confrelid
where n.nspname = 'public'
  and source.relname in ('payment_reminders', 'fcm_devices', 'payment_notification_events')
order by source.relname, con.conname;

-- Índices.
select tablename, indexname, indexdef
from pg_catalog.pg_indexes
where schemaname = 'public'
  and tablename in ('payment_reminders', 'fcm_devices', 'payment_notification_events')
order by tablename, indexname;

-- Políticas. payment_notification_events debe aparecer sin políticas.
select tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_catalog.pg_policies
where schemaname = 'public'
  and tablename in ('payment_reminders', 'fcm_devices', 'payment_notification_events', 'facturas_maestras')
order by tablename, policyname;

-- Funciones, firmas, SECURITY DEFINER y configuración search_path.
select p.oid::regprocedure::text as signature,
       p.prosecdef as security_definer,
       p.proconfig as function_config
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'set_payment_reminder_updated_at',
    'register_fcm_device',
    'deactivate_fcm_device',
    'claim_payment_notification_event'
  )
order by signature;

-- Privilegios efectivos de tablas para cada rol.
select role_name, table_name,
       has_table_privilege(role_name, format('public.%I', table_name), 'SELECT') as can_select,
       has_table_privilege(role_name, format('public.%I', table_name), 'INSERT') as can_insert,
       has_table_privilege(role_name, format('public.%I', table_name), 'UPDATE') as can_update,
       has_table_privilege(role_name, format('public.%I', table_name), 'DELETE') as can_delete
from unnest(array['anon', 'authenticated', 'service_role']) as roles(role_name)
cross join unnest(array['payment_reminders', 'fcm_devices', 'payment_notification_events']) as tables(table_name)
order by table_name, role_name;

-- Privilegios efectivos de ejecución.
select role_name, p.oid::regprocedure::text as signature,
       has_function_privilege(role_name, p.oid, 'EXECUTE') as can_execute
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
cross join unnest(array['anon', 'authenticated', 'service_role']) as roles(role_name)
where n.nspname = 'public'
  and p.proname in (
    'set_payment_reminder_updated_at',
    'register_fcm_device',
    'deactivate_fcm_device',
    'claim_payment_notification_event'
  )
order by signature, role_name;

-- Trigger.
select event_object_schema, event_object_table, trigger_name,
       action_timing, event_manipulation, action_statement
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table = 'payment_reminders'
  and trigger_name = 'payment_reminders_updated_at';

-- Confirmar que la política y privilegios de facturas_maestras permanecen iguales.
select c.relrowsecurity as rls_enabled,
       has_table_privilege('anon', 'public.facturas_maestras', 'SELECT') as anon_select,
       has_table_privilege('authenticated', 'public.facturas_maestras', 'SELECT') as authenticated_select,
       has_table_privilege('service_role', 'public.facturas_maestras', 'SELECT') as service_role_select
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'facturas_maestras';
