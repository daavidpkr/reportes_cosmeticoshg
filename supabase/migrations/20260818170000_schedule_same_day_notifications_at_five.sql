begin;

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create table public.notification_runtime_config (
  singleton boolean primary key default true check (singleton),
  business_timezone text not null,
  notification_local_time time not null,
  notification_cron_utc text not null,
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.notification_runtime_config enable row level security;
revoke all on public.notification_runtime_config from public,anon,authenticated;
grant select on public.notification_runtime_config to service_role;
insert into public.notification_runtime_config(
  singleton,business_timezone,notification_local_time,notification_cron_utc)
values(true,'America/Guayaquil','05:00','0 10 * * *')
on conflict(singleton) do update set
  business_timezone=excluded.business_timezone,
  notification_local_time=excluded.notification_local_time,
  notification_cron_utc=excluded.notification_cron_utc,
  updated_at=clock_timestamp();

do $$
declare item record;
begin
  for item in
    select jobid from cron.job
    where jobname in ('process-payment-reminders','process-same-day-payment-reminders')
       or command ilike '%process-payment-reminders%'
  loop
    perform cron.unschedule(item.jobid);
  end loop;

  if not exists(select 1 from vault.decrypted_secrets where name='payment_reminders_cron_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32),'hex'),
      'payment_reminders_cron_secret',
      'Generated credential for the same-day payment reminder Cron'
    );
  end if;
  if not exists(select 1 from vault.decrypted_secrets where name='payment_reminders_edge_url') then
    perform vault.create_secret(
      'https://bwtybktztmlucgtpczzg.supabase.co/functions/v1/process-payment-reminders',
      'payment_reminders_edge_url',
      'Edge Function URL for the same-day payment reminder Cron'
    );
  end if;
end;
$$;

create function public.authorize_payment_notification_cron(p_secret text)
returns boolean language sql security definer set search_path='' as $$
  select exists(
    select 1 from vault.decrypted_secrets s
    where s.name='payment_reminders_cron_secret'
      and extensions.digest(s.decrypted_secret,'sha256')
          =extensions.digest(coalesce(p_secret,''),'sha256')
  );
$$;
revoke all on function public.authorize_payment_notification_cron(text)
  from public,anon,authenticated;
grant execute on function public.authorize_payment_notification_cron(text)
  to service_role;

select cron.schedule(
  'process-same-day-payment-reminders',
  '0 10 * * *',
  $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name='payment_reminders_edge_url'),
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer '||(select decrypted_secret
        from vault.decrypted_secrets where name='payment_reminders_cron_secret')
    ),
    body := '{}'::jsonb
  );
  $cron$
);

create function public.payment_notification_cron_status()
returns table(job_name text,schedule text,active boolean,equivalent_jobs bigint)
language sql stable security definer set search_path='' as $$
  select j.jobname,j.schedule,j.active,
    (select count(*) from cron.job x where x.active
      and (x.jobname in ('process-payment-reminders','process-same-day-payment-reminders')
        or x.command ilike '%process-payment-reminders%'))
  from cron.job j where j.jobname='process-same-day-payment-reminders';
$$;
revoke all on function public.payment_notification_cron_status()
  from public,anon,authenticated;
grant execute on function public.payment_notification_cron_status() to service_role;

create table public.notification_test_deliveries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null references public.fcm_devices(id) on delete cascade,
  request_id uuid not null,
  local_date date not null,
  status text not null default 'processing'
    check(status in ('processing','sent','failed','invalid_token')),
  provider_message_id text,
  failure_code text,
  attempted_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  unique(user_id,device_id,request_id)
);
alter table public.notification_test_deliveries enable row level security;
revoke all on public.notification_test_deliveries from public,anon,authenticated;
grant select,insert,update on public.notification_test_deliveries to service_role;

create function public.list_my_notification_devices()
returns table(device_id uuid,platform text,last_seen_at timestamptz,fingerprint text)
language sql stable security definer set search_path='' as $$
  select d.id,d.platform,d.last_seen_at,
    right(encode(extensions.digest(d.token,'sha256'),'hex'),4)
  from public.fcm_devices d
  join public.organization_members m
    on m.organization_id=d.organization_id and m.user_id=d.user_id and m.active
  join public.organizations o on o.id=d.organization_id and o.active
  where d.user_id=auth.uid() and d.active
  order by d.last_seen_at desc;
$$;
revoke all on function public.list_my_notification_devices() from public,anon;
grant execute on function public.list_my_notification_devices() to authenticated;

create function public.claim_notification_test_delivery(
  p_user_id uuid,p_device_id uuid,p_request_id uuid,p_local_date date
) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; org uuid;
begin
  if p_local_date is distinct from timezone('America/Guayaquil',clock_timestamp())::date
     or p_request_id is null then return null; end if;
  select d.organization_id into org from public.fcm_devices d
  join public.organization_members m
    on m.organization_id=d.organization_id and m.user_id=d.user_id and m.active
  join public.organizations o on o.id=d.organization_id and o.active
  where d.id=p_device_id and d.user_id=p_user_id and d.active;
  if org is null then return null; end if;
  if exists(select 1 from public.notification_test_deliveries t
    where t.user_id=p_user_id and t.attempted_at>clock_timestamp()-interval '1 minute')
  then return null; end if;
  insert into public.notification_test_deliveries(
    organization_id,user_id,device_id,request_id,local_date)
  values(org,p_user_id,p_device_id,p_request_id,p_local_date)
  on conflict do nothing returning id into result;
  return result;
end;
$$;
revoke all on function public.claim_notification_test_delivery(uuid,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function public.claim_notification_test_delivery(uuid,uuid,uuid,date)
  to service_role;

commit;
