-- APPLY ONLY after: organization/memberships authorized, historical backfill
-- completed, all organization_id values verified, and the RPC-enabled app released.
begin;

do $$
begin
  if exists(select 1 from public.facturas_maestras where organization_id is null)
     or exists(select 1 from public.reportes_mensuales where organization_id is null)
     or exists(select 1 from public.reportes_ventas where organization_id is null)
     or exists(select 1 from public.vendedores where organization_id is null)
     or exists(select 1 from public.payment_reminders where organization_id is null)
     or exists(select 1 from public.payment_followups where organization_id is null)
     or exists(select 1 from public.payment_notification_events where organization_id is null)
     or exists(select 1 from public.fcm_devices where organization_id is null) then
    raise exception 'enterprise backfill is incomplete';
  end if;
end;
$$;

alter table public.facturas_maestras alter column organization_id set not null;
alter table public.reportes_mensuales alter column organization_id set not null;
alter table public.reportes_ventas alter column organization_id set not null;
alter table public.vendedores alter column organization_id set not null;
alter table public.payment_reminders alter column organization_id set not null;
alter table public.payment_followups alter column organization_id set not null;
alter table public.payment_notification_events alter column organization_id set not null;
alter table public.fcm_devices alter column organization_id set not null;

drop policy if exists "Permitir todo a todos en facturas" on public.facturas_maestras;
drop policy if exists "Permitir todo a todos en reportes" on public.reportes_ventas;
drop policy if exists "Usuarios autenticados pueden leer reportes" on public.reportes_mensuales;
drop policy if exists "Usuarios autenticados pueden crear reportes" on public.reportes_mensuales;
drop policy if exists "Usuarios autenticados pueden actualizar reportes" on public.reportes_mensuales;
drop policy if exists "Usuarios autenticados pueden eliminar reportes" on public.reportes_mensuales;
drop policy if exists "Usuarios autenticados pueden leer vendedores" on public.vendedores;
drop policy if exists "Usuarios autenticados pueden crear vendedores" on public.vendedores;
drop policy if exists "Usuarios autenticados pueden actualizar vendedores" on public.vendedores;
drop policy if exists "Usuarios autenticados pueden eliminar vendedores" on public.vendedores;
drop policy if exists "users read own reminders" on public.payment_reminders;
drop policy if exists "users insert own valid reminders" on public.payment_reminders;
drop policy if exists "users update own valid reminders" on public.payment_reminders;
drop policy if exists "users delete own reminders" on public.payment_reminders;
drop policy if exists "users read own payment followups" on public.payment_followups;

create policy "members read enterprise invoices" on public.facturas_maestras
for select to authenticated using (organization_id=public.current_organization_id());
create policy "members read enterprise monthly reports" on public.reportes_mensuales
for select to authenticated using (organization_id=public.current_organization_id());
create policy "members read enterprise report rows" on public.reportes_ventas
for select to authenticated using (organization_id=public.current_organization_id());
create policy "members read enterprise sellers" on public.vendedores
for select to authenticated using (organization_id=public.current_organization_id());
create policy "members read enterprise reminders" on public.payment_reminders
for select to authenticated using (organization_id=public.current_organization_id());
create policy "members read enterprise followups" on public.payment_followups
for select to authenticated using (organization_id=public.current_organization_id());

revoke all on public.facturas_maestras,public.reportes_ventas from anon;
revoke all on public.reportes_mensuales,public.vendedores from anon;
revoke all on public.facturas_maestras,public.reportes_mensuales,
  public.reportes_ventas,public.vendedores from authenticated;
grant select on public.facturas_maestras,public.reportes_mensuales,
  public.reportes_ventas,public.vendedores to authenticated;
revoke all on public.payment_reminders from authenticated;
grant select on public.payment_reminders to authenticated;
revoke all on public.payment_notification_events from anon,authenticated;

drop policy if exists "users read own devices" on public.fcm_devices;
create policy "users read own enterprise devices" on public.fcm_devices
for select to authenticated using (
  user_id=auth.uid() and organization_id=public.current_organization_id()
);

drop trigger if exists facturas_assign_enterprise on public.facturas_maestras;
drop trigger if exists monthly_reports_assign_enterprise on public.reportes_mensuales;
drop trigger if exists sellers_assign_enterprise on public.vendedores;
drop trigger if exists report_rows_assign_enterprise on public.reportes_ventas;
drop trigger if exists reminders_assign_enterprise on public.payment_reminders;
drop trigger if exists followups_assign_enterprise on public.payment_followups;
drop trigger if exists events_assign_enterprise on public.payment_notification_events;

drop function if exists public.assign_current_organization();
drop function if exists public.assign_report_row_organization();
drop function if exists public.assign_reminder_organization();
drop function if exists public.assign_followup_organization();
drop function if exists public.assign_event_organization();

commit;
