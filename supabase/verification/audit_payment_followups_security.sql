with tables as (
  select jsonb_agg(jsonb_build_object(
    'table', c.relname, 'rls', c.relrowsecurity, 'forced_rls', c.relforcerowsecurity
  ) order by c.relname) value
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname in ('payment_reminders','payment_notification_events')
), triggers as (
  select jsonb_agg(jsonb_build_object(
    'name', t.tgname, 'definition', pg_get_triggerdef(t.oid)
  ) order by t.tgname) value
  from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='payment_reminders' and not t.tgisinternal
), privileges as (
  select jsonb_agg(jsonb_build_object(
    'object', table_name, 'grantee', grantee, 'privilege', privilege_type
  ) order by table_name, grantee, privilege_type) value
  from information_schema.role_table_grants
  where table_schema='public'
    and table_name in ('payment_reminders','payment_notification_events')
    and grantee in ('anon','authenticated','service_role')
), functions as (
  select jsonb_agg(jsonb_build_object(
    'name', p.proname, 'security_definer', p.prosecdef,
    'config', p.proconfig, 'owner', r.rolname
  ) order by p.proname) value
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  join pg_roles r on r.oid=p.proowner
  where n.nspname='public'
    and p.proname in ('set_payment_reminder_updated_at','claim_payment_notification_event')
)
select tables.value tables, triggers.value triggers,
       privileges.value privileges, functions.value functions
from tables, triggers, privileges, functions;
