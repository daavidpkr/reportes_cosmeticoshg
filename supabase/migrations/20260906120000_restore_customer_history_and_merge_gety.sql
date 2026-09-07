-- Restore flat payment history responses and consolidate only the verified GETY
-- duplicate into its FARMACITY profile.
begin;

create or replace function public.list_customer_invoice_history(
  p_customer_id uuid,
  p_offset integer default 0,
  p_limit integer default 25,
  p_status text default 'all',
  p_search text default '',
  p_sort text default 'recent'
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  org uuid := public.require_current_organization_id();
  customer public.billing_customers%rowtype;
  result jsonb;
begin
  if p_offset < 0 or p_limit < 1 or p_limit > 50 then
    raise exception 'invalid pagination';
  end if;
  if p_status not in ('all','pending','paid','overdue','cancelled')
     or p_sort not in ('recent','oldest','sale','balance') then
    raise exception 'invalid filter';
  end if;

  select * into customer
  from public.billing_customers c
  where c.id = p_customer_id and c.organization_id = org;
  if not found then
    raise exception 'enterprise customer not found';
  end if;

  with invoice_base as (
    select
      f.ref_fact as reference,
      coalesce(nullif(f.nro_fact, ''), f.ref_fact) as invoice_number,
      f.fecha as invoice_date,
      f.venta as sale,
      coalesce(report.seller, '') as seller,
      coalesce(report.report_month, '') as report_month,
      coalesce(report.paid, 0) as paid,
      coalesce(report.cancelled, false) as cancelled,
      case
        when coalesce(report.cancelled, false) then 0
        else greatest(f.venta - coalesce(report.paid, 0), 0)
      end as balance,
      reminder.payment_date as reminder_date,
      coalesce(reminder.calendar_comment, '') as calendar_comment,
      reminder.date_source as schedule_source,
      coalesce(payment.payments, '[]'::jsonb) as payments
    from public.invoice_payment_terms terms
    join public.facturas_maestras f
      on f.organization_id = terms.organization_id
     and f.ref_fact = terms.factura_id
    left join lateral (
      select
        max(rv.vendedor) filter (
          where upper(trim(coalesce(rv.vendedor, ''))) <> 'ANULADA'
        ) as seller,
        max(rv.mes_reporte) as report_month,
        bool_or(upper(trim(coalesce(rv.vendedor, ''))) = 'ANULADA') as cancelled,
        coalesce(sum((
          select coalesce(sum(value::numeric), 0)
          from jsonb_array_elements_text(
            case when jsonb_typeof(rv.abonos) = 'array'
              then rv.abonos else '[]'::jsonb end
          ) value
        )), 0) as paid
      from public.reportes_ventas rv
      where rv.organization_id = org and rv.ref_fact = f.ref_fact
    ) report on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'amount', payment_item.value::numeric,
          'receipt', rv.numeros_recibo[payment_item.ordinality::integer],
          'comment', case
            when jsonb_typeof(rv.comentarios_abonos) = 'array'
              then rv.comentarios_abonos ->> (payment_item.ordinality - 1)::integer
            else null
          end
        ) order by rv.id, payment_item.ordinality
      ) as payments
      from public.reportes_ventas rv
      cross join lateral jsonb_array_elements_text(
        case when jsonb_typeof(rv.abonos) = 'array'
          then rv.abonos else '[]'::jsonb end
      ) with ordinality payment_item(value, ordinality)
      where rv.organization_id = org and rv.ref_fact = f.ref_fact
    ) payment on true
    left join lateral (
      select pr.payment_date, pr.calendar_comment, pr.date_source
      from public.payment_reminders pr
      where pr.organization_id = org
        and pr.factura_id = f.ref_fact
        and pr.active
      order by pr.updated_at desc, pr.id desc
      limit 1
    ) reminder on true
    where terms.organization_id = org
      and terms.customer_id = customer.id
      and terms.active
  ), invoice_data as (
    select invoice_base.*,
      coalesce(
        not cancelled and balance > .005
          and reminder_date < timezone('America/Guayaquil', now())::date,
        false
      ) as overdue
    from invoice_base
  ), filtered as (
    select *
    from invoice_data
    where (
      trim(coalesce(p_search, '')) = ''
      or reference ilike '%' || trim(p_search) || '%'
      or invoice_number ilike '%' || trim(p_search) || '%'
      or seller ilike '%' || trim(p_search) || '%'
    ) and case p_status
      when 'pending' then not cancelled and balance > .005
      when 'paid' then not cancelled and balance <= .005
      when 'overdue' then overdue
      when 'cancelled' then cancelled
      else true
    end
  ), page as (
    select ordered.*, row_number() over () as page_order
    from (
      select * from filtered
      order by
        case when p_sort = 'oldest' then invoice_date end asc,
        case when p_sort = 'sale' then sale end desc,
        case when p_sort = 'balance' then balance end desc,
        case when p_sort = 'recent' then invoice_date end desc,
        reference desc
      offset p_offset limit p_limit
    ) ordered
  )
  select jsonb_build_object(
    'summary', (
      select jsonb_build_object(
        'total_sales', coalesce(sum(sale) filter (where not cancelled), 0),
        'total_paid', coalesce(sum(paid) filter (where not cancelled), 0),
        'balance', coalesce(sum(balance) filter (where not cancelled), 0),
        'total_invoices', count(*),
        'paid_invoices', count(*) filter (where not cancelled and balance <= .005),
        'pending_invoices', count(*) filter (where not cancelled and balance > .005),
        'overdue_invoices', count(*) filter (where overdue),
        'cancelled_invoices', count(*) filter (where cancelled),
        'last_purchase', max(invoice_date) filter (where not cancelled),
        'next_payment', min(reminder_date) filter (
          where not cancelled and balance > .005
        )
      ) from invoice_data
    ),
    'filtered_count', (select count(*) from filtered),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reference', reference,
        'invoice_number', invoice_number,
        'invoice_date', invoice_date,
        'seller', seller,
        'report_month', report_month,
        'sale', sale,
        'paid', paid,
        'balance', balance,
        'cancelled', cancelled,
        'overdue', overdue,
        'reminder_date', reminder_date,
        'calendar_comment', calendar_comment,
        'schedule_source', schedule_source,
        'payments', payments
      ) order by page_order) from page
    ), '[]'::jsonb)
  ) into result;

  return result;
end $$;

revoke all on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text)
  from public, anon;
grant execute on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text)
  to authenticated;

do $$
declare
  expected_name constant text := 'GETY SALUD Y DIAGNÓSTICO S.A.S.';
  candidate_count integer;
  farmacity_count integer;
  source_count integer;
  canonical public.billing_customers%rowtype;
  duplicate public.billing_customers%rowtype;
  linked_refs text[];
  total_sales numeric;
  total_paid numeric;
begin
  select count(*),
    count(*) filter (where upper(trim(commercial_name)) = 'FARMACITY'),
    count(*) filter (where trim(coalesce(commercial_name, '')) = '')
  into candidate_count, farmacity_count, source_count
  from public.billing_customers
  where regexp_replace(trim(name), '^N24\s+', '', 'i') = expected_name;

  if candidate_count = 1 and farmacity_count = 1 then
    select * into canonical
    from public.billing_customers
    where regexp_replace(trim(name), '^N24\s+', '', 'i') = expected_name
      and upper(trim(commercial_name)) = 'FARMACITY';

    if not exists (
      select 1 from public.invoice_payment_terms
      where organization_id = canonical.organization_id
        and customer_id = canonical.id and factura_id = '000000598' and active
    ) or not exists (
      select 1 from public.invoice_payment_terms
      where organization_id = canonical.organization_id
        and customer_id = canonical.id and factura_id = '000000707' and active
    ) then
      raise exception 'GETY consolidation postcondition failed';
    end if;

    update public.billing_customers
    set name = expected_name,
        commercial_name = 'FARMACITY',
        payment_term_days = 60,
        configuration_active = true,
        updated_at = clock_timestamp()
    where id = canonical.id;
    return;
  end if;

  if candidate_count <> 2 or farmacity_count <> 1 or source_count <> 1 then
    raise exception 'GETY consolidation aborted: expected exactly FARMACITY and blank profiles';
  end if;

  select * into canonical
  from public.billing_customers
  where regexp_replace(trim(name), '^N24\s+', '', 'i') = expected_name
    and upper(trim(commercial_name)) = 'FARMACITY'
  for update;
  select * into duplicate
  from public.billing_customers
  where regexp_replace(trim(name), '^N24\s+', '', 'i') = expected_name
    and trim(coalesce(commercial_name, '')) = ''
  for update;

  if canonical.organization_id <> duplicate.organization_id then
    raise exception 'GETY consolidation aborted: organizations differ';
  end if;
  if canonical.buyer_identification_normalized is not null
     and duplicate.buyer_identification_normalized is not null
     and canonical.buyer_identification_normalized <> duplicate.buyer_identification_normalized then
    raise exception 'GETY consolidation aborted: buyer identities differ';
  end if;

  select array_agg(terms.factura_id order by terms.factura_id)
  into linked_refs
  from public.invoice_payment_terms terms
  where terms.organization_id = canonical.organization_id
    and terms.customer_id in (canonical.id, duplicate.id)
    and terms.active;
  if linked_refs is distinct from array['000000598','000000707']::text[] then
    raise exception 'GETY consolidation aborted: unexpected invoice relationships';
  end if;
  if exists (
    select 1
    from public.invoice_payment_terms terms
    left join public.facturas_maestras invoice
      on invoice.organization_id = terms.organization_id
     and invoice.ref_fact = terms.factura_id
    where terms.organization_id = canonical.organization_id
      and terms.customer_id in (canonical.id, duplicate.id)
      and (invoice.ref_fact is null or invoice.organization_id <> canonical.organization_id)
  ) then
    raise exception 'GETY consolidation aborted: invoice ownership is invalid';
  end if;

  select sum(invoice.venta), coalesce(sum(payment.paid), 0)
  into total_sales, total_paid
  from public.invoice_payment_terms terms
  join public.facturas_maestras invoice
    on invoice.organization_id = terms.organization_id
   and invoice.ref_fact = terms.factura_id
  left join lateral (
    select coalesce(sum(payment_value.amount::numeric), 0) as paid
    from public.reportes_ventas row
    cross join lateral jsonb_array_elements_text(
      case when jsonb_typeof(row.abonos) = 'array'
        then row.abonos else '[]'::jsonb end
    ) payment_value(amount)
    where row.organization_id = terms.organization_id
      and row.ref_fact = terms.factura_id
  ) payment on true
  where terms.organization_id = canonical.organization_id
    and terms.customer_id in (canonical.id, duplicate.id)
    and terms.active;
  if total_sales <> 113.17 or total_paid <> 50.67 then
    raise exception 'GETY consolidation aborted: verified KPI changed (sales %, paid %)',
      total_sales, total_paid;
  end if;

  update public.billing_customers
  set name = expected_name,
      commercial_name = 'FARMACITY',
      payment_term_days = 60,
      horario_atencion = coalesce(
        nullif(trim(canonical.horario_atencion), ''),
        nullif(trim(duplicate.horario_atencion), '')
      ),
      configuration_active = canonical.configuration_active or duplicate.configuration_active,
      buyer_identification = coalesce(
        canonical.buyer_identification, duplicate.buyer_identification
      ),
      buyer_identification_normalized = coalesce(
        canonical.buyer_identification_normalized,
        duplicate.buyer_identification_normalized
      ),
      buyer_identification_type = coalesce(
        canonical.buyer_identification_type, duplicate.buyer_identification_type
      ),
      profile_invoice_date = greatest(
        canonical.profile_invoice_date, duplicate.profile_invoice_date
      ),
      profile_invoice_ref = case
        when duplicate.profile_invoice_date > canonical.profile_invoice_date
          then duplicate.profile_invoice_ref
        else coalesce(canonical.profile_invoice_ref, duplicate.profile_invoice_ref)
      end,
      updated_at = clock_timestamp()
  where id = canonical.id;

  update public.invoice_payment_terms
  set customer_id = canonical.id, updated_at = clock_timestamp()
  where organization_id = canonical.organization_id
    and customer_id = duplicate.id;

  if exists (
    select 1 from public.invoice_payment_terms
    where organization_id = canonical.organization_id and customer_id = duplicate.id
  ) then
    raise exception 'GETY consolidation aborted: source relationships remain';
  end if;

  delete from public.billing_customers
  where id = duplicate.id and organization_id = canonical.organization_id;
  if not found then
    raise exception 'GETY consolidation aborted: duplicate profile was not deleted';
  end if;

  if (select count(*) from public.billing_customers
      where regexp_replace(trim(name), '^N24\s+', '', 'i') = expected_name) <> 1
     or (select count(*) from public.invoice_payment_terms
         where organization_id = canonical.organization_id
           and customer_id = canonical.id and active) <> 2 then
    raise exception 'GETY consolidation postcondition failed';
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
