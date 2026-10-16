with row_state as (
  select organization_id, ref_fact,
    bool_or(upper(trim(coalesce(vendedor, ''))) = 'ANULADA') as cancelled,
    coalesce(sum((select coalesce(sum(value::numeric), 0)
      from jsonb_array_elements_text(coalesce(abonos, '[]'::jsonb)))), 0) as paid
  from public.reportes_ventas
  where nullif(trim(ref_fact), '') is not null
  group by organization_id, ref_fact
), pending as (
  select f.organization_id, f.ref_fact,
    t.factura_id as term_invoice, t.active as term_active,
    t.exceptional_term_days, c.id as customer_id, c.payment_term_days,
    r.id as reminder_id, f.fecha, f.venta - rs.paid as balance
  from public.facturas_maestras f
  join row_state rs using (organization_id, ref_fact)
  left join public.invoice_payment_terms t
    on t.organization_id = f.organization_id and t.factura_id = f.ref_fact
  left join public.billing_customers c
    on c.organization_id = t.organization_id and c.id = t.customer_id
  left join public.payment_reminders r
    on r.organization_id = f.organization_id and r.factura_id = f.ref_fact
  where not rs.cancelled and f.venta - rs.paid > 0.005
), classified as (
  select *, case
    when reminder_id is not null then 'scheduled'
    when term_invoice is null or not coalesce(term_active, false)
      then 'customer_unresolved'
    when customer_id is null then 'customer_unresolved'
    when coalesce(exceptional_term_days, payment_term_days) is null
      then 'term_missing'
    when fecha is null then 'invoice_date_missing'
    else 'repairable'
  end as cause
  from pending
)
select
  coalesce((select jsonb_object_agg(cause, count) from (
    select cause, count(*)::integer as count
    from classified
    group by cause
  ) causes), '{}'::jsonb) as pending_by_cause,
  (select count(*) from (
    select organization_id, factura_id
    from public.payment_reminders
    group by organization_id, factura_id
    having count(*) > 1
  ) duplicates) as duplicate_invoice_schedules,
  (select count(*) from public.payment_reminders
    where extract(isodow from payment_date) in (6, 7)) as weekend_schedules,
  (select count(*) from public.payment_reminders where active) as active_schedules;
