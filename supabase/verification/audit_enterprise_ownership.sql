with auth_summary as (
  select jsonb_build_object(
    'total', count(*),
    'confirmed', count(*) filter (where email_confirmed_at is not null),
    'signed_in_last_30_days', count(*) filter (where last_sign_in_at >= now()-interval '30 days'),
    'never_signed_in', count(*) filter (where last_sign_in_at is null),
    'test_like', count(*) filter (where lower(coalesce(email,'')) ~ '(test|prueba|example|invalid|demo|service|technical)')
  ) value from auth.users
), auth_profiles as (
  select jsonb_agg(jsonb_build_object(
    'ordinal', ordinal,
    'confirmed', confirmed,
    'has_signed_in', has_signed_in,
    'active_last_30_days', active_last_30_days,
    'test_like', test_like,
    'provider', provider
  ) order by ordinal) value
  from (
    select row_number() over(order by created_at)::integer ordinal,
      email_confirmed_at is not null confirmed,
      last_sign_in_at is not null has_signed_in,
      last_sign_in_at >= now()-interval '30 days' active_last_30_days,
      lower(coalesce(email,'')) ~ '(test|prueba|example|invalid|demo|service|technical)' test_like,
      coalesce(raw_app_meta_data->>'provider','unknown') provider
    from auth.users
  ) users
), tables as (
  select jsonb_agg(jsonb_build_object(
    'table', c.relname, 'rls', c.relrowsecurity,
    'rows_estimate', c.reltuples::bigint,
    'has_user_id', exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='user_id' and not a.attisdropped),
    'has_organization_id', exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='organization_id' and not a.attisdropped)
  ) order by c.relname) value
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r'
    and c.relname in ('facturas_maestras','reportes_mensuales','reportes_ventas','vendedores',
      'payment_reminders','payment_followups','payment_notification_events','fcm_devices')
), policies as (
  select jsonb_agg(jsonb_build_object(
    'table', tablename, 'name', policyname, 'command', cmd,
    'roles', roles, 'using', qual, 'check', with_check
  ) order by tablename, policyname) value
  from pg_policies where schemaname='public'
    and tablename in ('facturas_maestras','reportes_mensuales','reportes_ventas','vendedores',
      'payment_reminders','payment_followups','payment_notification_events','fcm_devices')
), counts as (
  select jsonb_build_object(
    'invoices', (select count(*) from public.facturas_maestras),
    'distinct_customer_identities', (select count(*) from (
      select lower(regexp_replace(trim(cliente),'\s+',' ','g')),
             lower(regexp_replace(trim(coalesce(nombre_comercial,'')),'\s+',' ','g'))
      from public.facturas_maestras group by 1,2) c),
    'monthly_reports', (select count(*) from public.reportes_mensuales),
    'report_rows', (select count(*) from public.reportes_ventas),
    'sellers', (select count(*) from public.vendedores),
    'reminders', (select count(*) from public.payment_reminders),
    'followups', (select count(*) from public.payment_followups),
    'notification_events', (select count(*) from public.payment_notification_events),
    'devices', (select count(*) from public.fcm_devices)
  ) value
), integrity as (
  select jsonb_build_object(
    'duplicate_invoice_refs', (select count(*) from (
      select ref_fact from public.facturas_maestras group by ref_fact having count(*)>1) d),
    'report_rows_without_invoice', (select count(*) from public.reportes_ventas r
      left join public.facturas_maestras f on f.ref_fact=r.ref_fact where f.ref_fact is null),
    'reminders_without_invoice', (select count(*) from public.payment_reminders r
      left join public.facturas_maestras f on f.ref_fact=r.factura_id where f.ref_fact is null),
    'followups_without_reminder', (select count(*) from public.payment_followups f
      left join public.payment_reminders r on r.id=f.reminder_id where r.id is null),
    'events_without_reminder', (select count(*) from public.payment_notification_events e
      left join public.payment_reminders r on r.id=e.reminder_id where r.id is null),
    'reminder_distinct_users', (select count(distinct user_id) from public.payment_reminders),
    'device_distinct_users', (select count(distinct user_id) from public.fcm_devices)
  ) value
)
select auth_summary.value auth_summary, auth_profiles.value auth_profiles,
       tables.value tables, policies.value policies,
       counts.value counts, integrity.value integrity
from auth_summary, auth_profiles, tables, policies, counts, integrity;
