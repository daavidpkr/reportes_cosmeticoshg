-- Execute only after applying 20260810160000 in a disposable environment.
begin;

select public.calculate_customer_payment_date(date '2026-08-10', 0) = date '2026-08-10' as zero_days_ok,
       public.calculate_customer_payment_date(date '2026-08-14', 1) = date '2026-08-17' as saturday_ok,
       public.calculate_customer_payment_date(date '2026-08-14', 2) = date '2026-08-17' as sunday_ok,
       public.parse_invoice_date('10/08/2026') = date '2026-08-10' as dmy_ok,
       public.parse_invoice_date('2026-08-10') = date '2026-08-10' as ymd_ok;

select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid in ('public.billing_customers'::regclass,
                   'public.invoice_payment_terms'::regclass)
order by conname;

select tablename, policyname, cmd, roles
from pg_policies
where schemaname='public'
  and tablename in ('billing_customers','invoice_payment_terms')
order by tablename, policyname;

select p.proname, p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'execute') anon_execute,
       has_function_privilege('authenticated', p.oid, 'execute') authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'sync_existing_customer_catalog','preview_customer_term_impact',
  'save_customer_payment_term','save_invoice_payment_exception'
)
order by p.proname;

rollback;
