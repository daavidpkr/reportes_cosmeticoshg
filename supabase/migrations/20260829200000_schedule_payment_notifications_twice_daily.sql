begin;

-- Ecuador is UTC-5 year-round: 05:00 and 12:00 local are 10:00 and 17:00 UTC.
alter table public.notification_runtime_config
  add column if not exists notification_local_times time[] not null
    default array['05:00'::time,'12:00'::time],
  add column if not exists notification_crons_utc text[] not null
    default array['0 10 * * *','0 17 * * *'];

update public.notification_runtime_config set
  business_timezone='America/Guayaquil',
  notification_local_time='05:00',
  notification_cron_utc='0 10 * * *',
  notification_local_times=array['05:00'::time,'12:00'::time],
  notification_crons_utc=array['0 10 * * *','0 17 * * *'],
  updated_at=clock_timestamp()
where singleton;

alter table public.payment_notification_deliveries
  add column if not exists notification_slot text not null default '05:00';

alter table public.payment_notification_deliveries
  drop constraint if exists payment_notification_deliveries_notification_slot_check;
alter table public.payment_notification_deliveries
  add constraint payment_notification_deliveries_notification_slot_check
  check(notification_slot in ('05:00','12:00'));

do $$
declare constraint_name text;
begin
  select c.conname into constraint_name
  from pg_constraint c
  where c.conrelid='public.payment_notification_deliveries'::regclass
    and c.contype='u'
    and (select array_agg(a.attname::text order by key.ord)
         from unnest(c.conkey) with ordinality key(attnum,ord)
         join pg_attribute a on a.attrelid=c.conrelid and a.attnum=key.attnum)
      = array['organization_id','user_id','device_id','notification_date','notification_type'];
  if constraint_name is not null then
    execute format('alter table public.payment_notification_deliveries drop constraint %I',constraint_name);
  end if;
end;
$$;

create unique index if not exists payment_notification_deliveries_daily_slot_key
  on public.payment_notification_deliveries(
    organization_id,user_id,device_id,notification_date,notification_type,
    notification_slot
  );

create function public.claim_same_day_payment_delivery(
  p_organization_id uuid,p_user_id uuid,p_device_id uuid,
  p_notification_date date,p_invoice_count integer,p_notification_slot text
) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
  if p_notification_date is distinct from timezone('America/Guayaquil',clock_timestamp())::date
     or p_invoice_count<=0 or p_notification_slot not in ('05:00','12:00')
  then return null; end if;
  insert into public.payment_notification_deliveries(
    organization_id,user_id,device_id,notification_date,invoice_count,
    notification_slot)
  select p_organization_id,p_user_id,p_device_id,p_notification_date,
    p_invoice_count,p_notification_slot
  where exists(select 1 from public.organizations o where o.id=p_organization_id and o.active)
    and exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=p_user_id and m.active)
    and exists(select 1 from public.fcm_devices d where d.id=p_device_id and d.organization_id=p_organization_id and d.user_id=p_user_id and d.active)
  on conflict do nothing returning id into result;
  return result;
end;
$$;
revoke all on function public.claim_same_day_payment_delivery(uuid,uuid,uuid,date,integer,text)
  from public,anon,authenticated;
grant execute on function public.claim_same_day_payment_delivery(uuid,uuid,uuid,date,integer,text)
  to service_role;

-- Keep version 33 of the Edge Function operational while the new version is
-- deployed. Its five-argument claim maps to the historical/05:00 slot.
create or replace function public.claim_same_day_payment_delivery(
  p_organization_id uuid,p_user_id uuid,p_device_id uuid,
  p_notification_date date,p_invoice_count integer
) returns uuid
language sql security definer set search_path='' as $$
  select public.claim_same_day_payment_delivery(
    p_organization_id,p_user_id,p_device_id,p_notification_date,
    p_invoice_count,'05:00'
  );
$$;
revoke all on function public.claim_same_day_payment_delivery(uuid,uuid,uuid,date,integer)
  from public,anon,authenticated;
grant execute on function public.claim_same_day_payment_delivery(uuid,uuid,uuid,date,integer)
  to service_role;

do $$
declare item record;
begin
  for item in
    select jobid from cron.job
    where jobname in (
      'process-payment-reminders','process-payment-reminders-production',
      'process-same-day-payment-reminders',
      'process-same-day-payment-reminders-0500',
      'process-same-day-payment-reminders-1200'
    ) or command ilike '%process-payment-reminders%'
  loop
    perform cron.unschedule(item.jobid);
  end loop;
end;
$$;

select cron.schedule(
  'process-same-day-payment-reminders-0500','0 10 * * *',$cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='payment_reminders_edge_url'),
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='payment_reminders_cron_secret')
    ),
    body := '{"notification_slot":"05:00"}'::jsonb
  );
  $cron$
);

select cron.schedule(
  'process-same-day-payment-reminders-1200','0 17 * * *',$cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='payment_reminders_edge_url'),
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='payment_reminders_cron_secret')
    ),
    body := '{"notification_slot":"12:00"}'::jsonb
  );
  $cron$
);

drop function if exists public.payment_notification_cron_status();
create function public.payment_notification_cron_status()
returns table(job_name text,schedule text,active boolean,equivalent_jobs bigint)
language sql stable security definer set search_path='' as $$
  select j.jobname,j.schedule,j.active,
    (select count(*) from cron.job x where x.active
      and (x.jobname in ('process-same-day-payment-reminders-0500',
                         'process-same-day-payment-reminders-1200')
           or x.command ilike '%process-payment-reminders%'))
  from cron.job j
  where j.jobname in ('process-same-day-payment-reminders-0500',
                      'process-same-day-payment-reminders-1200')
    and j.active
  order by j.jobname;
$$;
revoke all on function public.payment_notification_cron_status()
  from public,anon,authenticated;
grant execute on function public.payment_notification_cron_status() to service_role;

commit;
