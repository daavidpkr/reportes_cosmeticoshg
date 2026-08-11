-- Run after applying the migration in a disposable/local database.
begin;
select public.next_weekday(date '2026-08-10') = date '2026-08-10' as monday_ok,
       public.next_weekday(date '2026-08-14') = date '2026-08-14' as friday_ok,
       public.next_weekday(date '2026-08-15') = date '2026-08-17' as saturday_ok,
       public.next_weekday(date '2026-08-16') = date '2026-08-17' as sunday_ok;
select conname from pg_constraint
where conrelid = 'public.payment_followups'::regclass;
select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'payment_followups';
rollback;

-- Production read-only audit to run BEFORE any separately authorized backfill:
-- select count(*) from public.payment_reminders
-- where active and payment_date > current_date
--   and extract(isodow from payment_date) in (6, 7);
