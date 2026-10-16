begin;

-- A pre-existing invoice exception is sufficient even when the customer's
-- default term is null.  Keep the same atomic importer, but only request a
-- customer term when neither source can resolve the invoice schedule.
create or replace function public.enterprise_import_monthly_invoices(
  p_request_id uuid, p_year integer, p_month integer, p_invoices jsonb
) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  item jsonb; invoice_ref text; invoice_date date; seller_label text;
  report_name text; next_row integer; inserted_rows integer := 0;
  customer_id uuid; proposed_days integer; canonical_days integer;
  exceptional_days integer; upsert_result jsonb;
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
    select c.payment_term_days, t.exceptional_term_days
    into canonical_days, exceptional_days
    from public.billing_customers c
    join public.invoice_payment_terms t
      on t.organization_id = c.organization_id and t.customer_id = c.id
        and t.factura_id = invoice_ref and t.active
    where c.id = customer_id and c.organization_id = org
    for update of c, t;
    if not found then
      raise exception 'customer could not be resolved for invoice %', invoice_ref;
    end if;
    if coalesce(exceptional_days, canonical_days) is null then
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

revoke all on function public.enterprise_import_monthly_invoices(
  uuid, integer, integer, jsonb) from public, anon;
grant execute on function public.enterprise_import_monthly_invoices(
  uuid, integer, integer, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
