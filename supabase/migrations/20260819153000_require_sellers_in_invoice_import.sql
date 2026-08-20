-- Extend the existing atomic importer with a mandatory catalog seller.
create or replace function public.enterprise_import_monthly_invoices(
  p_request_id uuid, p_year integer, p_month integer, p_invoices jsonb
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  report_id text; report_name text; item jsonb; invoice_ref text;
  invoice_date date; next_row integer; inserted_rows integer := 0;
  customer_id uuid; seller_label text;
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
  select coalesce(max(nro_fila),0) into next_row from public.reportes_ventas
    where organization_id=org and mes_reporte=report_name;

  for item in select value from jsonb_array_elements(p_invoices) loop
    invoice_ref := trim(coalesce(item->>'ref_fact',''));
    seller_label := trim(coalesce(item->>'vendedor',''));
    begin invoice_date := (item->>'fecha')::date;
    exception when others then raise exception 'invalid invoice date for %',invoice_ref; end;
    if invoice_ref = '' or invoice_ref !~ '^[0-9]+$'
       or invoice_ref <> coalesce(item->>'nro_fact','')
       or invoice_date < make_date(p_year,p_month,1)
       or invoice_date >= (make_date(p_year,p_month,1)+interval '1 month')::date
       or coalesce((item->>'venta')::numeric,-1) < 0 then
      raise exception 'invalid invoice % for selected report',invoice_ref;
    end if;
    if seller_label = '' or not exists(
      select 1 from public.vendedores v where v.organization_id=org
        and seller_label = case when trim(v.codigo)='' then trim(v.nombre)
          else trim(v.codigo) || ' - ' || trim(v.nombre) end
    ) then raise exception 'invalid seller for invoice %',invoice_ref; end if;
    if exists(select 1 from public.facturas_maestras where ref_fact=invoice_ref) then
      raise exception 'invoice % already exists',invoice_ref;
    end if;

    insert into public.facturas_maestras(
      organization_id,ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta)
    values(org,invoice_ref,trim(coalesce(item->>'cliente','')),
      trim(coalesce(item->>'nombre_comercial','')),invoice_date,invoice_ref,
      (item->>'venta')::numeric);
    insert into public.billing_customers(organization_id,name,commercial_name,updated_by)
    values(org,trim(coalesce(item->>'cliente','')),
      trim(coalesce(item->>'nombre_comercial','')),auth.uid())
    on conflict(organization_id,normalized_name,normalized_commercial_name)
    do update set name=excluded.name,commercial_name=excluded.commercial_name,
      updated_at=clock_timestamp(),updated_by=auth.uid() returning id into customer_id;
    insert into public.invoice_payment_terms(
      organization_id,factura_id,customer_id,active,updated_by)
    values(org,invoice_ref,customer_id,true,auth.uid());
    next_row := next_row + 1;
    insert into public.reportes_ventas(
      organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,
      numeros_recibo,comentarios_abonos,mes_reporte)
    values(org,next_row,invoice_ref,seller_label,0,'[]'::jsonb,'{}'::bigint[],
      '[]'::jsonb,report_name);
    inserted_rows := inserted_rows + 1;
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
