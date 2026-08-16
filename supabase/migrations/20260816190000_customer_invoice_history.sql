begin;

create function public.list_customer_invoice_history(
  p_customer_id uuid,
  p_offset integer default 0,
  p_limit integer default 25,
  p_status text default 'all',
  p_search text default '',
  p_sort text default 'recent'
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  customer public.billing_customers%rowtype;
  result jsonb;
begin
  if p_offset < 0 or p_limit < 1 or p_limit > 50 then
    raise exception 'invalid pagination';
  end if;
  if p_status not in ('all','pending','paid','overdue','cancelled') then
    raise exception 'invalid status';
  end if;
  if p_sort not in ('recent','oldest','sale','balance') then
    raise exception 'invalid sort';
  end if;

  select * into customer from public.billing_customers c
  where c.id = p_customer_id and c.organization_id = org
    and c.configuration_active;
  if not found then raise exception 'enterprise customer not found'; end if;

  with invoice_data as (
    select f.ref_fact as reference, coalesce(f.nro_fact, f.ref_fact) as invoice_number,
      f.fecha as invoice_date, f.venta as sale,
      coalesce(rows.seller, '') as seller,
      coalesce(rows.report_month, '') as report_month,
      coalesce(rows.paid, 0) as paid,
      coalesce(rows.cancelled, false) as cancelled,
      case when coalesce(rows.cancelled, false) then 0
           else greatest(f.venta - coalesce(rows.paid, 0), 0) end as balance,
      r.payment_date as reminder_date, coalesce(r.calendar_comment, '') as calendar_comment,
      (not coalesce(rows.cancelled, false)
       and f.venta - coalesce(rows.paid, 0) > .005
       and r.payment_date < timezone('America/Guayaquil', now())::date) as overdue,
      coalesce(rows.payments, '[]'::jsonb) as payments
    from public.facturas_maestras f
    left join lateral (
      select max(rv.vendedor) filter(where upper(trim(coalesce(rv.vendedor,''))) <> 'ANULADA') as seller,
        max(rv.mes_reporte) as report_month,
        bool_or(upper(trim(coalesce(rv.vendedor,''))) = 'ANULADA') as cancelled,
        coalesce(sum((select coalesce(sum(value::numeric),0)
          from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0) as paid,
        coalesce(jsonb_agg(payment.item order by rv.mes_reporte, rv.nro_fila, payment.ordinal)
          filter(where payment.item is not null), '[]'::jsonb) as payments
      from public.reportes_ventas rv
      left join lateral (
        select ordinal, jsonb_build_object(
          'amount', (value #>> '{}')::numeric,
          'receipt', rv.numeros_recibo[ordinal],
          'comment', rv.comentarios_abonos->>(ordinal - 1)
        ) as item
        from jsonb_array_elements(coalesce(rv.abonos,'[]'::jsonb))
          with ordinality p(value, ordinal)
      ) payment on true
      where rv.organization_id = org and rv.ref_fact = f.ref_fact
    ) rows on true
    left join public.payment_reminders r
      on r.organization_id = org and r.factura_id = f.ref_fact and r.active
    where f.organization_id = org
      and public.normalize_customer_identity(f.cliente) = customer.normalized_name
      and public.normalize_customer_identity(coalesce(f.nombre_comercial,'')) = customer.normalized_commercial_name
  ), filtered as (
    select * from invoice_data i
    where (trim(coalesce(p_search,'')) = '' or
      i.reference ilike '%' || trim(p_search) || '%' or
      i.invoice_number ilike '%' || trim(p_search) || '%' or
      i.seller ilike '%' || trim(p_search) || '%' or
      i.report_month ilike '%' || trim(p_search) || '%' or
      i.invoice_date::text ilike '%' || trim(p_search) || '%')
      and case p_status
        when 'pending' then not i.cancelled and i.balance > .005
        when 'paid' then not i.cancelled and i.balance <= .005
        when 'overdue' then i.overdue
        when 'cancelled' then i.cancelled
        else true end
  ), page as (
    select * from filtered
    order by
      case when p_sort='oldest' then invoice_date end asc,
      case when p_sort='sale' then sale end desc,
      case when p_sort='balance' then balance end desc,
      case when p_sort='recent' then invoice_date end desc,
      reference desc
    offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'summary', (select jsonb_build_object(
      'total_sales', coalesce(sum(sale) filter(where not cancelled),0),
      'total_paid', coalesce(sum(paid) filter(where not cancelled),0),
      'balance', coalesce(sum(balance) filter(where not cancelled),0),
      'total_invoices', count(*),
      'paid_invoices', count(*) filter(where not cancelled and balance <= .005),
      'pending_invoices', count(*) filter(where not cancelled and balance > .005),
      'overdue_invoices', count(*) filter(where overdue),
      'cancelled_invoices', count(*) filter(where cancelled),
      'last_purchase', max(invoice_date) filter(where not cancelled),
      'next_payment', min(reminder_date) filter(where not cancelled and balance > .005 and reminder_date >= timezone('America/Guayaquil', now())::date)
    ) from invoice_data),
    'filtered_count', (select count(*) from filtered),
    'invoices', coalesce((select jsonb_agg(jsonb_build_object(
      'reference', reference, 'invoice_number', invoice_number,
      'invoice_date', invoice_date, 'seller', seller, 'report_month', report_month,
      'sale', sale, 'paid', paid, 'balance', balance, 'cancelled', cancelled,
      'overdue', overdue, 'reminder_date', reminder_date,
      'calendar_comment', calendar_comment, 'payments', payments
    )) from page), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text)
  from public, anon;
grant execute on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text)
  to authenticated;

commit;
