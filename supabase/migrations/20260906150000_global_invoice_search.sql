create or replace function public.enterprise_search_invoice_rows(
  p_search text default '',
  p_offset integer default 0,
  p_limit integer default 50
)
returns table (
  mes_reporte text,
  nro_fila integer,
  ref_fact text,
  cliente text,
  nombre_comercial text,
  fecha date,
  nro_fact text,
  vendedor text,
  esmaltes integer,
  venta numeric,
  abonos jsonb,
  numeros_recibo bigint[],
  comentarios_abonos jsonb,
  plazo_pago_dias integer,
  fecha_programada date,
  estado text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    row.mes_reporte,
    row.nro_fila,
    invoice.ref_fact,
    invoice.cliente,
    invoice.nombre_comercial,
    invoice.fecha,
    invoice.nro_fact,
    row.vendedor,
    row.esmaltes,
    invoice.venta,
    coalesce(row.abonos, '[]'::jsonb),
    coalesce(row.numeros_recibo, '{}'::bigint[]),
    coalesce(row.comentarios_abonos, '[]'::jsonb),
    terms.payment_term_days,
    reminder.payment_date,
    case
      when upper(trim(coalesce(row.vendedor, ''))) = 'ANULADA' then 'anulada'
      when invoice.venta - payments.total <= .005 then 'pagada'
      else 'pendiente'
    end
  from public.reportes_ventas row
  join public.facturas_maestras invoice
    on invoice.organization_id = row.organization_id
   and invoice.ref_fact = row.ref_fact
  left join lateral (
    select customer.payment_term_days
    from public.invoice_payment_terms term
    join public.billing_customers customer
      on customer.id = term.customer_id
     and customer.organization_id = term.organization_id
    where term.organization_id = row.organization_id
      and term.factura_id = row.ref_fact
      and term.active
    order by term.updated_at desc
    limit 1
  ) terms on true
  left join lateral (
    select item.payment_date
    from public.payment_reminders item
    where item.organization_id = row.organization_id
      and item.factura_id = row.ref_fact
      and item.active
    order by item.updated_at desc, item.id desc
    limit 1
  ) reminder on true
  cross join lateral (
    select coalesce(sum(value::numeric), 0) as total
    from jsonb_array_elements_text(coalesce(row.abonos, '[]'::jsonb))
  ) payments
  where row.organization_id = public.require_current_organization_id()
    and (
      trim(coalesce(p_search, '')) = ''
      or invoice.ref_fact ilike '%' || trim(p_search) || '%'
      or invoice.nro_fact ilike '%' || trim(p_search) || '%'
      or invoice.cliente ilike '%' || trim(p_search) || '%'
      or invoice.nombre_comercial ilike '%' || trim(p_search) || '%'
    )
  order by
    case when invoice.ref_fact ~ '^[0-9]+$' then 0 else 1 end,
    case
      when invoice.ref_fact ~ '^[0-9]+$'
        then length(ltrim(invoice.ref_fact, '0'))
    end,
    case
      when invoice.ref_fact ~ '^[0-9]+$'
        then ltrim(invoice.ref_fact, '0')
    end,
    lower(invoice.ref_fact),
    row.mes_reporte,
    row.nro_fila
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 50), 1), 50);
$$;

revoke all on function public.enterprise_search_invoice_rows(text, integer, integer)
  from public, anon;
grant execute on function public.enterprise_search_invoice_rows(text, integer, integer)
  to authenticated;

comment on function public.enterprise_search_invoice_rows(text, integer, integer)
  is 'Organization-scoped, naturally ordered and paged invoice row search.';
