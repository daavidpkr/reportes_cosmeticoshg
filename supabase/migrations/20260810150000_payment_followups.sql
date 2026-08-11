begin;

-- Reversible with: drop function/add trigger/table and restore the original
-- status constraint/function from 20260810130000_payment_reminders.sql.
create function public.next_weekday(value date)
returns date language sql immutable strict set search_path = '' as $$
  select case extract(isodow from value)
    when 6 then value + 2
    when 7 then value + 1
    else value
  end;
$$;

create table public.payment_followups (
  id uuid primary key default gen_random_uuid(),
  reminder_id uuid not null references public.payment_reminders(id) on delete restrict,
  request_id uuid not null,
  comment text,
  action_type text not null check (action_type in ('comment', 'reschedule', 'comment_and_reschedule')),
  previous_payment_date date,
  requested_payment_date date,
  effective_payment_date date,
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  constraint payment_followups_comment_length check (comment is null or length(trim(comment)) between 1 and 4000),
  constraint payment_followups_request_key unique (reminder_id, request_id)
);

create index payment_followups_history_idx
  on public.payment_followups (reminder_id, created_at desc);
create index payment_followups_created_by_idx
  on public.payment_followups (created_by);

alter table public.payment_notification_events
  drop constraint payment_notification_events_status_check;
alter table public.payment_notification_events
  add constraint payment_notification_events_status_check check (
    status in ('pending', 'processing', 'sent', 'temporary_failure',
               'permanent_failure', 'no_devices', 'cancelled')
  );

create or replace function public.set_payment_reminder_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.payment_date = case extract(isodow from new.payment_date)
    when 6 then new.payment_date + 2
    when 7 then new.payment_date + 1
    else new.payment_date
  end;
  new.updated_at = now();
  if tg_op = 'UPDATE' and new.payment_date is distinct from old.payment_date then
    new.schedule_version = gen_random_uuid();
  end if;
  return new;
end;
$$;

drop trigger payment_reminders_updated_at on public.payment_reminders;
create trigger payment_reminders_updated_at
before insert or update on public.payment_reminders
for each row execute function public.set_payment_reminder_updated_at();

create function public.add_payment_followup(
  p_reminder_id uuid,
  p_request_id uuid,
  p_comment text default null,
  p_requested_payment_date date default null
) returns table (followup_id uuid, action_type text, effective_payment_date date)
language plpgsql security definer set search_path = '' as $$
declare
  current_reminder public.payment_reminders%rowtype;
  clean_comment text := nullif(trim(p_comment), '');
  effective_date date;
  kind text;
  inserted_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select * into current_reminder from public.payment_reminders
  where id = p_reminder_id and user_id = auth.uid() for update;
  if not found then raise exception 'reminder not found'; end if;
  if clean_comment is null and p_requested_payment_date is null then
    raise exception 'comment or payment date required';
  end if;

  select f.id, f.action_type,
         coalesce(f.effective_payment_date, current_reminder.payment_date)
    into inserted_id, kind, effective_date
  from public.payment_followups f
  where f.reminder_id = p_reminder_id and f.request_id = p_request_id;
  if found then return query select inserted_id, kind, effective_date; return; end if;

  effective_date := coalesce(public.next_weekday(p_requested_payment_date), current_reminder.payment_date);
  kind := case
    when p_requested_payment_date is null then 'comment'
    when clean_comment is null then 'reschedule'
    else 'comment_and_reschedule'
  end;

  if p_requested_payment_date is not null
     and effective_date is distinct from current_reminder.payment_date then
    update public.payment_reminders set payment_date = effective_date
    where id = p_reminder_id;
    update public.payment_notification_events set
      status = 'cancelled', next_retry_at = null,
      last_error_code = 'SCHEDULE_CHANGED', updated_at = now()
    where reminder_id = p_reminder_id
      and schedule_version = current_reminder.schedule_version
      and status in ('pending', 'processing', 'temporary_failure', 'no_devices');
  end if;

  insert into public.payment_followups (
    reminder_id, request_id, comment, action_type, previous_payment_date,
    requested_payment_date, effective_payment_date, created_by
  ) values (
    p_reminder_id, p_request_id, clean_comment, kind,
    case when p_requested_payment_date is null then null else current_reminder.payment_date end,
    p_requested_payment_date,
    case when p_requested_payment_date is null then null else effective_date end,
    auth.uid()
  ) returning id into inserted_id;
  return query select inserted_id, kind, effective_date;
end;
$$;

alter table public.payment_followups enable row level security;
create policy "users read own payment followups" on public.payment_followups
for select to authenticated using (exists (
  select 1 from public.payment_reminders r
  where r.id = reminder_id and r.user_id = auth.uid()
));

revoke all on public.payment_followups from public, anon, authenticated;
grant select on public.payment_followups to authenticated;
grant select on public.payment_followups to service_role;
revoke all on function public.add_payment_followup(uuid, uuid, text, date) from public, anon;
grant execute on function public.add_payment_followup(uuid, uuid, text, date) to authenticated;
revoke all on function public.next_weekday(date) from public, anon, authenticated;

commit;
