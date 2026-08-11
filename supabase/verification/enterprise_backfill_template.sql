-- TEMPLATE ONLY. Do not run without a backup and explicit authorization.
-- Replace :organization_id only in the controlled administrative procedure.
begin;

-- update public.facturas_maestras set organization_id=:organization_id where organization_id is null;
-- update public.reportes_mensuales set organization_id=:organization_id where organization_id is null;
-- update public.reportes_ventas r set organization_id=:organization_id
--   where r.organization_id is null and exists (
--     select 1 from public.facturas_maestras f
--     where f.ref_fact=r.ref_fact and f.organization_id=:organization_id);
-- update public.vendedores set organization_id=:organization_id where organization_id is null;
-- update public.payment_reminders r set organization_id=:organization_id
--   where r.organization_id is null and exists (
--     select 1 from public.facturas_maestras f
--     where f.ref_fact=r.factura_id and f.organization_id=:organization_id);
-- update public.payment_followups f set organization_id=r.organization_id
--   from public.payment_reminders r
--   where f.reminder_id=r.id and f.organization_id is null;
-- update public.payment_notification_events e set organization_id=r.organization_id
--   from public.payment_reminders r
--   where e.reminder_id=r.id and e.organization_id is null;

-- Deliberately rollback until the reviewed placeholders are replaced and
-- the independent backup/count/fingerprint verification has passed.
rollback;
