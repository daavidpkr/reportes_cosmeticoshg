begin;

-- Deployment-time integration check. The synthetic customer is removed before
-- commit, so this verifies the real RPC and database without retaining test data.
do $$
declare
  member record;
  synthetic_id uuid := gen_random_uuid();
  saved jsonb;
  reloaded jsonb;
begin
  select m.user_id, m.organization_id into member
  from public.organization_members m
  where m.active
  order by m.created_at
  limit 1;
  if member is null then raise exception 'business-hours verification requires an active member'; end if;

  insert into public.billing_customers(
    id, organization_id, name, commercial_name
  ) values (
    synthetic_id, member.organization_id,
    'SYNTHETIC HOURS ROLLBACK ' || synthetic_id::text, 'TEST ONLY'
  );

  perform set_config('request.jwt.claim.sub', member.user_id::text, true);
  saved := public.update_customer_business_hours(
    synthetic_id, '  Lunes a sábado, 08:30 - 19:00  ');
  reloaded := public.get_customer_profile(synthetic_id);
  if saved->>'horario_atencion' <> 'Lunes a sábado, 08:30 - 19:00'
      or reloaded->>'horario_atencion' <> saved->>'horario_atencion' then
    raise exception 'business hours did not normalize and persist';
  end if;

  begin
    perform public.update_customer_business_hours(synthetic_id, repeat('x', 121));
    raise exception 'business hours length validation did not run';
  exception when others then
    if sqlerrm = 'business hours length validation did not run' then raise; end if;
  end;

  update public.billing_customers
  set configuration_active = false
  where id = synthetic_id;
  begin
    perform public.update_customer_business_hours(synthetic_id, 'changed');
    raise exception 'inactive customer remained editable';
  exception when others then
    if sqlerrm = 'inactive customer remained editable' then raise; end if;
  end;

  delete from public.billing_customers where id = synthetic_id;
  if exists(select 1 from public.billing_customers where id = synthetic_id) then
    raise exception 'synthetic customer cleanup failed';
  end if;
end;
$$;

commit;
