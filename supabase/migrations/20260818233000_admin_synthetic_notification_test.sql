begin;

create table public.notification_test_executions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  operation text not null default 'organization_android_test'
    check (operation = 'organization_android_test'),
  local_date date not null,
  status text not null default 'prepared'
    check (status in ('prepared','sending','completed','failed')),
  eligible_count integer not null check (eligible_count >= 0),
  duplicate_count integer not null default 0 check (duplicate_count >= 0),
  sent_count integer not null default 0 check (sent_count >= 0),
  invalid_token_count integer not null default 0 check (invalid_token_count >= 0),
  failure_count integer not null default 0 check (failure_count >= 0),
  prepared_at timestamptz not null default clock_timestamp(),
  started_at timestamptz,
  completed_at timestamptz
);

create table public.notification_test_recipients (
  execution_id uuid not null references public.notification_test_executions(id) on delete restrict,
  device_id uuid not null references public.fcm_devices(id) on delete restrict,
  token_fingerprint text not null check (length(token_fingerprint) = 64),
  status text not null default 'prepared'
    check (status in ('prepared','sent','invalid_token','failed','skipped')),
  failure_code text,
  provider_message_id text,
  attempted_at timestamptz,
  sent_at timestamptz,
  primary key (execution_id, device_id),
  unique (execution_id, token_fingerprint)
);

alter table public.notification_test_executions enable row level security;
alter table public.notification_test_recipients enable row level security;
revoke all on public.notification_test_executions,
  public.notification_test_recipients from public, anon, authenticated;
grant select, insert, update on public.notification_test_executions,
  public.notification_test_recipients to service_role;

commit;
