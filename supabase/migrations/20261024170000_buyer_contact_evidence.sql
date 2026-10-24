begin;

alter table public.facturas_maestras
  add column direccion_comprador text not null default '',
  add column telefono_comprador text not null default '',
  add column correo_comprador text not null default '';

alter table public.billing_customers
  add column address text not null default '',
  add column phone text not null default '',
  add column email text not null default '',
  add column contact_invoice_date date,
  add column contact_invoice_ref text;

alter table public.facturas_maestras
  add constraint facturas_maestras_buyer_phone_valid check (
    telefono_comprador = '' or telefono_comprador ~ '^\+?[0-9]{7,15}$'),
  add constraint facturas_maestras_buyer_email_valid check (
    correo_comprador = '' or
    (length(correo_comprador) <= 254 and
     correo_comprador ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'));

alter table public.billing_customers
  add constraint billing_customers_phone_valid check (
    phone = '' or phone ~ '^\+?[0-9]{7,15}$'),
  add constraint billing_customers_email_valid check (
    email = '' or
    (length(email) <= 254 and
     email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'));

create or replace function public.clean_buyer_address(value text)
returns text language sql immutable set search_path = '' as $$
  select left(regexp_replace(trim(coalesce(value, '')), '[[:space:]]+', ' ', 'g'), 500);
$$;

create or replace function public.clean_buyer_phone(value text)
returns text language sql immutable set search_path = '' as $$
  with cleaned as (
    select regexp_replace(trim(coalesce(value, '')), '[^0-9+]', '', 'g') v
  ), normalized as (
    select case
      when v ~ '^\+?[0-9]{7,15}$' then v
      else ''
    end v from cleaned
  ) select v from normalized;
$$;

create or replace function public.clean_buyer_email(value text)
returns text language sql immutable set search_path = '' as $$
  with cleaned as (select lower(trim(coalesce(value, ''))) v)
  select case
    when length(v) <= 254 and
         v ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then v
    else ''
  end from cleaned;
$$;

create or replace function public.invoice_profile_is_newer(
  p_date date, p_reference text, p_current_date date, p_current_reference text
) returns boolean language sql immutable set search_path = '' as $$
  select p_current_date is null
    or p_date > p_current_date
    or (p_date = p_current_date and (
      case
        when trim(coalesce(p_reference, '')) ~ '^[0-9]+$'
         and trim(coalesce(p_current_reference, '')) ~ '^[0-9]+$'
          then trim(p_reference)::numeric >= trim(p_current_reference)::numeric
        else trim(coalesce(p_reference, '')) >= trim(coalesce(p_current_reference, ''))
      end));
$$;

revoke all on function public.clean_buyer_address(text) from public, anon, authenticated;
revoke all on function public.clean_buyer_phone(text) from public, anon, authenticated;
revoke all on function public.clean_buyer_email(text) from public, anon, authenticated;
revoke all on function public.invoice_profile_is_newer(date,text,date,text)
  from public, anon, authenticated;

create or replace function public.enterprise_upsert_invoice(
  p_request_id uuid, p_ref_fact text, p_cliente text,
  p_nombre_comercial text, p_fecha date, p_nro_fact text, p_venta numeric,
  p_identificacion_comprador text, p_tipo_identificacion_comprador text,
  p_direccion_comprador text, p_telefono_comprador text,
  p_correo_comprador text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  customer_id uuid;
  result jsonb;
  resolution jsonb;
  buyer_id text := public.normalize_buyer_identification(p_identificacion_comprador);
  buyer_address text := public.clean_buyer_address(p_direccion_comprador);
  buyer_phone text := public.clean_buyer_phone(p_telefono_comprador);
  buyer_email text := public.clean_buyer_email(p_correo_comprador);
  comparison_key text :=
    public.normalize_customer_match_identity(p_cliente) || chr(31) ||
    public.normalize_customer_match_identity(p_nombre_comercial);
begin
  if nullif(trim(p_ref_fact), '') is null
     or nullif(trim(p_cliente), '') is null or p_fecha is null then
    raise exception 'invalid invoice';
  end if;
  select r.result into result from public.enterprise_requests r
  where r.organization_id = org and r.request_id = p_request_id
    and r.action = 'upsert_invoice';
  if found then return result; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    org::text || ':customer-name:' || comparison_key, 0));
  if buyer_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      org::text || ':customer-id:' || buyer_id, 0));
  end if;
  resolution := public.resolve_enterprise_import_customer(
    org, p_identificacion_comprador, p_cliente, p_nombre_comercial);
  if resolution->>'status' = 'ambiguous' then
    raise exception
      'Identidad ambigua para la factura %: hay varios perfiles compatibles',
      trim(p_ref_fact);
  end if;
  customer_id := (resolution->>'customer_id')::uuid;

  insert into public.facturas_maestras(
    organization_id, ref_fact, cliente, nombre_comercial, fecha, nro_fact,
    venta, identificacion_comprador, tipo_identificacion_comprador,
    direccion_comprador, telefono_comprador, correo_comprador)
  values (org, trim(p_ref_fact), trim(p_cliente),
    trim(coalesce(p_nombre_comercial, '')), p_fecha, trim(p_nro_fact), p_venta,
    buyer_id, nullif(trim(coalesce(p_tipo_identificacion_comprador, '')), ''),
    buyer_address, buyer_phone, buyer_email)
  on conflict (ref_fact) do update set
    cliente = excluded.cliente, nombre_comercial = excluded.nombre_comercial,
    fecha = excluded.fecha, nro_fact = excluded.nro_fact, venta = excluded.venta,
    identificacion_comprador = coalesce(excluded.identificacion_comprador,
      public.facturas_maestras.identificacion_comprador),
    tipo_identificacion_comprador = coalesce(
      excluded.tipo_identificacion_comprador,
      public.facturas_maestras.tipo_identificacion_comprador),
    direccion_comprador = coalesce(nullif(excluded.direccion_comprador, ''),
      public.facturas_maestras.direccion_comprador),
    telefono_comprador = coalesce(nullif(excluded.telefono_comprador, ''),
      public.facturas_maestras.telefono_comprador),
    correo_comprador = coalesce(nullif(excluded.correo_comprador, ''),
      public.facturas_maestras.correo_comprador)
  where public.facturas_maestras.organization_id = org;

  if customer_id is null then
    insert into public.billing_customers(
      organization_id, name, commercial_name, buyer_identification,
      buyer_identification_normalized, buyer_identification_type,
      profile_invoice_date, profile_invoice_ref, address, phone, email,
      contact_invoice_date, contact_invoice_ref, updated_by)
    values (org, trim(p_cliente), trim(coalesce(p_nombre_comercial, '')),
      buyer_id, buyer_id,
      nullif(trim(coalesce(p_tipo_identificacion_comprador, '')), ''),
      p_fecha, trim(p_ref_fact),
      case when buyer_id is not null then buyer_address else '' end,
      case when buyer_id is not null then buyer_phone else '' end,
      case when buyer_id is not null then buyer_email else '' end,
      case when buyer_id is not null then p_fecha end,
      case when buyer_id is not null then trim(p_ref_fact) end,
      auth.uid())
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
        when public.invoice_profile_is_newer(
          p_fecha, p_ref_fact, c.profile_invoice_date, c.profile_invoice_ref)
          and not (trim(c.name) ~* '^N[0-9]+\s+'
                   and trim(p_cliente) !~* '^N[0-9]+\s+')
        then trim(p_cliente) else c.name end,
      commercial_name = case
        when public.invoice_profile_is_newer(
          p_fecha, p_ref_fact, c.profile_invoice_date, c.profile_invoice_ref)
          and trim(coalesce(p_nombre_comercial, '')) <> ''
        then trim(p_nombre_comercial) else c.commercial_name end,
      profile_invoice_date = case
        when public.invoice_profile_is_newer(
          p_fecha, p_ref_fact, c.profile_invoice_date, c.profile_invoice_ref)
        then p_fecha else c.profile_invoice_date end,
      profile_invoice_ref = case
        when public.invoice_profile_is_newer(
          p_fecha, p_ref_fact, c.profile_invoice_date, c.profile_invoice_ref)
        then trim(p_ref_fact) else c.profile_invoice_ref end,
      address = case
        when buyer_id is not null and buyer_address <> ''
          and public.invoice_profile_is_newer(
            p_fecha, p_ref_fact, c.contact_invoice_date, c.contact_invoice_ref)
        then buyer_address else c.address end,
      phone = case
        when buyer_id is not null and buyer_phone <> ''
          and public.invoice_profile_is_newer(
            p_fecha, p_ref_fact, c.contact_invoice_date, c.contact_invoice_ref)
        then buyer_phone else c.phone end,
      email = case
        when buyer_id is not null and buyer_email <> ''
          and public.invoice_profile_is_newer(
            p_fecha, p_ref_fact, c.contact_invoice_date, c.contact_invoice_ref)
        then buyer_email else c.email end,
      contact_invoice_date = case
        when buyer_id is not null and public.invoice_profile_is_newer(
          p_fecha, p_ref_fact, c.contact_invoice_date, c.contact_invoice_ref)
        then p_fecha else c.contact_invoice_date end,
      contact_invoice_ref = case
        when buyer_id is not null and public.invoice_profile_is_newer(
          p_fecha, p_ref_fact, c.contact_invoice_date, c.contact_invoice_ref)
        then trim(p_ref_fact) else c.contact_invoice_ref end,
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
  uuid,text,text,text,date,text,numeric,text,text,text,text,text)
  from public, anon;
grant execute on function public.enterprise_upsert_invoice(
  uuid,text,text,text,date,text,numeric,text,text,text,text,text)
  to authenticated;

-- Compatibility for installed clients that do not send contact evidence yet.
create or replace function public.enterprise_upsert_invoice(
  p_request_id uuid, p_ref_fact text, p_cliente text,
  p_nombre_comercial text, p_fecha date, p_nro_fact text, p_venta numeric,
  p_identificacion_comprador text, p_tipo_identificacion_comprador text
) returns jsonb language sql security definer set search_path = '' as $$
  select public.enterprise_upsert_invoice(
    p_request_id, p_ref_fact, p_cliente, p_nombre_comercial, p_fecha,
    p_nro_fact, p_venta, p_identificacion_comprador,
    p_tipo_identificacion_comprador, '', '', '');
$$;
revoke all on function public.enterprise_upsert_invoice(
  uuid,text,text,text,date,text,numeric,text,text) from public, anon;
grant execute on function public.enterprise_upsert_invoice(
  uuid,text,text,text,date,text,numeric,text,text) to authenticated;

-- Preserve the current atomic importer, payments, terms and scheduling while
-- forwarding the three new historical fields to the canonical upsert.
create or replace function public.enterprise_import_monthly_invoices(
  p_request_id uuid, p_year integer, p_month integer, p_invoices jsonb
) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_organization_id uuid := public.require_current_organization_id();
  v_item jsonb; v_invoice_ref text; v_invoice_date date; v_seller_label text;
  v_report_name text; v_next_row integer; v_inserted_rows integer := 0;
  v_customer_id uuid; v_proposed_days integer; v_canonical_days integer;
  v_exceptional_days integer; v_upsert_result jsonb; v_has_payment boolean;
  v_payment_amount numeric; v_payment_receipt bigint;
begin
  if p_year < 2000 or p_month not between 1 and 12 or p_invoices is null
     or jsonb_typeof(p_invoices) <> 'array' then
    raise exception 'invalid monthly invoice batch';
  end if;
  if exists (select 1 from public.enterprise_requests er
    where er.organization_id=v_organization_id and er.request_id=p_request_id)
  then return coalesce((select (er.result->>'inserted_rows')::integer
    from public.enterprise_requests er where er.organization_id=v_organization_id
      and er.request_id=p_request_id),0); end if;

  for v_item in select value from jsonb_array_elements(p_invoices) loop
    if v_item ? 'payment_term_days' then
      begin v_proposed_days := (v_item->>'payment_term_days')::integer;
      exception when others then raise exception 'invalid payment term'; end;
      if v_proposed_days < 0 or v_proposed_days > 3650 then
        raise exception 'invalid payment term'; end if;
    end if;
    v_has_payment := v_item ? 'abonos' or v_item ? 'numeros_recibo'
      or v_item ? 'comentarios_abonos';
    if v_has_payment then
      if not (v_item ? 'abonos') or not (v_item ? 'numeros_recibo')
         or not (v_item ? 'comentarios_abonos')
         or jsonb_typeof(v_item->'abonos') <> 'array'
         or jsonb_typeof(v_item->'numeros_recibo') <> 'array'
         or jsonb_typeof(v_item->'comentarios_abonos') <> 'array'
         or jsonb_array_length(v_item->'abonos') <> 1
         or jsonb_array_length(v_item->'numeros_recibo') <> 1
         or jsonb_array_length(v_item->'comentarios_abonos') <> 1 then
        raise exception 'import payment arrays must contain one aligned tuple';
      end if;
      if upper(trim(coalesce(v_item->>'vendedor',''))) in ('ANUL','ANULADA')
         or jsonb_typeof(v_item->'abonos'->0) <> 'number' then
        raise exception 'cancelled invoice cannot receive payment'; end if;
      begin
        v_payment_amount := (v_item->'abonos'->>0)::numeric;
        if v_payment_amount <= 0 or
           abs(v_payment_amount-(v_item->>'venta')::numeric) > .005 then
          raise exception 'import payment must cover the full invoice balance';
        end if;
      exception when invalid_text_representation or numeric_value_out_of_range
        then raise exception 'invalid import payment amount'; end;
      if v_item->'numeros_recibo'->0 <> 'null'::jsonb then
        if jsonb_typeof(v_item->'numeros_recibo'->0) <> 'number'
           or (v_item->'numeros_recibo'->>0) !~ '^[0-9]+$' then
          raise exception 'invalid import receipt number'; end if;
        begin v_payment_receipt := (v_item->'numeros_recibo'->>0)::bigint;
        exception when invalid_text_representation or numeric_value_out_of_range
          then raise exception 'invalid import receipt number'; end;
        if v_payment_receipt <= 0 or v_payment_receipt > 9007199254740991 then
          raise exception 'invalid import receipt number'; end if;
      end if;
      if v_item->'comentarios_abonos'->0 <> 'null'::jsonb and
         jsonb_typeof(v_item->'comentarios_abonos'->0) <> 'string' then
        raise exception 'invalid import payment comment'; end if;
    end if;
  end loop;

  v_report_name := (array['Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[p_month]
    || ' ' || p_year::text;
  perform 1 from public.reportes_mensuales rm
    where rm.id=p_year::text||'-'||lpad(p_month::text,2,'0')
      and rm.organization_id=v_organization_id for update;
  if not found then raise exception 'monthly report not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    v_organization_id::text||':'||v_report_name,0));
  select coalesce(max(rv.nro_fila),0) into v_next_row
    from public.reportes_ventas rv
    where rv.organization_id=v_organization_id and rv.mes_reporte=v_report_name;

  for v_item in select value from jsonb_array_elements(p_invoices)
    order by case when trim(value->>'ref_fact')~'^[0-9]+$' then 0 else 1 end,
      case when trim(value->>'ref_fact')~'^[0-9]+$'
        then trim(value->>'ref_fact')::numeric end, trim(value->>'ref_fact') loop
    v_invoice_ref:=trim(coalesce(v_item->>'ref_fact',''));
    v_seller_label:=trim(coalesce(v_item->>'vendedor',''));
    v_has_payment:=v_item ? 'abonos'; v_payment_amount:=null;
    v_payment_receipt:=null;
    if v_has_payment then
      v_payment_amount:=(v_item->'abonos'->>0)::numeric;
      if v_item->'numeros_recibo'->0 <> 'null'::jsonb then
        v_payment_receipt:=(v_item->'numeros_recibo'->>0)::bigint; end if;
    end if;
    begin v_invoice_date:=(v_item->>'fecha')::date;
    exception when others then
      raise exception 'invalid invoice date for %',v_invoice_ref; end;
    if v_invoice_ref='' or v_invoice_ref<>trim(coalesce(v_item->>'nro_fact',''))
       or v_invoice_date<make_date(p_year,p_month,1)
       or v_invoice_date>=(make_date(p_year,p_month,1)+interval '1 month')::date
       or v_seller_label='' then
      raise exception 'invalid invoice % for selected report',v_invoice_ref;
    end if;
    if not exists(select 1 from public.vendedores seller
      where seller.organization_id=v_organization_id and v_seller_label=case
        when trim(seller.codigo)='' then trim(seller.nombre)
        else trim(seller.codigo)||' - '||trim(seller.nombre) end) then
      raise exception 'invalid seller for invoice %',v_invoice_ref; end if;

    v_upsert_result:=public.enterprise_upsert_invoice(gen_random_uuid(),
      v_invoice_ref,trim(coalesce(v_item->>'cliente','')),
      trim(coalesce(v_item->>'nombre_comercial','')),v_invoice_date,
      v_invoice_ref,(v_item->>'venta')::numeric,
      coalesce(v_item->>'identificacion_comprador',''),
      coalesce(v_item->>'tipo_identificacion_comprador',''),
      coalesce(v_item->>'direccion_comprador',''),
      coalesce(v_item->>'telefono_comprador',''),
      coalesce(v_item->>'correo_comprador',''));
    v_customer_id:=(v_upsert_result->>'customer_id')::uuid;
    select bc.payment_term_days,ipt.exceptional_term_days
      into v_canonical_days,v_exceptional_days
      from public.billing_customers bc join public.invoice_payment_terms ipt
        on ipt.organization_id=bc.organization_id and ipt.customer_id=bc.id
        and ipt.factura_id=v_invoice_ref and ipt.active
      where bc.id=v_customer_id and bc.organization_id=v_organization_id
      for update of bc,ipt;
    if not found then raise exception
      'customer could not be resolved for invoice %',v_invoice_ref; end if;
    if coalesce(v_exceptional_days,v_canonical_days) is null then
      if not (v_item ? 'payment_term_days') then raise exception
        'customer payment term is pending for invoice %',v_invoice_ref; end if;
      v_proposed_days:=(v_item->>'payment_term_days')::integer;
      update public.billing_customers bc set payment_term_days=v_proposed_days,
        configuration_active=true,updated_at=clock_timestamp(),updated_by=auth.uid()
        where bc.id=v_customer_id and bc.organization_id=v_organization_id
          and bc.payment_term_days is null;
    end if;
    if not exists(select 1 from public.reportes_ventas rv
      where rv.organization_id=v_organization_id
        and rv.mes_reporte=v_report_name and rv.ref_fact=v_invoice_ref) then
      v_next_row:=v_next_row+1;
      insert into public.reportes_ventas(organization_id,nro_fila,ref_fact,
        vendedor,esmaltes,abonos,numeros_recibo,comentarios_abonos,mes_reporte)
      values(v_organization_id,v_next_row,v_invoice_ref,v_seller_label,0,
        case when v_has_payment then jsonb_build_array(v_payment_amount)
          else '[]'::jsonb end,
        case when v_has_payment then array[v_payment_receipt]::bigint[]
          else '{}'::bigint[] end,
        case when v_has_payment then v_item->'comentarios_abonos'
          else '[]'::jsonb end,v_report_name);
      v_inserted_rows:=v_inserted_rows+1;
    end if;
    if v_has_payment then
      update public.payment_reminders r set active=false
        where r.organization_id=v_organization_id
          and r.factura_id=v_invoice_ref and r.active;
    elsif public.sync_enterprise_reminder(v_organization_id,v_invoice_ref,
      p_request_id,'Atomic schedule after invoice import') is null then
      raise exception
        'invoice % could not be scheduled: customer or payment term missing',
        v_invoice_ref;
    end if;
  end loop;
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(v_organization_id,p_request_id,'import_monthly_invoices',
      jsonb_build_object('inserted_rows',v_inserted_rows));
  return v_inserted_rows;
end $$;

revoke all on function public.enterprise_import_monthly_invoices(
  uuid,integer,integer,jsonb) from public,anon;
grant execute on function public.enterprise_import_monthly_invoices(
  uuid,integer,integer,jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
