begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data
) values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'payment-followup-1@example.invalid', '', now(), '{}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'payment-followup-2@example.invalid', '', now(), '{}', '{}');

insert into public.facturas_maestras
  (cliente, fecha, nombre_comercial, nro_fact, ref_fact, venta)
values
  ('PRUEBA RPC', '2026-08-10', 'PRUEBA RPC', 'TEST-RPC-001', 'TEST-RPC-001', 1);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);

insert into public.payment_reminders (
  id, user_id, factura_id, payment_date, active,
  notify_three_days, notify_one_day, schedule_version
) values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', 'TEST-RPC-001',
  date '2026-08-10', true, true, true,
  '30000000-0000-4000-8000-000000000001'
);

set local role authenticated;

do $$
declare original_version uuid; returned_id uuid;
begin
  select schedule_version into original_version from public.payment_reminders
  where id='20000000-0000-4000-8000-000000000001';

  select followup_id into returned_id from public.add_payment_followup(
    '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001', 'Primer comentario', null);
  perform public.add_payment_followup(
    '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000002', 'Segundo comentario', null);

  if (select payment_date <> date '2026-08-10' or schedule_version <> original_version
      from public.payment_reminders where id='20000000-0000-4000-8000-000000000001') then
    raise exception 'comment changed reminder schedule';
  end if;
  if (select count(*) <> 2 from public.payment_followups
      where reminder_id='20000000-0000-4000-8000-000000000001') then
    raise exception 'comments were not preserved';
  end if;
  if (select min(created_at) >= max(created_at) from public.payment_followups
      where reminder_id='20000000-0000-4000-8000-000000000001') then
    raise exception 'timestamps are not strictly orderable';
  end if;
  if (select count(*) <> 2 from public.payment_followups
      where reminder_id='20000000-0000-4000-8000-000000000001'
        and created_by='10000000-0000-4000-8000-000000000001') then
    raise exception 'created_by did not come from auth.uid';
  end if;
  if (select comment <> 'Segundo comentario' from public.payment_followups
      where reminder_id='20000000-0000-4000-8000-000000000001'
      order by created_at desc, id desc limit 1) then
    raise exception 'history order is incorrect';
  end if;

  if returned_id <> (select followup_id from public.add_payment_followup(
    '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001', 'ignored duplicate', null)) then
    raise exception 'request id is not idempotent';
  end if;
  if (select count(*) <> 2 from public.payment_followups
      where reminder_id='20000000-0000-4000-8000-000000000001') then
    raise exception 'duplicate request created a row';
  end if;
end $$;

do $$
declare version_before uuid; version_after uuid;
begin
  select schedule_version into version_before from public.payment_reminders
  where id='20000000-0000-4000-8000-000000000001';
  perform public.add_payment_followup(
    '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000003', null, date '2026-08-14');
  select schedule_version into version_after from public.payment_reminders
  where id='20000000-0000-4000-8000-000000000001';
  if version_after = version_before then raise exception 'weekday did not change version'; end if;
  if (select payment_date <> date '2026-08-14' from public.payment_reminders
      where id='20000000-0000-4000-8000-000000000001') then
    raise exception 'weekday changed unexpectedly';
  end if;

  version_before := version_after;
  perform public.add_payment_followup(
    '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000004', null, date '2026-08-15');
  select schedule_version into version_after from public.payment_reminders
  where id='20000000-0000-4000-8000-000000000001';
  if version_after = version_before then raise exception 'saturday did not change version'; end if;
  if (select payment_date <> date '2026-08-17' from public.payment_reminders
      where id='20000000-0000-4000-8000-000000000001') then
    raise exception 'saturday was not moved to monday';
  end if;
  if (select requested_payment_date <> date '2026-08-15'
          or effective_payment_date <> date '2026-08-17'
      from public.payment_followups where request_id='40000000-0000-4000-8000-000000000004') then
    raise exception 'saturday history is incorrect';
  end if;

  version_before := version_after;
  perform public.add_payment_followup(
    '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000005', null, date '2026-08-16');
  select schedule_version into version_after from public.payment_reminders
  where id='20000000-0000-4000-8000-000000000001';
  if version_after <> version_before then raise exception 'same effective monday changed version'; end if;
  if (select effective_payment_date <> date '2026-08-17'
      from public.payment_followups where request_id='40000000-0000-4000-8000-000000000005') then
    raise exception 'sunday was not moved to monday';
  end if;
end $$;

reset role;

insert into public.payment_notification_events (
  id, reminder_id, schedule_version, notice_type, scheduled_for, status
) values
  ('50000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
   (select schedule_version from public.payment_reminders where id='20000000-0000-4000-8000-000000000001'),
   'three_days', date '2026-08-17', 'pending'),
  ('50000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001',
   (select schedule_version from public.payment_reminders where id='20000000-0000-4000-8000-000000000001'),
   'one_day', date '2026-08-17', 'sent');

set local role authenticated;
do $$
declare old_version uuid; new_version uuid;
begin
  select schedule_version into old_version from public.payment_reminders
  where id='20000000-0000-4000-8000-000000000001';
  perform public.add_payment_followup(
    '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000006', 'Cambio con eventos', date '2026-08-18');
  select schedule_version into new_version from public.payment_reminders
  where id='20000000-0000-4000-8000-000000000001';
  if new_version = old_version then raise exception 'reschedule did not rotate version'; end if;
  begin
    perform public.add_payment_followup(
      '20000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000007', repeat('x', 4001), date '2026-08-19');
    raise exception 'expected atomic failure did not occur';
  exception when check_violation then null;
  end;
  if (select payment_date <> date '2026-08-18' or schedule_version <> new_version
      from public.payment_reminders where id='20000000-0000-4000-8000-000000000001') then
    raise exception 'failed operation was partially applied';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
do $$
declare affected integer;
begin
  begin
    perform public.add_payment_followup(
      '20000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000008', 'unauthorized', null);
    raise exception 'other user was accepted';
  exception when others then
    if sqlerrm = 'other user was accepted' then raise; end if;
  end;
  if (select count(*) <> 0 from public.payment_followups) then
    raise exception 'RLS exposed another user history';
  end if;
  update public.payment_reminders set active=false
  where id='20000000-0000-4000-8000-000000000001';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'RLS modified another user reminder'; end if;
end $$;

reset role;

do $$
begin
  if (select status <> 'cancelled' from public.payment_notification_events
      where id='50000000-0000-4000-8000-000000000001') then
    raise exception 'processable old event was not cancelled';
  end if;
  if (select status <> 'sent' from public.payment_notification_events
      where id='50000000-0000-4000-8000-000000000002') then
    raise exception 'sent event was modified';
  end if;
end $$;

select jsonb_build_object(
  'status', 'all_rpc_and_rls_assertions_passed',
  'followups_tested', (select count(*) from public.payment_followups),
  'old_pending_cancelled', (select status='cancelled' from public.payment_notification_events where id='50000000-0000-4000-8000-000000000001'),
  'sent_preserved', (select status='sent' from public.payment_notification_events where id='50000000-0000-4000-8000-000000000002')
) result;

rollback;
