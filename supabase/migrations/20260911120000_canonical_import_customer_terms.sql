begin;

create temporary table import_customer_terms_audit_before on commit drop as
with identified_customers as (
  select c.id from public.billing_customers c
  where c.buyer_identification_normalized is not null
  union
  select distinct t.customer_id
  from public.invoice_payment_terms t
  join public.facturas_maestras f
    on f.organization_id = t.organization_id and f.ref_fact = t.factura_id
  where t.active
    and public.normalize_buyer_identification(f.identificacion_comprador)
        is not null
), ambiguous as (
  select t.organization_id,
    public.normalize_buyer_identification(f.identificacion_comprador)
  from public.invoice_payment_terms t
  join public.facturas_maestras f
    on f.organization_id = t.organization_id and f.ref_fact = t.factura_id
  where t.active
    and public.normalize_buyer_identification(f.identificacion_comprador)
        is not null
  group by 1, 2 having count(distinct t.customer_id) > 1
)
select
  (select count(*) from public.billing_customers)::bigint customer_count,
  (select count(*) from public.facturas_maestras)::bigint invoice_count,
  (select count(*) from public.reportes_ventas)::bigint report_row_count,
  (select count(*) from public.payment_reminders)::bigint reminder_count,
  (select count(*) from public.billing_customers
    where configuration_active and payment_term_days is not null)::bigint
      configured_active,
  (select count(*) from public.billing_customers c
    join identified_customers i on i.id = c.id
    where c.configuration_active and c.payment_term_days is not null)::bigint
      false_pending_candidates,
  (select count(*) from public.billing_customers
    where buyer_identification_normalized is not null)::bigint
      profiles_with_identity,
  (select count(*) from public.billing_customers
    where buyer_identification_normalized is null)::bigint
      legacy_profiles_without_identity,
  (select count(*) from ambiguous)::bigint ambiguous_identities,
  (select md5(coalesce(string_agg(
    id::text || ':' || coalesce(payment_term_days::text, 'NULL'),
    '|' order by id), '')) from public.billing_customers) term_checksum,
  (select max(payment_term_days) from public.billing_customers
    where normalized_name = public.normalize_customer_identity(
      'N59 LORENA SUSANA OCHOA CORREA')) lorena_term_days;

-- Shared by the read-only preview and transactional writer. Historical
-- ownership is accepted only when it identifies exactly one customer.
create or replace function public.resolve_enterprise_import_customer(
  p_organization_id uuid, p_identification text, p_name text,
  p_commercial_name text
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  buyer_id text := public.normalize_buyer_identification(p_identification);
  candidate_ids uuid[];
  resolved_id uuid;
  term_days integer;
begin
  if buyer_id is not null then
    select array_agg(c.id order by c.id) into candidate_ids
    from public.billing_customers c
    where c.organization_id = p_organization_id
      and c.buyer_identification_normalized = buyer_id;

    if coalesce(array_length(candidate_ids, 1), 0) = 0 then
      select array_agg(x.customer_id order by x.customer_id) into candidate_ids
      from (
        select distinct t.customer_id
        from public.invoice_payment_terms t
        join public.facturas_maestras f
          on f.organization_id = t.organization_id
         and f.ref_fact = t.factura_id
        where t.organization_id = p_organization_id and t.active
          and public.normalize_buyer_identification(
                f.identificacion_comprador) = buyer_id
      ) x;
    end if;
  end if;

  if coalesce(array_length(candidate_ids, 1), 0) = 0 then
    select array_agg(c.id order by c.id) into candidate_ids
    from public.billing_customers c
    where c.organization_id = p_organization_id
      and c.buyer_identification_normalized is null
      and c.normalized_name = public.normalize_customer_identity(p_name)
      and c.normalized_commercial_name =
          public.normalize_customer_identity(p_commercial_name);
  end if;

  if coalesce(array_length(candidate_ids, 1), 0) > 1 then
    return jsonb_build_object(
      'status', 'ambiguous',
      'message', 'Hay más de un perfil compatible. Resuelve la identidad del cliente antes de importar.');
  end if;
  if coalesce(array_length(candidate_ids, 1), 0) = 0 then
    return jsonb_build_object('status', 'new');
  end if;

  resolved_id := candidate_ids[1];
  select c.payment_term_days into term_days
  from public.billing_customers c
  where c.organization_id = p_organization_id and c.id = resolved_id;
  return jsonb_build_object(
    'status', case when term_days is null then 'existing_without_term'
                   else 'existing_with_term' end,
    'customer_id', resolved_id,
    'payment_term_days', term_days);
end $$;

revoke all on function public.resolve_enterprise_import_customer(
  uuid, text, text, text) from public, anon, authenticated;

create or replace function public.resolve_enterprise_import_customers(
  p_customers jsonb
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  item jsonb;
  answer jsonb := '[]'::jsonb;
  resolution jsonb;
begin
  if p_customers is null or jsonb_typeof(p_customers) <> 'array'
     or jsonb_array_length(p_customers) > 2000 then
    raise exception 'invalid customer resolution batch';
  end if;
  for item in select value from jsonb_array_elements(p_customers) loop
    if nullif(trim(coalesce(item->>'group_key', '')), '') is null then
      raise exception 'invalid customer resolution key';
    end if;
    resolution := public.resolve_enterprise_import_customer(
      org, coalesce(item->>'identificacion_comprador', ''),
      coalesce(item->>'cliente', ''),
      coalesce(item->>'nombre_comercial', ''));
    answer := answer || jsonb_build_array(
      resolution || jsonb_build_object('group_key', item->>'group_key'));
  end loop;
  return answer;
end $$;

revoke all on function public.resolve_enterprise_import_customers(jsonb)
  from public, anon;
grant execute on function public.resolve_enterprise_import_customers(jsonb)
  to authenticated;

create or replace function public.enterprise_upsert_invoice(
  p_request_id uuid, p_ref_fact text, p_cliente text,
  p_nombre_comercial text, p_fecha date, p_nro_fact text, p_venta numeric,
  p_identificacion_comprador text, p_tipo_identificacion_comprador text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  customer_id uuid;
  result jsonb;
  resolution jsonb;
  buyer_id text := public.normalize_buyer_identification(
    p_identificacion_comprador);
begin
  if nullif(trim(p_ref_fact), '') is null
     or nullif(trim(p_cliente), '') is null or p_fecha is null then
    raise exception 'invalid invoice';
  end if;
  select r.result into result from public.enterprise_requests r
  where r.organization_id = org and r.request_id = p_request_id
    and r.action = 'upsert_invoice';
  if found then return result; end if;

  resolution := public.resolve_enterprise_import_customer(
    org, p_identificacion_comprador, p_cliente, p_nombre_comercial);
  if resolution->>'status' = 'ambiguous' then
    raise exception 'ambiguous customer identity for invoice %', trim(p_ref_fact);
  end if;
  customer_id := (resolution->>'customer_id')::uuid;

  insert into public.facturas_maestras(
    organization_id, ref_fact, cliente, nombre_comercial, fecha, nro_fact,
    venta, identificacion_comprador, tipo_identificacion_comprador)
  values (org, trim(p_ref_fact), trim(p_cliente),
    trim(coalesce(p_nombre_comercial, '')), p_fecha, trim(p_nro_fact), p_venta,
    buyer_id, nullif(trim(coalesce(p_tipo_identificacion_comprador, '')), ''))
  on conflict (ref_fact) do update set
    cliente = excluded.cliente, nombre_comercial = excluded.nombre_comercial,
    fecha = excluded.fecha, nro_fact = excluded.nro_fact, venta = excluded.venta,
    identificacion_comprador = coalesce(excluded.identificacion_comprador,
      public.facturas_maestras.identificacion_comprador),
    tipo_identificacion_comprador = coalesce(
      excluded.tipo_identificacion_comprador,
      public.facturas_maestras.tipo_identificacion_comprador)
  where public.facturas_maestras.organization_id = org;

  if customer_id is null then
    insert into public.billing_customers(
      organization_id, name, commercial_name, buyer_identification,
      buyer_identification_normalized, buyer_identification_type,
      profile_invoice_date, profile_invoice_ref, updated_by)
    values (org, trim(p_cliente), trim(coalesce(p_nombre_comercial, '')),
      buyer_id, buyer_id,
      nullif(trim(coalesce(p_tipo_identificacion_comprador, '')), ''),
      p_fecha, trim(p_ref_fact), auth.uid())
    returning id into customer_id;
  else
    update public.billing_customers c set
      buyer_identification = case
        when c.buyer_identification_normalized is null then buyer_id
        else c.buyer_identification end,
      buyer_identification_normalized = coalesce(
        c.buyer_identification_normalized, buyer_id),
      buyer_identification_type = coalesce(
        nullif(trim(coalesce(p_tipo_identificacion_comprador, '')), ''),
        c.buyer_identification_type),
      name = case
        when p_fecha > coalesce(c.profile_invoice_date, '-infinity'::date)
          or (p_fecha = c.profile_invoice_date
              and trim(p_ref_fact) >= coalesce(c.profile_invoice_ref, ''))
        then trim(p_cliente) else c.name end,
      commercial_name = case
        when (p_fecha > coalesce(c.profile_invoice_date, '-infinity'::date)
          or (p_fecha = c.profile_invoice_date
              and trim(p_ref_fact) >= coalesce(c.profile_invoice_ref, '')))
          and trim(coalesce(p_nombre_comercial, '')) <> ''
        then trim(p_nombre_comercial) else c.commercial_name end,
      profile_invoice_date = case
        when p_fecha >= coalesce(c.profile_invoice_date, '-infinity'::date)
        then p_fecha else c.profile_invoice_date end,
      profile_invoice_ref = case
        when p_fecha >= coalesce(c.profile_invoice_date, '-infinity'::date)
        then trim(p_ref_fact) else c.profile_invoice_ref end,
      updated_at = clock_timestamp(), updated_by = auth.uid()
    where c.id = customer_id and c.organization_id = org;
  end if;

  insert into public.invoice_payment_terms(
    organization_id, factura_id, customer_id, active, updated_by)
  values (org, trim(p_ref_fact), customer_id, true, auth.uid())
  on conflict (organization_id, factura_id) do update set
    customer_id = excluded.customer_id, active = true,
    updated_at = clock_timestamp(), updated_by = auth.uid();
  perform public.sync_enterprise_reminder(org, trim(p_ref_fact), p_request_id,
    'Automatic reschedule from invoice data');
  result := jsonb_build_object(
    'factura_id', trim(p_ref_fact), 'customer_id', customer_id);
  insert into public.enterprise_requests(
    organization_id, request_id, action, result)
  values (org, p_request_id, 'upsert_invoice', result);
  return result;
end $$;

revoke all on function public.enterprise_upsert_invoice(
  uuid, text, text, text, date, text, numeric, text, text) from public, anon;
grant execute on function public.enterprise_upsert_invoice(
  uuid, text, text, text, date, text, numeric, text, text) to authenticated;

-- Preserve the signature while making missing terms mandatory server-side.
-- If a stale preview submits a value for an already configured customer, the
-- locked canonical database value wins and is never overwritten.
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
      perform public.sync_enterprise_reminder(
        org, invoice_ref, p_request_id,
        'Automatic schedule after imported customer term');
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

do $$
declare
  before_row record;
  after_customer_count bigint;
  after_invoice_count bigint;
  after_report_row_count bigint;
  after_reminder_count bigint;
  after_term_checksum text;
begin
  select * into before_row from import_customer_terms_audit_before;
  select count(*), md5(coalesce(string_agg(
    id::text || ':' || coalesce(payment_term_days::text, 'NULL'),
    '|' order by id), ''))
  into after_customer_count, after_term_checksum
  from public.billing_customers;
  select count(*) into after_invoice_count from public.facturas_maestras;
  select count(*) into after_report_row_count from public.reportes_ventas;
  select count(*) into after_reminder_count from public.payment_reminders;
  if (after_customer_count, after_invoice_count, after_report_row_count,
      after_reminder_count, after_term_checksum) is distinct from
     (before_row.customer_count, before_row.invoice_count,
      before_row.report_row_count, before_row.reminder_count,
      before_row.term_checksum) then
    raise exception 'canonical import migration modified business data';
  end if;
  raise notice 'sanitized import audit: configured=%, false_pending_candidates=%, profiles_with_identity=%, legacy_without_identity=%, ambiguous=%, lorena_term_days=%',
    before_row.configured_active, before_row.false_pending_candidates,
    before_row.profiles_with_identity,
    before_row.legacy_profiles_without_identity,
    before_row.ambiguous_identities, before_row.lorena_term_days;
end $$;

notify pgrst, 'reload schema';
commit;
