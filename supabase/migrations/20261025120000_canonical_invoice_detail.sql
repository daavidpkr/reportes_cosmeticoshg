-- Canonical, organization-scoped invoice detail. Payment dates are recorded
-- prospectively; historical payments remain explicitly unknown (no backfill).
begin;

alter table public.reportes_ventas
  add column fechas_abonos jsonb not null default '[]'::jsonb;

create function public.sync_report_payment_dates()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_count integer := case when tg_op = 'INSERT' then 0
    else jsonb_array_length(coalesce(old.abonos, '[]'::jsonb)) end;
  new_count integer := jsonb_array_length(coalesce(new.abonos, '[]'::jsonb));
  result jsonb := '[]'::jsonb;
  used_old integer[] := '{}'::integer[];
  i integer;
  j integer;
  matched integer;
  old_dates jsonb := case when tg_op = 'INSERT' then '[]'::jsonb
    else coalesce(old.fechas_abonos, '[]'::jsonb) end;
begin
  if new_count = 0 then
    new.fechas_abonos := '[]'::jsonb;
    return new;
  end if;

  for i in 0..new_count - 1 loop
    matched := null;
    if old_count > 0 then
      for j in 0..old_count - 1 loop
        if not (j = any(used_old))
           and old.abonos->j is not distinct from new.abonos->i
           and old.numeros_recibo[j + 1] is not distinct from new.numeros_recibo[i + 1]
           and coalesce(old.comentarios_abonos->>j, '')
             is not distinct from coalesce(new.comentarios_abonos->>i, '') then
          matched := j;
          exit;
        end if;
      end loop;
    end if;

    -- An in-place edit is still the same payment and keeps its original date.
    if matched is null and i < old_count and new_count = old_count then
      matched := i;
    end if;
    if matched is null then
      result := result || jsonb_build_array(to_char(
        timezone('America/Guayaquil', statement_timestamp())::date,
        'YYYY-MM-DD'
      ));
    else
      used_old := array_append(used_old, matched);
      result := result || jsonb_build_array(old_dates->matched);
    end if;
  end loop;
  new.fechas_abonos := result;
  return new;
end;
$$;

create trigger report_payment_dates_before_write
before insert or update of abonos, numeros_recibo, comentarios_abonos
on public.reportes_ventas
for each row execute function public.sync_report_payment_dates();

create function public.get_invoice_detail(p_ref_fact text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  org uuid := public.require_current_organization_id();
  result jsonb;
begin
  if nullif(trim(p_ref_fact), '') is null then
    raise exception 'invalid invoice reference';
  end if;

  select jsonb_build_object(
    'reference', invoice.ref_fact,
    'invoice_number', coalesce(nullif(invoice.nro_fact, ''), invoice.ref_fact),
    'invoice_date', invoice.fecha,
    'cliente', coalesce(invoice.cliente, ''),
    'commercial_name', coalesce(invoice.nombre_comercial, ''),
    'sale', invoice.venta,
    'report_month', coalesce(report.mes_reporte, ''),
    'row_number', coalesce(report.nro_fila, 0),
    'seller', coalesce(report.vendedor, ''),
    'nail_polish', coalesce(report.esmaltes, 0),
    'abonos', coalesce(report.abonos, '[]'::jsonb),
    'payment_receipts', coalesce(to_jsonb(report.numeros_recibo), '[]'::jsonb),
    'payment_comments', coalesce(report.comentarios_abonos, '[]'::jsonb),
    'payment_dates', coalesce(report.fechas_abonos, '[]'::jsonb),
    'payment_term_days', customer.payment_term_days,
    'scheduled_date', reminder.payment_date,
    'next_collection_date', case
      when upper(trim(coalesce(report.vendedor, ''))) in ('ANUL', 'ANULADA')
        or invoice.venta - payment.total <= .005 then null
      else reminder.payment_date
    end,
    'schedule_source', reminder.date_source,
    'overdue', coalesce(
      upper(trim(coalesce(report.vendedor, ''))) not in ('ANUL', 'ANULADA')
      and invoice.venta - payment.total > .005
      and reminder.payment_date < timezone('America/Guayaquil', now())::date,
      false
    )
  ) into result
  from public.facturas_maestras invoice
  left join lateral (
    select rv.*
    from public.reportes_ventas rv
    where rv.organization_id = org and rv.ref_fact = invoice.ref_fact
    order by rv.mes_reporte desc, rv.nro_fila desc, rv.id desc
    limit 1
  ) report on true
  left join lateral (
    select bc.payment_term_days
    from public.invoice_payment_terms term
    join public.billing_customers bc
      on bc.organization_id = term.organization_id and bc.id = term.customer_id
    where term.organization_id = org
      and term.factura_id = invoice.ref_fact and term.active
    order by term.updated_at desc
    limit 1
  ) customer on true
  left join lateral (
    select pr.payment_date, pr.date_source
    from public.payment_reminders pr
    where pr.organization_id = org
      and pr.factura_id = invoice.ref_fact and pr.active
    order by pr.updated_at desc, pr.id desc
    limit 1
  ) reminder on true
  cross join lateral (
    select coalesce(sum(value::numeric), 0) total
    from jsonb_array_elements_text(coalesce(report.abonos, '[]'::jsonb)) value
  ) payment
  where invoice.organization_id = org
    and invoice.ref_fact = trim(p_ref_fact);

  return result;
end;
$$;

revoke all on function public.get_invoice_detail(text) from public, anon;
grant execute on function public.get_invoice_detail(text) to authenticated;
revoke all on function public.sync_report_payment_dates() from public, anon, authenticated;

comment on function public.get_invoice_detail(text) is
  'Canonical organization-scoped invoice detail without internal buyer identity.';

commit;
