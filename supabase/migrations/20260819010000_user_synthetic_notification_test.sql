begin;

-- La prueba pertenece exclusivamente al usuario autenticado. La organización
-- no participa en la autorización ni en la selección de destinatarios.
alter table public.notification_test_executions
  alter column organization_id drop not null,
  add column inactive_count integer not null default 0
    check (inactive_count >= 0);

alter table public.notification_test_executions
  drop constraint notification_test_executions_operation_check;
alter table public.notification_test_executions
  add constraint notification_test_executions_operation_check
  check (operation in ('organization_android_test', 'user_android_test'));

comment on table public.notification_test_executions is
  'Idempotency and aggregate results for synthetic notification tests; service_role only.';

-- Reafirma que el cliente nunca puede leer tokens ni alterar ejecuciones.
revoke all on public.notification_test_executions,
  public.notification_test_recipients from public, anon, authenticated;
grant select, insert, update on public.notification_test_executions,
  public.notification_test_recipients to service_role;

commit;
