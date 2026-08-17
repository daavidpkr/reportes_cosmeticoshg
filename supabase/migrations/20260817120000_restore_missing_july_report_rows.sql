begin;

-- Read-only, tenant-scoped detector for invoices whose calendar month has no
-- matching monthly report row. It deliberately never repairs data.
create or replace function public.enterprise_find_missing_report_rows(
  p_year integer, p_month integer
) returns table(ref_fact text, fecha date, venta numeric, expected_report text)
language plpgsql stable security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  report_name text;
begin
  if p_year < 2000 or p_month not between 1 and 12 then
    raise exception 'invalid report period';
  end if;
  report_name := (array['Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[p_month]
    || ' ' || p_year::text;
  return query
    select f.ref_fact, f.fecha, f.venta, report_name
    from public.facturas_maestras f
    where f.organization_id = org
      and f.fecha >= make_date(p_year,p_month,1)
      and f.fecha < (make_date(p_year,p_month,1) + interval '1 month')::date
      and not exists (
        select 1 from public.reportes_ventas rv
        where rv.organization_id = org and rv.ref_fact = f.ref_fact
          and rv.mes_reporte = report_name
      )
    order by f.fecha, f.ref_fact;
end;
$$;

revoke all on function public.enterprise_find_missing_report_rows(integer,integer)
  from public, anon;
grant execute on function public.enterprise_find_missing_report_rows(integer,integer)
  to authenticated;

-- Atomic batch import. A retry completes a missing monthly association even
-- when the master invoice already exists. Organization always comes from auth.
create or replace function public.enterprise_import_monthly_invoices(
  p_request_id uuid, p_year integer, p_month integer, p_invoices jsonb
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  report_id text;
  report_name text;
  item jsonb;
  invoice_ref text;
  invoice_date date;
  next_row integer;
  inserted_rows integer := 0;
  customer_id uuid;
begin
  if p_year < 2000 or p_month not between 1 and 12
     or p_invoices is null or jsonb_typeof(p_invoices) <> 'array' then
    raise exception 'invalid monthly invoice batch';
  end if;
  if exists(select 1 from public.enterprise_requests
            where organization_id=org and request_id=p_request_id) then
    return coalesce((select (result->>'inserted_rows')::integer
      from public.enterprise_requests
      where organization_id=org and request_id=p_request_id),0);
  end if;
  report_id := p_year::text || '-' || lpad(p_month::text,2,'0');
  report_name := (array['Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[p_month]
    || ' ' || p_year::text;
  perform 1 from public.reportes_mensuales
    where id=report_id and organization_id=org for update;
  if not found then raise exception 'monthly report not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(org::text || ':' || report_name,0));
  select coalesce(max(nro_fila),0) into next_row
    from public.reportes_ventas
    where organization_id=org and mes_reporte=report_name;

  for item in select value from jsonb_array_elements(p_invoices)
  loop
    invoice_ref := trim(coalesce(item->>'ref_fact',''));
    begin invoice_date := (item->>'fecha')::date;
    exception when others then raise exception 'invalid invoice date for %',invoice_ref; end;
    if invoice_ref = '' or invoice_ref !~ '^[0-9]+$'
       or invoice_ref <> coalesce(item->>'nro_fact','')
       or invoice_date < make_date(p_year,p_month,1)
       or invoice_date >= (make_date(p_year,p_month,1)+interval '1 month')::date
       or coalesce((item->>'venta')::numeric,-1) < 0 then
      raise exception 'invalid invoice % for selected report',invoice_ref;
    end if;
    if exists(select 1 from public.facturas_maestras
      where ref_fact=invoice_ref and organization_id is distinct from org) then
      raise exception 'invoice belongs to another organization';
    end if;
    insert into public.facturas_maestras(
      organization_id,ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta)
    values(org,invoice_ref,trim(coalesce(item->>'cliente','')),
      trim(coalesce(item->>'nombre_comercial','')),invoice_date,invoice_ref,
      (item->>'venta')::numeric)
    on conflict(ref_fact) do update set
      cliente=excluded.cliente,nombre_comercial=excluded.nombre_comercial,
      fecha=excluded.fecha,nro_fact=excluded.nro_fact,venta=excluded.venta
    where public.facturas_maestras.organization_id=org;

    insert into public.billing_customers(
      organization_id,name,commercial_name,updated_by)
    values(org,trim(coalesce(item->>'cliente','')),
      trim(coalesce(item->>'nombre_comercial','')),auth.uid())
    on conflict(organization_id,normalized_name,normalized_commercial_name)
    do update set name=excluded.name,commercial_name=excluded.commercial_name,
      updated_at=clock_timestamp(),updated_by=auth.uid()
    returning id into customer_id;
    insert into public.invoice_payment_terms(
      organization_id,factura_id,customer_id,active,updated_by)
    values(org,invoice_ref,customer_id,true,auth.uid())
    on conflict(organization_id,factura_id) do update set
      customer_id=excluded.customer_id,updated_at=clock_timestamp(),updated_by=auth.uid();

    if not exists(select 1 from public.reportes_ventas
      where organization_id=org and ref_fact=invoice_ref
        and mes_reporte=report_name) then
      next_row := next_row + 1;
      insert into public.reportes_ventas(
        organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,
        numeros_recibo,comentarios_abonos,mes_reporte)
      values(org,next_row,invoice_ref,'',0,'[]'::jsonb,'{}'::bigint[],
        '[]'::jsonb,report_name);
      inserted_rows := inserted_rows + 1;
    end if;
  end loop;
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'import_monthly_invoices',
      jsonb_build_object('inserted_rows',inserted_rows));
  return inserted_rows;
end;
$$;

revoke all on function public.enterprise_import_monthly_invoices(uuid,integer,integer,jsonb)
  from public, anon;
grant execute on function public.enterprise_import_monthly_invoices(uuid,integer,integer,jsonb)
  to authenticated;

-- One-time, defensive repair. The neighboring rows establish tenant, canonical
-- month and insertion point. Unknown seller data is intentionally left empty.
do $$
declare
  target_org uuid;
  canonical_month text;
  anchor_row integer;
  following_row integer;
  missing_count integer;
  already_count integer;
  moved_count integer;
  inserted_count integer;
  ref text;
begin
  select f.organization_id into target_org
  from public.facturas_maestras f where f.ref_fact='000000655';
  if target_org is null then raise exception 'repair precondition: 655 master missing'; end if;
  if (select count(*) from public.facturas_maestras f
      where f.organization_id=target_org and f.ref_fact between '000000655' and '000000666') <> 12 then
    raise exception 'repair precondition: expected 12 master invoices';
  end if;
  if exists(select 1 from public.facturas_maestras f
    where f.organization_id=target_org and f.ref_fact between '000000655' and '000000666'
      and (f.nro_fact<>f.ref_fact or f.fecha<'2026-07-01' or f.fecha>='2026-08-01')) then
    raise exception 'repair precondition: noncanonical reference or date';
  end if;
  select r.mes_reporte,r.nro_fila into canonical_month,anchor_row
    from public.reportes_ventas r
    where r.organization_id=target_org and r.ref_fact='000000655' for update;
  select r.nro_fila into following_row from public.reportes_ventas r
    where r.organization_id=target_org and r.ref_fact='000000666'
      and r.mes_reporte=canonical_month for update;
  if canonical_month is distinct from 'Julio 2026' or anchor_row is null
     or following_row is distinct from anchor_row+1 then
    raise exception 'repair precondition: unexpected canonical month or anchors';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_org::text||':'||canonical_month,0));
  select count(*) into already_count from public.reportes_ventas r
    where r.organization_id=target_org and r.ref_fact between '000000656' and '000000665';
  select count(*) into missing_count from public.facturas_maestras f
    where f.organization_id=target_org and f.ref_fact between '000000656' and '000000665'
      and not exists(select 1 from public.reportes_ventas r
        where r.organization_id=target_org and r.ref_fact=f.ref_fact);
  if already_count=10 and missing_count=0 then return; end if;
  if already_count<>0 or missing_count<>10 then
    raise exception 'repair precondition: range is partially associated';
  end if;
  if exists(select 1 from public.reportes_ventas r
    where r.organization_id=target_org
      and regexp_replace(r.ref_fact,'^0+','') in
        (select generate_series(656,665)::text)) then
    raise exception 'repair precondition: alternate reference exists';
  end if;

  -- Two-phase offset prevents transient collisions with the unique visual key.
  update public.reportes_ventas set nro_fila=nro_fila+100000
    where organization_id=target_org and mes_reporte=canonical_month
      and nro_fila>anchor_row;
  get diagnostics moved_count=row_count;
  update public.reportes_ventas set nro_fila=nro_fila-99990
    where organization_id=target_org and mes_reporte=canonical_month
      and nro_fila>100000+anchor_row;

  for ref in select lpad(g::text,9,'0') from generate_series(656,665) g loop
    insert into public.reportes_ventas(
      organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,
      numeros_recibo,comentarios_abonos,mes_reporte)
    values(target_org,anchor_row+(ref::integer-655),ref,'',0,'[]'::jsonb,
      '{}'::bigint[],'[]'::jsonb,canonical_month);
  end loop;
  get diagnostics inserted_count=row_count;
  if (select count(*) from public.reportes_ventas r
      where r.organization_id=target_org and r.ref_fact between '000000655' and '000000666')<>12
     or exists(select 1 from public.reportes_ventas r where r.organization_id=target_org
       and r.mes_reporte=canonical_month group by r.nro_fila having count(*)>1) then
    raise exception 'repair postcondition failed';
  end if;
  raise notice 'July repair: inserted %, shifted %, canonical month %',10,moved_count,canonical_month;
end;
$$;

notify pgrst, 'reload schema';
commit;
