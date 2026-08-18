begin;

do $$
declare
  target_organization uuid;
  target_devices uuid[];
  target_users uuid[];
begin
  select d.organization_id into target_organization
  from public.fcm_devices d
  join public.organization_members m
    on m.organization_id=d.organization_id
   and m.user_id=d.user_id
   and m.active
  join public.organizations o
    on o.id=d.organization_id and o.active
  where d.active and d.platform='android'
  order by d.last_seen_at desc
  limit 1;

  if target_organization is null then
    raise exception 'No active Android organization found';
  end if;

  select array_agg(d.id order by d.id),array_agg(distinct d.user_id)
    into target_devices,target_users
  from public.fcm_devices d
  join public.organization_members m
    on m.organization_id=d.organization_id
   and m.user_id=d.user_id
   and m.active
  join public.organizations o
    on o.id=d.organization_id and o.active
  where d.organization_id=target_organization
    and d.active
    and d.platform='android';

  if coalesce(cardinality(target_devices),0)<>5 then
    raise exception 'Expected exactly 5 active authorized Android devices';
  end if;

  update public.fcm_devices
  set active=false,updated_at=clock_timestamp()
  where id=any(target_devices) and active;

  if not found then
    raise exception 'No device was deactivated';
  end if;

  delete from auth.sessions where user_id=any(target_users);
end;
$$;

commit;
