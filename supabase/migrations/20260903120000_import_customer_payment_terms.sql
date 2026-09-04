-- Preserve the deployed importer and add missing payment terms atomically.
-- The previous implementation remains the single source for invoices, sellers
-- and reminder creation; this wrapper only fills a currently-null term.
alter function public.enterprise_import_monthly_invoices(uuid, integer, integer, jsonb)
  rename to enterprise_import_monthly_invoices_without_terms;

create function public.enterprise_import_monthly_invoices(
  p_request_id uuid, p_year integer, p_month integer, p_invoices jsonb
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  imported integer;
  item jsonb;
  proposed_days integer;
  customer record;
begin
  if p_invoices is null or jsonb_typeof(p_invoices) <> 'array' then
    raise exception 'invalid monthly invoice batch';
  end if;
  -- Validate values before the legacy importer writes anything.  Null means a
  -- term was already configured and must never be overwritten.
  for item in select value from jsonb_array_elements(p_invoices) loop
    if item ? 'payment_term_days' then
      begin proposed_days := (item->>'payment_term_days')::integer;
      exception when others then raise exception 'invalid payment term'; end;
      if proposed_days < 0 or proposed_days > 3650 then
        raise exception 'invalid payment term';
      end if;
    end if;
  end loop;

  imported := public.enterprise_import_monthly_invoices_without_terms(
    p_request_id, p_year, p_month, p_invoices);

  for item in select value from jsonb_array_elements(p_invoices) loop
    if not (item ? 'payment_term_days') then continue; end if;
    proposed_days := (item->>'payment_term_days')::integer;
    select c.* into customer from public.billing_customers c
      where c.organization_id = org
        and c.normalized_name = lower(trim(coalesce(item->>'cliente','')))
        and c.normalized_commercial_name = lower(trim(coalesce(item->>'nombre_comercial','')))
      for update;
    if not found then raise exception 'customer could not be resolved'; end if;
    if customer.payment_term_days is null then
      update public.billing_customers set payment_term_days = proposed_days,
        updated_at = clock_timestamp(), updated_by = auth.uid()
        where id = customer.id and payment_term_days is null;
    elsif customer.payment_term_days <> proposed_days then
      raise exception 'payment term changed concurrently for customer %', customer.name;
    end if;
  end loop;
  return imported;
end;
$$;

revoke all on function public.enterprise_import_monthly_invoices(uuid,integer,integer,jsonb)
  from public, anon;
grant execute on function public.enterprise_import_monthly_invoices(uuid,integer,integer,jsonb)
  to authenticated;
notify pgrst, 'reload schema';
