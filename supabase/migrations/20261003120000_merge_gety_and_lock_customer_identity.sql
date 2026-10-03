-- Consolidate the verified GETY duplicate and make invoice imports share one
-- concurrency-safe customer identity resolution.
begin;

create or replace function public.normalize_customer_match_identity(value text)
returns text language sql immutable set search_path = '' as $$
  select lower(regexp_replace(
    regexp_replace(trim(coalesce(value, '')), '^n[0-9]+\s+', '', 'i'),
    '\s+', ' ', 'g'));
$$;
revoke all on function public.normalize_customer_match_identity(text)
  from public, anon, authenticated;

-- Invoice ownership is the only direct customer relation. Rows containing
-- amounts, receipts, comments, sellers, reminders and dates stay untouched.
do $$
declare
  target_name constant text := 'gety salud y diagnóstico s.a.s.';
  target_commercial constant text := 'farmacity';
  canonical public.billing_customers%rowtype;
  duplicate public.billing_customers%rowtype;
  matching_count integer;
  canonical_count integer;
  duplicate_count integer;
  relation_count bigint;
  invoice_count bigint;
  report_count bigint;
  reminder_count bigint;
  followup_count bigint;
  event_count bigint;
  invoice_checksum text;
  report_checksum text;
  reminder_checksum text;
  followup_checksum text;
  event_checksum text;
  after_count bigint;
  after_checksum text;
begin
  select count(*),
    count(*) filter (where trim(c.name) ~* '^N[0-9]+\s+'),
    count(*) filter (where trim(c.name) !~* '^N[0-9]+\s+')
  into matching_count, canonical_count, duplicate_count
  from public.billing_customers c
  where public.normalize_customer_match_identity(c.name) = target_name
    and public.normalize_customer_match_identity(c.commercial_name) =
        target_commercial;

  if matching_count = 0 then return; end if;
  if matching_count = 1 and canonical_count = 1 then return; end if;
  if matching_count <> 2 or canonical_count <> 1 or duplicate_count <> 1 then
    raise exception
      'GETY consolidation aborted: expected one N-prefixed and one duplicate profile';
  end if;

  select * into canonical from public.billing_customers c
  where public.normalize_customer_match_identity(c.name) = target_name
    and public.normalize_customer_match_identity(c.commercial_name) =
        target_commercial
    and trim(c.name) ~* '^N[0-9]+\s+' for update;
  select * into duplicate from public.billing_customers c
  where public.normalize_customer_match_identity(c.name) = target_name
    and public.normalize_customer_match_identity(c.commercial_name) =
        target_commercial
    and trim(c.name) !~* '^N[0-9]+\s+' for update;

  if canonical.organization_id <> duplicate.organization_id
     or canonical.buyer_identification_normalized is distinct from
        '0195172153001'
     or duplicate.buyer_identification_normalized is not null then
    raise exception 'GETY consolidation aborted: verified identities changed';
  end if;
  if canonical.commercial_name <> 'FARMACITY'
     or canonical.payment_term_days is distinct from 60
     or not canonical.configuration_active then
    raise exception 'GETY consolidation aborted: canonical configuration changed';
  end if;

  if exists (
    select 1 from pg_constraint fk
    where fk.contype = 'f'
      and fk.confrelid = 'public.billing_customers'::regclass
      and fk.conrelid <> 'public.invoice_payment_terms'::regclass
  ) then
    raise exception 'GETY consolidation aborted: unknown customer relation';
  end if;

  select count(*) into relation_count from public.invoice_payment_terms t
  where t.organization_id = canonical.organization_id
    and t.customer_id in (canonical.id, duplicate.id);
  if relation_count <> 3 then
    raise exception
      'GETY consolidation aborted: expected 3 invoice relationships, found %',
      relation_count;
  end if;

  select count(*), md5(coalesce(string_agg(to_jsonb(f)::text, '|'
      order by f.ref_fact), ''))
  into invoice_count, invoice_checksum
  from public.facturas_maestras f
  join public.invoice_payment_terms t
    on t.organization_id = f.organization_id and t.factura_id = f.ref_fact
  where t.organization_id = canonical.organization_id
    and t.customer_id in (canonical.id, duplicate.id);
  select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, '|'
      order by r.id), ''))
  into report_count, report_checksum from public.reportes_ventas r
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.ref_fact
        and t.customer_id in (canonical.id, duplicate.id));
  select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, '|'
      order by r.id), ''))
  into reminder_count, reminder_checksum from public.payment_reminders r
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.factura_id
        and t.customer_id in (canonical.id, duplicate.id));
  select count(*), md5(coalesce(string_agg(to_jsonb(f)::text, '|'
      order by f.id), ''))
  into followup_count, followup_checksum from public.payment_followups f
  join public.payment_reminders r on r.id = f.reminder_id
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.factura_id
        and t.customer_id in (canonical.id, duplicate.id));
  select count(*), md5(coalesce(string_agg(to_jsonb(e)::text, '|'
      order by e.id), ''))
  into event_count, event_checksum from public.payment_notification_events e
  join public.payment_reminders r on r.id = e.reminder_id
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.factura_id
        and t.customer_id in (canonical.id, duplicate.id));

  update public.invoice_payment_terms
  set customer_id = canonical.id, updated_at = clock_timestamp()
  where organization_id = canonical.organization_id
    and customer_id = duplicate.id;
  if exists (select 1 from public.invoice_payment_terms
      where organization_id = canonical.organization_id
        and customer_id = duplicate.id) then
    raise exception 'GETY consolidation aborted: duplicate relations remain';
  end if;

  select count(*), md5(coalesce(string_agg(to_jsonb(f)::text, '|'
      order by f.ref_fact), '')) into after_count, after_checksum
  from public.facturas_maestras f join public.invoice_payment_terms t
    on t.organization_id = f.organization_id and t.factura_id = f.ref_fact
  where t.organization_id = canonical.organization_id
    and t.customer_id = canonical.id;
  if (after_count, after_checksum) is distinct from
     (invoice_count, invoice_checksum) then
    raise exception 'GETY consolidation modified invoices';
  end if;
  select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, '|'
      order by r.id), '')) into after_count, after_checksum
  from public.reportes_ventas r
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.ref_fact and t.customer_id = canonical.id);
  if (after_count, after_checksum) is distinct from
     (report_count, report_checksum) then
    raise exception 'GETY consolidation modified report rows or payments';
  end if;
  select count(*), md5(coalesce(string_agg(to_jsonb(r)::text, '|'
      order by r.id), '')) into after_count, after_checksum
  from public.payment_reminders r
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.factura_id and t.customer_id = canonical.id);
  if (after_count, after_checksum) is distinct from
     (reminder_count, reminder_checksum) then
    raise exception 'GETY consolidation modified reminders';
  end if;
  select count(*), md5(coalesce(string_agg(to_jsonb(f)::text, '|'
      order by f.id), '')) into after_count, after_checksum
  from public.payment_followups f
  join public.payment_reminders r on r.id = f.reminder_id
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.factura_id and t.customer_id = canonical.id);
  if (after_count, after_checksum) is distinct from
     (followup_count, followup_checksum) then
    raise exception 'GETY consolidation modified reminder follow-ups';
  end if;
  select count(*), md5(coalesce(string_agg(to_jsonb(e)::text, '|'
      order by e.id), '')) into after_count, after_checksum
  from public.payment_notification_events e
  join public.payment_reminders r on r.id = e.reminder_id
  where r.organization_id = canonical.organization_id
    and exists (select 1 from public.invoice_payment_terms t
      where t.organization_id = r.organization_id
        and t.factura_id = r.factura_id and t.customer_id = canonical.id);
  if (after_count, after_checksum) is distinct from
     (event_count, event_checksum) then
    raise exception 'GETY consolidation modified notification events';
  end if;

  delete from public.billing_customers
  where id = duplicate.id and organization_id = canonical.organization_id;
  if not found then
    raise exception 'GETY consolidation aborted: duplicate was not deleted';
  end if;
  if (select count(*) from public.invoice_payment_terms
      where organization_id = canonical.organization_id
        and customer_id = canonical.id) <> relation_count then
    raise exception 'GETY consolidation postcondition failed';
  end if;
end $$;

create unique index if not exists billing_customers_org_buyer_identity_key
  on public.billing_customers(
    organization_id, buyer_identification_normalized)
  where buyer_identification_normalized is not null;
create unique index if not exists billing_customers_org_legacy_match_key
  on public.billing_customers(
    organization_id,
    public.normalize_customer_match_identity(name),
    public.normalize_customer_match_identity(commercial_name))
  where buyer_identification_normalized is null;

create or replace function public.resolve_enterprise_import_customer(
  p_organization_id uuid, p_identification text, p_name text,
  p_commercial_name text
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
      select array_agg(x.customer_id order by x.customer_id)
      into candidate_ids
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
    if coalesce(array_length(candidate_ids, 1), 0) = 0 then
      select array_agg(c.id order by c.id) into candidate_ids
      from public.billing_customers c
      where c.organization_id = p_organization_id
        and c.buyer_identification_normalized is null
        and public.normalize_customer_match_identity(c.name) =
            public.normalize_customer_match_identity(p_name)
        and public.normalize_customer_match_identity(c.commercial_name) =
            public.normalize_customer_match_identity(p_commercial_name);
    end if;
  else
    select array_agg(c.id order by c.id) into candidate_ids
    from public.billing_customers c
    where c.organization_id = p_organization_id
      and public.normalize_customer_match_identity(c.name) =
          public.normalize_customer_match_identity(p_name)
      and public.normalize_customer_match_identity(c.commercial_name) =
          public.normalize_customer_match_identity(p_commercial_name);
  end if;

  if coalesce(array_length(candidate_ids, 1), 0) > 1 then
    return jsonb_build_object('status', 'ambiguous', 'message',
      'Hay varios perfiles compatibles; resuelve la identidad del cliente antes de importar.');
  end if;
  if coalesce(array_length(candidate_ids, 1), 0) = 0 then
    return jsonb_build_object('status', 'new');
  end if;
  resolved_id := candidate_ids[1];
  select c.payment_term_days into term_days from public.billing_customers c
  where c.organization_id = p_organization_id and c.id = resolved_id;
  return jsonb_build_object(
    'status', case when term_days is null then 'existing_without_term'
                   else 'existing_with_term' end,
    'customer_id', resolved_id, 'payment_term_days', term_days);
end $$;
revoke all on function public.resolve_enterprise_import_customer(
  uuid, text, text, text) from public, anon, authenticated;

create or replace function public.enterprise_upsert_invoice(
  p_request_id uuid, p_ref_fact text, p_cliente text,
  p_nombre_comercial text, p_fecha date, p_nro_fact text, p_venta numeric,
  p_identificacion_comprador text, p_tipo_identificacion_comprador text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  customer_id uuid;
  result jsonb;
  resolution jsonb;
  buyer_id text := public.normalize_buyer_identification(
    p_identificacion_comprador);
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
        when (p_fecha > coalesce(c.profile_invoice_date, '-infinity'::date)
          or (p_fecha = c.profile_invoice_date
              and trim(p_ref_fact) >= coalesce(c.profile_invoice_ref, '')))
          and not (trim(c.name) ~* '^N[0-9]+\s+'
                   and trim(p_cliente) !~* '^N[0-9]+\s+')
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

do $$
begin
  if exists (select 1 from public.billing_customers c
    group by c.organization_id, c.buyer_identification_normalized
    having c.buyer_identification_normalized is not null and count(*) > 1)
  then raise exception 'duplicate normalized buyer identity remains'; end if;
  if exists (select 1 from public.billing_customers c
    where c.buyer_identification_normalized is null
    group by c.organization_id,
      public.normalize_customer_match_identity(c.name),
      public.normalize_customer_match_identity(c.commercial_name)
    having count(*) > 1)
  then raise exception 'duplicate legacy customer identity remains'; end if;
end $$;

notify pgrst, 'reload schema';
commit;
