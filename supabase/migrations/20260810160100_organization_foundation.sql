begin;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin','member')),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  created_by uuid references auth.users(id) on delete restrict,
  primary key (organization_id, user_id),
  check ((active and revoked_at is null) or (not active))
);

create unique index organization_members_one_active_org_per_user
  on public.organization_members(user_id) where active;
create index organization_members_org_active_idx
  on public.organization_members(organization_id, active);
create unique index organizations_normalized_name_key
  on public.organizations(lower(regexp_replace(trim(name),'\s+',' ','g')));

create function public.current_organization_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select m.organization_id from public.organization_members m
  join public.organizations o on o.id=m.organization_id
  where m.user_id=auth.uid() and m.active and o.active
  limit 1;
$$;

create function public.require_current_organization_id()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare result uuid;
begin
  result := public.current_organization_id();
  if result is null then raise exception 'active organization membership required'; end if;
  return result;
end;
$$;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
create policy "members read active organization" on public.organizations
for select to authenticated using (id=public.current_organization_id() and active);
create policy "members read own membership" on public.organization_members
for select to authenticated using (user_id=auth.uid());

revoke all on public.organizations, public.organization_members from public, anon, authenticated;
grant select on public.organizations, public.organization_members to authenticated;
grant select, insert, update on public.organizations, public.organization_members to service_role;
revoke all on function public.current_organization_id() from public, anon;
revoke all on function public.require_current_organization_id() from public, anon;
grant execute on function public.current_organization_id() to authenticated, service_role;
grant execute on function public.require_current_organization_id() to authenticated, service_role;

commit;
