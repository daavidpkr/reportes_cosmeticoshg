begin;

-- Expose the contact evidence already stored by 20261024170000 without ever
-- returning the internal buyer identification.
create or replace function public.get_customer_profile(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare org uuid := public.require_current_organization_id(); result jsonb;
begin
  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'commercial_name', c.commercial_name,
    'payment_term_days', c.payment_term_days,
    'horario_atencion', c.horario_atencion,
    'configuration_active', c.configuration_active,
    'address', c.address,
    'phone', c.phone,
    'email', c.email,
    'contact_invoice_date', c.contact_invoice_date,
    'contact_invoice_ref', c.contact_invoice_ref
  ) into result
  from public.billing_customers c
  where c.id = p_customer_id and c.organization_id = org;
  if result is null then raise exception 'enterprise customer not found'; end if;
  return result;
end;
$$;

create or replace function public.update_customer_contact(
  p_customer_id uuid, p_address text, p_phone text, p_email text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  normalized_address text := public.clean_buyer_address(p_address);
  normalized_phone text := public.clean_buyer_phone(p_phone);
  normalized_email text := public.clean_buyer_email(p_email);
  result jsonb;
begin
  if trim(coalesce(p_phone, '')) <> '' and normalized_phone = '' then
    raise exception 'invalid customer phone';
  end if;
  if trim(coalesce(p_email, '')) <> '' and normalized_email = '' then
    raise exception 'invalid customer email';
  end if;

  update public.billing_customers c set
    address = normalized_address,
    phone = normalized_phone,
    email = normalized_email,
    updated_at = clock_timestamp(),
    updated_by = auth.uid()
  where c.id = p_customer_id and c.organization_id = org
    and c.configuration_active
  returning public.get_customer_profile(c.id) into result;
  if result is null then
    raise exception 'enterprise customer not available for editing';
  end if;
  return result;
end;
$$;

-- Extend the canonical history RPC in place so partial payments can be
-- filtered and counted without introducing a second history implementation.
do $$
declare definition text; updated text;
begin
  select pg_get_functiondef(
    'public.list_customer_invoice_history(uuid,integer,integer,text,text,text)'::regprocedure
  ) into definition;
  updated := replace(definition,
    $find$p_status not in ('all','pending','paid','overdue','cancelled')$find$,
    $find$p_status not in ('all','pending','partial','paid','overdue','cancelled')$find$);
  updated := replace(updated,
    $find$when 'paid' then not cancelled and balance <= .005$find$,
    $find$when 'partial' then not cancelled and paid > .005 and balance > .005
      when 'paid' then not cancelled and balance <= .005$find$);
  updated := replace(updated,
    $find$'paid_invoices', count(*) filter (where not cancelled and balance <= .005),$find$,
    $find$'paid_invoices', count(*) filter (where not cancelled and balance <= .005),
        'partial_invoices', count(*) filter (
          where not cancelled and paid > .005 and balance > .005
        ),$find$);
  if updated = definition
     or position($find$'partial_invoices'$find$ in updated) = 0
     or position($find$when 'partial'$find$ in updated) = 0 then
    raise exception 'customer history definition is not compatible';
  end if;
  execute updated;
end;
$$;

revoke all on function public.get_customer_profile(uuid) from public, anon;
revoke all on function public.update_customer_contact(uuid,text,text,text)
  from public, anon;
grant execute on function public.get_customer_profile(uuid) to authenticated;
grant execute on function public.update_customer_contact(uuid,text,text,text)
  to authenticated;

notify pgrst, 'reload schema';
commit;
