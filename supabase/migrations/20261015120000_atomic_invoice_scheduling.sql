begin;

-- The importer previously attempted reminder synchronization from
-- enterprise_upsert_invoice before the report row existed.  The scheduler
-- deliberately requires that row as proof of a completed import, so the
-- attempt was a no-op.  Schedule each invoice only after its report row is
-- present, while the batch transaction and advisory lock are still held.
create or replace function public.enterprise_import_monthly_invoices(
  p_request_id uuid, p_year integer, p_month integer, p_invoices jsonb
) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  item jsonb; invoice_ref text; invoice_date date; seller_label text;
  report_name text; next_row integer; inserted_rows integer := 0;
  customer_id uuid; proposed_days integer; canonical_days integer;
  upsert_result jsonb;
begin
  if p_year < 2000 or p_month not between 1 and 12 or p_invoices is null
     or jsonb_typeof(p_invoices) <> 'array' then
    raise exception 'invalid monthly invoice batch';
  end if;
  if exists(select 1 from public.enterprise_requests r
            where r.organization_id = org and r.request_id = p_request_id) then
    return coalesce((select (r.result->>'inserted_rows')::integer
      from public.enterprise_requests r where r.organization_id = org
        and r.request_id = p_request_id), 0);
  end if;
  for item in select value from jsonb_array_elements(p_invoices) loop
    if item ? 'payment_term_days' then
      begin proposed_days := (item->>'payment_term_days')::integer;
      exception when others then raise exception 'invalid payment term'; end;
      if proposed_days < 0 or proposed_days > 3650 then
        raise exception 'invalid payment term';
      end if;
    end if;
  end loop;
  report_name := (array['Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[p_month]
    || ' ' || p_year::text;
  perform 1 from public.reportes_mensuales
  where id = p_year::text || '-' || lpad(p_month::text, 2, '0')
    and organization_id = org for update;
  if not found then raise exception 'monthly report not found'; end if;
  perform pg_advisory_xact_lock(
    hashtextextended(org::text || ':' || report_name, 0));
  select coalesce(max(nro_fila), 0) into next_row
  from public.reportes_ventas
  where organization_id = org and mes_reporte = report_name;

  for item in select value from jsonb_array_elements(p_invoices)
    order by case when trim(value->>'ref_fact') ~ '^[0-9]+$' then 0 else 1 end,
      case when trim(value->>'ref_fact') ~ '^[0-9]+$'
           then trim(value->>'ref_fact')::numeric end,
      trim(value->>'ref_fact')
  loop
    invoice_ref := trim(coalesce(item->>'ref_fact', ''));
    seller_label := trim(coalesce(item->>'vendedor', ''));
    begin invoice_date := (item->>'fecha')::date;
    exception when others then
      raise exception 'invalid invoice date for %', invoice_ref;
    end;
    if invoice_ref = '' or invoice_ref <> trim(coalesce(item->>'nro_fact', ''))
       or invoice_date < make_date(p_year, p_month, 1)
       or invoice_date >=
          (make_date(p_year, p_month, 1) + interval '1 month')::date
       or seller_label = '' then
      raise exception 'invalid invoice % for selected report', invoice_ref;
    end if;
    if not exists(select 1 from public.vendedores v
      where v.organization_id = org and seller_label = case
        when trim(v.codigo) = '' then trim(v.nombre)
        else trim(v.codigo) || ' - ' || trim(v.nombre) end) then
      raise exception 'invalid seller for invoice %', invoice_ref;
    end if;

    upsert_result := public.enterprise_upsert_invoice(
      gen_random_uuid(), invoice_ref, trim(coalesce(item->>'cliente', '')),
      trim(coalesce(item->>'nombre_comercial', '')), invoice_date, invoice_ref,
      (item->>'venta')::numeric,
      coalesce(item->>'identificacion_comprador', ''),
      coalesce(item->>'tipo_identificacion_comprador', ''));
    customer_id := (upsert_result->>'customer_id')::uuid;
    select c.payment_term_days into canonical_days
    from public.billing_customers c
    where c.id = customer_id and c.organization_id = org for update;
    if canonical_days is null then
      if not (item ? 'payment_term_days') then
        raise exception 'customer payment term is pending for invoice %',
          invoice_ref;
      end if;
      proposed_days := (item->>'payment_term_days')::integer;
      update public.billing_customers c set
        payment_term_days = proposed_days, configuration_active = true,
        updated_at = clock_timestamp(), updated_by = auth.uid()
      where c.id = customer_id and c.organization_id = org
        and c.payment_term_days is null;
    end if;
    if not exists(select 1 from public.reportes_ventas r
      where r.organization_id = org and r.mes_reporte = report_name
        and r.ref_fact = invoice_ref) then
      next_row := next_row + 1;
      insert into public.reportes_ventas(
        organization_id, nro_fila, ref_fact, vendedor, esmaltes, abonos,
        numeros_recibo, comentarios_abonos, mes_reporte)
      values (org, next_row, invoice_ref, seller_label, 0, '[]'::jsonb,
        '{}'::bigint[], '[]'::jsonb, report_name);
      inserted_rows := inserted_rows + 1;
    end if;

    -- invoice exception > canonical customer term > no fabricated date.
    if public.sync_enterprise_reminder(
      org, invoice_ref, p_request_id, 'Atomic schedule after invoice import'
    ) is null then
      raise exception 'invoice % could not be scheduled: customer or payment term missing',
        invoice_ref;
    end if;
  end loop;
  insert into public.enterprise_requests(
    organization_id, request_id, action, result)
  values (org, p_request_id, 'import_monthly_invoices',
    jsonb_build_object('inserted_rows', inserted_rows));
  return inserted_rows;
end $$;

create function public.search_schedulable_invoices(
  p_search text default '', p_limit integer default 30
) returns table(
  factura_id text,
  invoice_number text,
  cliente text,
  nombre_comercial text,
  invoice_date date,
  reminder_date date,
  balance numeric
)
language sql stable security definer set search_path = '' as $$
  with invoice_rows as (
    select rv.organization_id, rv.ref_fact,
      bool_or(upper(trim(coalesce(rv.vendedor, ''))) = 'ANULADA') as cancelled,
      coalesce(sum((select coalesce(sum(value::numeric), 0)
        from jsonb_array_elements_text(coalesce(rv.abonos, '[]'::jsonb)))), 0) as paid
    from public.reportes_ventas rv
    where rv.organization_id = public.require_current_organization_id()
      and nullif(trim(rv.ref_fact), '') is not null
    group by rv.organization_id, rv.ref_fact
  )
  select f.ref_fact, coalesce(f.nro_fact, ''), f.cliente,
    coalesce(f.nombre_comercial, ''), f.fecha, r.payment_date,
    greatest(f.venta - ir.paid, 0)
  from public.facturas_maestras f
  join invoice_rows ir
    on ir.organization_id = f.organization_id and ir.ref_fact = f.ref_fact
  join public.invoice_payment_terms t
    on t.organization_id = f.organization_id and t.factura_id = f.ref_fact
      and t.active
  join public.billing_customers c
    on c.organization_id = t.organization_id and c.id = t.customer_id
  left join public.payment_reminders r
    on r.organization_id = f.organization_id and r.factura_id = f.ref_fact
  where f.organization_id = public.require_current_organization_id()
    and not ir.cancelled and f.venta - ir.paid > 0.005
    and f.fecha is not null
    and coalesce(t.exceptional_term_days, c.payment_term_days) is not null
    and (nullif(trim(p_search), '') is null
      or f.ref_fact ilike '%' || trim(p_search) || '%'
      or coalesce(f.nro_fact, '') ilike '%' || trim(p_search) || '%'
      or f.cliente ilike '%' || trim(p_search) || '%'
      or coalesce(f.nombre_comercial, '') ilike '%' || trim(p_search) || '%')
  order by f.fecha desc, f.ref_fact
  limit greatest(1, least(coalesce(p_limit, 30), 100));
$$;

create function public.schedule_invoice_on_calendar(
  p_request_id uuid,
  p_factura_id text,
  p_requested_payment_date date,
  p_comment text default ''
) returns table(
  reminder_id uuid,
  factura_id text,
  invoice_number text,
  cliente text,
  nombre_comercial text,
  invoice_date date,
  reminder_date date,
  balance numeric,
  comment text
)
language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  invoice public.facturas_maestras%rowtype;
  terms public.invoice_payment_terms%rowtype;
  customer public.billing_customers%rowtype;
  reminder public.payment_reminders%rowtype;
  monthly_rows integer;
  cancelled boolean;
  paid numeric;
begin
  if p_requested_payment_date is null or nullif(trim(p_factura_id), '') is null then
    raise exception 'invalid invoice schedule request';
  end if;
  select * into invoice from public.facturas_maestras f
  where f.organization_id = org and f.ref_fact = trim(p_factura_id) for update;
  if not found then raise exception 'enterprise invoice not found'; end if;
  select * into terms from public.invoice_payment_terms t
  where t.organization_id = org and t.factura_id = invoice.ref_fact
    and t.active for update;
  if not found then raise exception 'invoice customer could not be resolved'; end if;
  select * into customer from public.billing_customers c
  where c.organization_id = org and c.id = terms.customer_id for update;
  if not found then raise exception 'invoice customer could not be resolved'; end if;
  if coalesce(terms.exceptional_term_days, customer.payment_term_days) is null then
    raise exception 'invoice payment term is missing';
  end if;
  select count(*)::integer,
    coalesce(bool_or(upper(trim(coalesce(rv.vendedor, ''))) = 'ANULADA'), false),
    coalesce(sum((select coalesce(sum(value::numeric), 0)
      from jsonb_array_elements_text(coalesce(rv.abonos, '[]'::jsonb)))), 0)
  into monthly_rows, cancelled, paid
  from public.reportes_ventas rv
  where rv.organization_id = org and rv.ref_fact = invoice.ref_fact;
  if monthly_rows = 0 then raise exception 'invoice report row is missing'; end if;
  if cancelled then raise exception 'cancelled invoice cannot be scheduled'; end if;
  if invoice.venta - paid <= 0.005 then
    raise exception 'paid invoice cannot be scheduled';
  end if;

  perform public.sync_enterprise_reminder(
    org, invoice.ref_fact, p_request_id, 'Calendar day scheduling');
  select * into reminder from public.payment_reminders r
  where r.organization_id = org and r.factura_id = invoice.ref_fact for update;
  if not found then raise exception 'invoice could not be scheduled'; end if;
  perform public.update_payment_calendar_reminder(
    p_request_id, reminder.id, p_requested_payment_date, p_comment);
  update public.payment_reminders r set active = true
  where r.id = reminder.id and r.organization_id = org;

  return query
  select r.id, invoice.ref_fact, coalesce(invoice.nro_fact, ''), invoice.cliente,
    coalesce(invoice.nombre_comercial, ''), invoice.fecha, r.payment_date,
    greatest(invoice.venta - paid, 0), r.calendar_comment
  from public.payment_reminders r
  where r.id = reminder.id and r.organization_id = org;
end $$;

revoke all on function public.enterprise_import_monthly_invoices(
  uuid, integer, integer, jsonb) from public, anon;
revoke all on function public.search_schedulable_invoices(text, integer)
  from public, anon;
revoke all on function public.schedule_invoice_on_calendar(
  uuid, text, date, text) from public, anon;
grant execute on function public.enterprise_import_monthly_invoices(
  uuid, integer, integer, jsonb) to authenticated;
grant execute on function public.search_schedulable_invoices(text, integer)
  to authenticated;
grant execute on function public.schedule_invoice_on_calendar(
  uuid, text, date, text) to authenticated;

-- Idempotent repair: only pending, non-cancelled invoices with an active,
-- resolved customer, a real invoice date and an exceptional/customer term.
-- Existing reminders (including manual dates) are never touched.
with row_state as (
  select rv.organization_id, rv.ref_fact,
    bool_or(upper(trim(coalesce(rv.vendedor, ''))) = 'ANULADA') as cancelled,
    coalesce(sum((select coalesce(sum(value::numeric), 0)
      from jsonb_array_elements_text(coalesce(rv.abonos, '[]'::jsonb)))), 0) as paid
  from public.reportes_ventas rv
  where nullif(trim(rv.ref_fact), '') is not null
  group by rv.organization_id, rv.ref_fact
), repairable as (
  select f.organization_id, t.updated_by as user_id, f.ref_fact, f.fecha,
    coalesce(t.exceptional_term_days, c.payment_term_days) as term_days,
    case when t.exceptional_term_days is null
      then 'customer_term' else 'invoice_exception' end as source
  from public.facturas_maestras f
  join row_state rs
    on rs.organization_id = f.organization_id and rs.ref_fact = f.ref_fact
  join public.invoice_payment_terms t
    on t.organization_id = f.organization_id and t.factura_id = f.ref_fact
      and t.active
  join public.billing_customers c
    on c.organization_id = t.organization_id and c.id = t.customer_id
  where not rs.cancelled and f.venta - rs.paid > 0.005
    and f.fecha is not null and t.updated_by is not null
    and coalesce(t.exceptional_term_days, c.payment_term_days) is not null
    and not exists(select 1 from public.payment_reminders r
      where r.organization_id = f.organization_id and r.factura_id = f.ref_fact)
)
insert into public.payment_reminders(
  organization_id, user_id, factura_id, payment_date, active,
  notify_three_days, notify_one_day, date_source, calculated_term_days)
select organization_id, user_id, ref_fact,
  public.next_weekday(fecha + term_days), true, true, true, source, term_days
from repairable
on conflict (organization_id, factura_id) where organization_id is not null
do nothing;

notify pgrst, 'reload schema';
commit;
