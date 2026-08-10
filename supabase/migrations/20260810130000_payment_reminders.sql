begin;

create table public.payment_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  factura_id text not null references public.facturas_maestras(ref_fact) on update cascade on delete cascade,
  payment_date date not null,
  active boolean not null default true,
  notify_three_days boolean not null default true,
  notify_one_day boolean not null default true,
  schedule_version uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_reminders_notice_enabled check (notify_three_days or notify_one_day),
  constraint payment_reminders_user_factura_key unique (user_id, factura_id)
);

create table public.fcm_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table public.payment_notification_events (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references public.payment_reminders(id) on delete cascade,
  schedule_version uuid not null,
  device_id uuid references public.fcm_devices(id) on delete set null,
  notice_type text not null check (notice_type in ('three_days', 'one_day')),
  scheduled_for date not null,
  status text not null default 'pending' check (status in ('pending', 'processing', 'sent', 'temporary_failure', 'permanent_failure', 'no_devices')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  fcm_message_id text,
  last_error_code text,
  next_retry_at timestamptz,
  claimed_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index payment_notification_events_device_key
  on public.payment_notification_events (reminder_id, schedule_version, notice_type, device_id)
  where device_id is not null;
create unique index payment_notification_events_no_devices_key
  on public.payment_notification_events (reminder_id, schedule_version, notice_type)
  where device_id is null;
create index payment_reminders_due_idx
  on public.payment_reminders (payment_date, active) where active;
create index payment_reminders_user_idx on public.payment_reminders (user_id);
create index fcm_devices_user_active_idx on public.fcm_devices (user_id, active);
create index payment_notification_events_retry_idx
  on public.payment_notification_events (status, next_retry_at);

create function public.set_payment_reminder_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  if new.payment_date is distinct from old.payment_date then
    new.schedule_version = gen_random_uuid();
  end if;
  return new;
end;
$$;

create trigger payment_reminders_updated_at before update on public.payment_reminders
for each row execute function public.set_payment_reminder_updated_at();

create function public.register_fcm_device(device_token text, device_platform text default 'android')
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare result uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if length(trim(device_token)) < 20 or length(device_token) > 4096 then raise exception 'invalid token'; end if;
  if device_platform <> 'android' then raise exception 'unsupported platform'; end if;
  insert into public.fcm_devices (user_id, token, platform, active, last_seen_at)
  values (auth.uid(), device_token, device_platform, true, now())
  on conflict (token) do update set
    user_id = excluded.user_id, platform = excluded.platform, active = true,
    last_seen_at = now(), updated_at = now()
  returning id into result;
  return result;
end;
$$;

create function public.deactivate_fcm_device(device_token text)
returns void language sql security definer set search_path = ''
as $$
  update public.fcm_devices set active = false, updated_at = now()
  where token = device_token and user_id = auth.uid();
$$;

create function public.claim_payment_notification_event(
  p_reminder_id uuid, p_schedule_version uuid, p_device_id uuid,
  p_notice_type text, p_scheduled_for date
) returns table (event_id uuid, attempt_count integer)
language plpgsql security definer set search_path = ''
as $$
begin
  return query
  insert into public.payment_notification_events
    (reminder_id, schedule_version, device_id, notice_type, scheduled_for, status, claimed_at)
  values
    (p_reminder_id, p_schedule_version, p_device_id, p_notice_type, p_scheduled_for, 'processing', now())
  on conflict (reminder_id, schedule_version, notice_type, device_id)
    where device_id is not null do nothing
  returning id, payment_notification_events.attempt_count;
  if found then return; end if;

  return query
  update public.payment_notification_events e
  set status = 'processing', claimed_at = now(), updated_at = now()
  where e.reminder_id = p_reminder_id
    and e.schedule_version = p_schedule_version
    and e.device_id = p_device_id
    and e.notice_type = p_notice_type
    and (
      (e.status = 'temporary_failure' and coalesce(e.next_retry_at, now()) <= now())
      or (e.status = 'processing' and e.claimed_at < now() - interval '10 minutes')
    )
  returning e.id, e.attempt_count;
end;
$$;

revoke all on function public.register_fcm_device(text, text) from public;
revoke all on function public.deactivate_fcm_device(text) from public;
revoke all on function public.claim_payment_notification_event(uuid, uuid, uuid, text, date) from public, anon, authenticated;
revoke all on function public.set_payment_reminder_updated_at() from public, anon, authenticated;
grant execute on function public.register_fcm_device(text, text) to authenticated;
grant execute on function public.deactivate_fcm_device(text) to authenticated;
grant execute on function public.claim_payment_notification_event(uuid, uuid, uuid, text, date) to service_role;

alter table public.payment_reminders enable row level security;
alter table public.fcm_devices enable row level security;
alter table public.payment_notification_events enable row level security;

create policy "users read own reminders" on public.payment_reminders for select to authenticated using (user_id = auth.uid());
create policy "users insert own valid reminders" on public.payment_reminders for insert to authenticated
with check (user_id = auth.uid() and exists (select 1 from public.facturas_maestras f where f.ref_fact = factura_id));
create policy "users update own valid reminders" on public.payment_reminders for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid() and exists (select 1 from public.facturas_maestras f where f.ref_fact = factura_id));
create policy "users delete own reminders" on public.payment_reminders for delete to authenticated using (user_id = auth.uid());
create policy "users read own devices" on public.fcm_devices for select to authenticated using (user_id = auth.uid());

revoke all on public.payment_reminders from anon, authenticated;
revoke all on public.fcm_devices from anon, authenticated;
revoke all on public.payment_notification_events from anon, authenticated;
grant select, insert, update, delete on public.payment_reminders to authenticated;
grant select on public.fcm_devices to authenticated;
grant select on public.payment_reminders to service_role;
grant select, update on public.fcm_devices to service_role;
grant select, insert, update on public.payment_notification_events to service_role;

commit;
