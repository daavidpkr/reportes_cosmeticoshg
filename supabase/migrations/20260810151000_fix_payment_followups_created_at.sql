begin;

-- clock_timestamp() distinguishes multiple audit entries created in the same
-- database transaction; now() would give all of them the transaction start.
alter table public.payment_followups
  alter column created_at set default clock_timestamp();

commit;
