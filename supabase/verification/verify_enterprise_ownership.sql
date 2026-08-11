-- Prepared for a disposable database after applying 160100-160300.
-- All synthetic records must be created inside this transaction.
begin;

select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid in ('public.organizations'::regclass,
                   'public.organization_members'::regclass,
                   'public.billing_customers'::regclass,
                   'public.invoice_payment_terms'::regclass)
order by conname;

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename in
  ('organizations','organization_members','billing_customers','invoice_payment_terms')
order by tablename,policyname;

select p.proname,p.prosecdef,p.proconfig,
       has_function_privilege('anon',p.oid,'execute') anon_execute,
       has_function_privilege('authenticated',p.oid,'execute') authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
  ('current_organization_id','require_current_organization_id',
   'enterprise_upsert_invoice','preview_enterprise_customer_term',
   'save_enterprise_customer_term','save_enterprise_invoice_exception')
order by p.proname;

-- The deployment-stage test must add two organizations, two members in one,
-- one member in the other, an inactive membership and an authenticated
-- non-member. It must assert shared access within one organization, rejection
-- across organizations/anon/inactive/non-member, normalized customer
-- idempotency, manual-date confirmation, schedule/event/history atomicity and
-- repeated request_id behavior. It deliberately remains non-executable until
-- the exact administrative test identities are authorized.

rollback;
