-- Sanitized counts only. Run before and after deployment; no business values are exposed.
with invoice_state as (
  select f.organization_id,f.ref_fact,f.venta,
    count(rv.*) as monthly_rows,
    coalesce(bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA'),false) as cancelled,
    coalesce(sum((select coalesce(sum(value::numeric),0)
      from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0) as paid
  from public.facturas_maestras f
  left join public.reportes_ventas rv
    on rv.organization_id=f.organization_id and rv.ref_fact=f.ref_fact
  group by f.organization_id,f.ref_fact,f.venta
), eligible as (
  select * from invoice_state where monthly_rows>0 and not cancelled and venta-paid>0.005
)
select
  (select count(*) from public.billing_customers where payment_term_days is not null) configured_customers,
  (select count(*) from public.billing_customers where payment_term_days is null) pending_customers,
  (select count(*) from eligible e join public.payment_reminders r
    on r.organization_id=e.organization_id and r.factura_id=e.ref_fact) pending_invoices_with_reminder,
  (select count(*) from eligible e where not exists(select 1 from public.payment_reminders r
    where r.organization_id=e.organization_id and r.factura_id=e.ref_fact)) pending_invoices_without_reminder,
  (select count(*) from public.payment_reminders where date_source<>'manual') automatic_reminders,
  (select count(*) from public.payment_reminders where date_source='manual') manual_reminders,
  (select coalesce(sum(c-1),0) from (select count(*) c from public.payment_reminders
    group by organization_id,factura_id having count(*)>1) d) duplicates,
  (select count(*) from public.payment_reminders r where not exists(
    select 1 from public.facturas_maestras f
    where f.organization_id=r.organization_id and f.ref_fact=r.factura_id)) orphan_reminders;

