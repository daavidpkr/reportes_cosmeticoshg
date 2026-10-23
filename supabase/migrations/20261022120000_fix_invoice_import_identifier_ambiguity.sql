begin;

-- Keep the monthly import atomic while making every PL/pgSQL local distinct
-- from table columns and every SQL column reference explicit.
create or replace function public.enterprise_import_monthly_invoices(
  p_request_id uuid, p_year integer, p_month integer, p_invoices jsonb
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid := public.require_current_organization_id();
  v_item jsonb;
  v_invoice_ref text;
  v_invoice_date date;
  v_seller_label text;
  v_report_name text;
  v_next_row integer;
  v_inserted_rows integer := 0;
  v_customer_id uuid;
  v_proposed_days integer;
  v_canonical_days integer;
  v_exceptional_days integer;
  v_upsert_result jsonb;
begin
  if p_year < 2000 or p_month not between 1 and 12 or p_invoices is null
     or jsonb_typeof(p_invoices) <> 'array' then
    raise exception 'invalid monthly invoice batch';
  end if;

  if exists (
    select 1
    from public.enterprise_requests as er
    where er.organization_id = v_organization_id
      and er.request_id = p_request_id
  ) then
    return coalesce((
      select (er.result->>'inserted_rows')::integer
      from public.enterprise_requests as er
      where er.organization_id = v_organization_id
        and er.request_id = p_request_id
    ), 0);
  end if;

  for v_item in
    select invoice_element.value
    from jsonb_array_elements(p_invoices) as invoice_element(value)
  loop
    if v_item ? 'payment_term_days' then
      begin
        v_proposed_days := (v_item->>'payment_term_days')::integer;
      exception when others then
        raise exception 'invalid payment term';
      end;
      if v_proposed_days < 0 or v_proposed_days > 3650 then
        raise exception 'invalid payment term';
      end if;
    end if;
  end loop;

  v_report_name := (array[
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ])[p_month] || ' ' || p_year::text;

  perform 1
  from public.reportes_mensuales as rm
  where rm.id = p_year::text || '-' || lpad(p_month::text, 2, '0')
    and rm.organization_id = v_organization_id
  for update;
  if not found then
    raise exception 'monthly report not found';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_organization_id::text || ':' || v_report_name, 0)
  );

  select coalesce(max(rv.nro_fila), 0)
  into v_next_row
  from public.reportes_ventas as rv
  where rv.organization_id = v_organization_id
    and rv.mes_reporte = v_report_name;

  for v_item in
    select invoice_element.value
    from jsonb_array_elements(p_invoices) as invoice_element(value)
    order by
      case
        when trim(invoice_element.value->>'ref_fact') ~ '^[0-9]+$' then 0
        else 1
      end,
      case
        when trim(invoice_element.value->>'ref_fact') ~ '^[0-9]+$'
          then trim(invoice_element.value->>'ref_fact')::numeric
      end,
      trim(invoice_element.value->>'ref_fact')
  loop
    v_invoice_ref := trim(coalesce(v_item->>'ref_fact', ''));
    v_seller_label := trim(coalesce(v_item->>'vendedor', ''));
    begin
      v_invoice_date := (v_item->>'fecha')::date;
    exception when others then
      raise exception 'invalid invoice date for %', v_invoice_ref;
    end;

    if v_invoice_ref = ''
       or v_invoice_ref <> trim(coalesce(v_item->>'nro_fact', ''))
       or v_invoice_date < make_date(p_year, p_month, 1)
       or v_invoice_date >=
          (make_date(p_year, p_month, 1) + interval '1 month')::date
       or v_seller_label = '' then
      raise exception 'invalid invoice % for selected report', v_invoice_ref;
    end if;

    if not exists (
      select 1
      from public.vendedores as seller
      where seller.organization_id = v_organization_id
        and v_seller_label = case
          when trim(seller.codigo) = '' then trim(seller.nombre)
          else trim(seller.codigo) || ' - ' || trim(seller.nombre)
        end
    ) then
      raise exception 'invalid seller for invoice %', v_invoice_ref;
    end if;

    v_upsert_result := public.enterprise_upsert_invoice(
      gen_random_uuid(),
      v_invoice_ref,
      trim(coalesce(v_item->>'cliente', '')),
      trim(coalesce(v_item->>'nombre_comercial', '')),
      v_invoice_date,
      v_invoice_ref,
      (v_item->>'venta')::numeric,
      coalesce(v_item->>'identificacion_comprador', ''),
      coalesce(v_item->>'tipo_identificacion_comprador', '')
    );
    v_customer_id := (v_upsert_result->>'customer_id')::uuid;

    select bc.payment_term_days, ipt.exceptional_term_days
    into v_canonical_days, v_exceptional_days
    from public.billing_customers as bc
    join public.invoice_payment_terms as ipt
      on ipt.organization_id = bc.organization_id
      and ipt.customer_id = bc.id
      and ipt.factura_id = v_invoice_ref
      and ipt.active
    where bc.id = v_customer_id
      and bc.organization_id = v_organization_id
    for update of bc, ipt;
    if not found then
      raise exception 'customer could not be resolved for invoice %',
        v_invoice_ref;
    end if;

    if coalesce(v_exceptional_days, v_canonical_days) is null then
      if not (v_item ? 'payment_term_days') then
        raise exception 'customer payment term is pending for invoice %',
          v_invoice_ref;
      end if;
      v_proposed_days := (v_item->>'payment_term_days')::integer;
      update public.billing_customers as bc
      set payment_term_days = v_proposed_days,
          configuration_active = true,
          updated_at = clock_timestamp(),
          updated_by = auth.uid()
      where bc.id = v_customer_id
        and bc.organization_id = v_organization_id
        and bc.payment_term_days is null;
    end if;

    if not exists (
      select 1
      from public.reportes_ventas as rv
      where rv.organization_id = v_organization_id
        and rv.mes_reporte = v_report_name
        and rv.ref_fact = v_invoice_ref
    ) then
      v_next_row := v_next_row + 1;
      insert into public.reportes_ventas(
        organization_id,
        nro_fila,
        ref_fact,
        vendedor,
        esmaltes,
        abonos,
        numeros_recibo,
        comentarios_abonos,
        mes_reporte
      ) values (
        v_organization_id,
        v_next_row,
        v_invoice_ref,
        v_seller_label,
        0,
        '[]'::jsonb,
        '{}'::bigint[],
        '[]'::jsonb,
        v_report_name
      );
      v_inserted_rows := v_inserted_rows + 1;
    end if;

    if public.sync_enterprise_reminder(
      v_organization_id,
      v_invoice_ref,
      p_request_id,
      'Atomic schedule after invoice import'
    ) is null then
      raise exception
        'invoice % could not be scheduled: customer or payment term missing',
        v_invoice_ref;
    end if;
  end loop;

  insert into public.enterprise_requests(
    organization_id,
    request_id,
    action,
    result
  ) values (
    v_organization_id,
    p_request_id,
    'import_monthly_invoices',
    jsonb_build_object('inserted_rows', v_inserted_rows)
  );

  return v_inserted_rows;
end
$$;

revoke all on function public.enterprise_import_monthly_invoices(
  uuid, integer, integer, jsonb
) from public, anon;
grant execute on function public.enterprise_import_monthly_invoices(
  uuid, integer, integer, jsonb
) to authenticated;

notify pgrst, 'reload schema';

commit;
