with columns_audit as (
  select jsonb_agg(jsonb_build_object(
    'table', table_name, 'column', column_name,
    'type', data_type, 'udt', udt_name, 'nullable', is_nullable
  ) order by table_name, ordinal_position) value
  from information_schema.columns
  where table_schema='public'
    and ((table_name='payment_reminders' and column_name in ('id','payment_date','schedule_version','user_id'))
      or (table_name='payment_notification_events' and column_name in ('id','reminder_id','schedule_version','scheduled_for','status')))
), constraints_audit as (
  select jsonb_agg(jsonb_build_object(
    'table', c.relname, 'name', con.conname,
    'definition', pg_get_constraintdef(con.oid)
  ) order by c.relname, con.conname) value
  from pg_constraint con join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in ('payment_reminders','payment_notification_events')
), policies_audit as (
  select jsonb_agg(jsonb_build_object(
    'table', tablename, 'name', policyname, 'command', cmd,
    'roles', roles, 'using', qual, 'check', with_check
  ) order by tablename, policyname) value
  from pg_policies
  where schemaname='public' and tablename in ('payment_reminders','payment_notification_events')
), event_states as (
  select coalesce(jsonb_object_agg(status, amount), '{}'::jsonb) value
  from (select status, count(*) amount from public.payment_notification_events group by status) s
), weekend as (
  select jsonb_build_object(
    'total', count(*),
    'saturday', count(*) filter (where extract(isodow from payment_date)=6),
    'sunday', count(*) filter (where extract(isodow from payment_date)=7)
  ) value
  from public.payment_reminders
  where active and payment_date > current_date
    and extract(isodow from payment_date) in (6,7)
), inactive as (
  select jsonb_build_object(
    'total', count(*),
    'future_weekend', count(*) filter (
      where payment_date > current_date and extract(isodow from payment_date) in (6,7)
    )
  ) value from public.payment_reminders where not active
), status_columns as (
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='payment_reminders'
      and column_name in ('status','state','paid','closed','payment_status')
  ) value
), cron_audit as (
  select jsonb_agg(jsonb_build_object(
    'name', jobname, 'schedule', schedule, 'active', active
  )) value from cron.job where jobname='process-payment-reminders-production'
)
select columns_audit.value columns,
       constraints_audit.value constraints,
       policies_audit.value policies,
       event_states.value event_states,
       weekend.value active_future_weekend,
       inactive.value inactive_reminders,
       status_columns.value has_closed_or_paid_column,
       cron_audit.value cron
from columns_audit, constraints_audit, policies_audit, event_states,
     weekend, inactive, status_columns, cron_audit;
