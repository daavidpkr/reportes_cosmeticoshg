begin;

-- Read the profile in a new statement after the update so the RPC always
-- returns the values that were just persisted.
create or replace function public.update_customer_contact(
  p_customer_id uuid, p_address text, p_phone text, p_email text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  normalized_address text := public.clean_buyer_address(p_address);
  normalized_phone text := public.clean_buyer_phone(p_phone);
  normalized_email text := public.clean_buyer_email(p_email);
  affected integer;
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
    and c.configuration_active;
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'enterprise customer not available for editing';
  end if;
  return public.get_customer_profile(p_customer_id);
end;
$$;

revoke all on function public.update_customer_contact(uuid,text,text,text)
  from public, anon;
grant execute on function public.update_customer_contact(uuid,text,text,text)
  to authenticated;

notify pgrst, 'reload schema';
commit;
