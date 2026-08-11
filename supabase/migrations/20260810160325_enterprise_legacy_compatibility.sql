-- Apply only after the initial organization, membership and backfill exist.
-- Keeps authenticated 1.0.0+3 writes tagged during the transition.
begin;

create function public.assign_current_organization()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.organization_id is null then new.organization_id:=public.require_current_organization_id(); end if;
  if new.organization_id<>public.require_current_organization_id() then raise exception 'organization mismatch'; end if;
  return new;
end; $$;

create trigger facturas_assign_enterprise before insert or update on public.facturas_maestras
for each row execute function public.assign_current_organization();
create trigger monthly_reports_assign_enterprise before insert or update on public.reportes_mensuales
for each row execute function public.assign_current_organization();
create trigger sellers_assign_enterprise before insert or update on public.vendedores
for each row execute function public.assign_current_organization();

create function public.assign_report_row_organization()
returns trigger language plpgsql security definer set search_path='' as $$
declare org uuid;
begin
  select organization_id into org from public.facturas_maestras where ref_fact=new.ref_fact;
  org:=coalesce(org,public.require_current_organization_id());
  if org<>public.require_current_organization_id() then raise exception 'invoice organization mismatch'; end if;
  new.organization_id:=org; return new;
end; $$;
create trigger report_rows_assign_enterprise before insert or update on public.reportes_ventas
for each row execute function public.assign_report_row_organization();

create function public.assign_reminder_organization()
returns trigger language plpgsql security definer set search_path='' as $$
declare org uuid;
begin
  select organization_id into org from public.facturas_maestras where ref_fact=new.factura_id;
  if org is null or org<>public.require_current_organization_id() then raise exception 'invoice organization mismatch'; end if;
  new.organization_id:=org; return new;
end; $$;
create trigger reminders_assign_enterprise before insert or update on public.payment_reminders
for each row execute function public.assign_reminder_organization();

create function public.assign_followup_organization()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  select organization_id into new.organization_id from public.payment_reminders where id=new.reminder_id;
  if new.organization_id is null or new.organization_id<>public.require_current_organization_id() then
    raise exception 'reminder organization mismatch';
  end if;
  return new;
end; $$;
create trigger followups_assign_enterprise before insert or update on public.payment_followups
for each row execute function public.assign_followup_organization();

create function public.assign_event_organization()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  select organization_id into new.organization_id from public.payment_reminders where id=new.reminder_id;
  if new.organization_id is null then raise exception 'reminder organization missing'; end if;
  return new;
end; $$;
create trigger events_assign_enterprise before insert or update on public.payment_notification_events
for each row execute function public.assign_event_organization();

revoke all on function public.assign_current_organization() from public,anon,authenticated;
revoke all on function public.assign_report_row_organization() from public,anon,authenticated;
revoke all on function public.assign_reminder_organization() from public,anon,authenticated;
revoke all on function public.assign_followup_organization() from public,anon,authenticated;
revoke all on function public.assign_event_organization() from public,anon,authenticated;

commit;
