begin;

-- Create the exact signature used by Flutter before removing the obsolete one.
-- ref_fact is the internal invoice reference; nro_fact stores the full number.
create function public.enterprise_save_report_row(
  p_request_id uuid,p_row_number integer,p_report_name text,p_ref_fact text,
  p_cliente text,p_commercial_name text,p_invoice_date date,p_sale numeric,
  p_seller text,p_nail_polish numeric,p_payments jsonb,
  p_payment_receipts jsonb,p_payment_comments jsonb,p_invoice_number text
) returns void language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id();
  customer_id uuid;
  receipts bigint[];
  existing_payments jsonb;
  existing_receipts bigint[];
  payment_count integer;
  i integer;
begin
  if p_row_number<1 or nullif(trim(p_report_name),'') is null then
    raise exception 'invalid report row';
  end if;
  if p_payments is null or p_payment_receipts is null or p_payment_comments is null
     or jsonb_typeof(p_payments)<>'array'
     or jsonb_typeof(p_payment_receipts)<>'array'
     or jsonb_typeof(p_payment_comments)<>'array' then
    raise exception 'payment data must be arrays';
  end if;
  payment_count:=jsonb_array_length(p_payments);
  if jsonb_array_length(p_payment_receipts)<>payment_count
     or jsonb_array_length(p_payment_comments)<>payment_count then
    raise exception 'payment arrays must be aligned';
  end if;

  begin
    select coalesce(
      array_agg(
        case when value='null'::jsonb then null
             else (value #>> '{}')::bigint end
        order by ordinal
      ),
      '{}'::bigint[]
    ) into receipts
    from jsonb_array_elements(p_payment_receipts)
         with ordinality item(value,ordinal);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'invalid receipt number';
  end;
  if not public.valid_receipt_numbers(receipts) then
    raise exception 'receipt numbers must be positive safe integers';
  end if;

  select abonos,numeros_recibo into existing_payments,existing_receipts
  from public.reportes_ventas
  where nro_fila=p_row_number and mes_reporte=p_report_name
    and organization_id=org
  for update;

  if payment_count>0 then
    for i in 0..payment_count-1 loop
      if jsonb_typeof(p_payments->i)<>'number' then
        raise exception 'invalid payment value';
      end if;
      if (p_payments->>i)::numeric<>0 and receipts[i+1] is null then
        if existing_payments is null
           or i>=jsonb_array_length(existing_payments)
           or existing_receipts[i+1] is not null
           or (existing_payments->>i)::numeric<>(p_payments->>i)::numeric then
          raise exception 'receipt number is required for new or modified payments';
        end if;
      end if;
    end loop;
  end if;

  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  if nullif(trim(p_ref_fact),'') is not null then
    if exists(select 1 from public.facturas_maestras where ref_fact=trim(p_ref_fact) and organization_id is distinct from org) then
      raise exception 'invoice belongs to another organization';
    end if;
    insert into public.facturas_maestras(organization_id,ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta)
    values(org,trim(p_ref_fact),trim(p_cliente),trim(coalesce(p_commercial_name,'')),p_invoice_date,
           coalesce(nullif(trim(p_invoice_number),''),trim(p_ref_fact)),p_sale)
    on conflict(ref_fact) do update set cliente=excluded.cliente,nombre_comercial=excluded.nombre_comercial,
      fecha=excluded.fecha,nro_fact=excluded.nro_fact,venta=excluded.venta
    where public.facturas_maestras.organization_id=org;
    insert into public.billing_customers(organization_id,name,commercial_name,updated_by)
    values(org,trim(p_cliente),trim(coalesce(p_commercial_name,'')),auth.uid())
    on conflict(organization_id,normalized_name,normalized_commercial_name)
    do update set updated_at=clock_timestamp(),updated_by=auth.uid() returning id into customer_id;
    insert into public.invoice_payment_terms(organization_id,factura_id,customer_id,active,updated_by)
    values(org,trim(p_ref_fact),customer_id,true,auth.uid())
    on conflict(organization_id,factura_id) do update set customer_id=excluded.customer_id,
      updated_at=clock_timestamp(),updated_by=auth.uid();
    perform public.sync_enterprise_reminder(org,trim(p_ref_fact),p_request_id,'Reprogramación automática por edición de factura');
  end if;
  if exists(select 1 from public.reportes_ventas where nro_fila=p_row_number and mes_reporte=p_report_name
            and organization_id is distinct from org) then raise exception 'report row belongs to another organization'; end if;
  insert into public.reportes_ventas(organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,numeros_recibo,comentarios_abonos,mes_reporte)
  values(org,p_row_number,trim(p_ref_fact),p_seller,p_nail_polish,p_payments,receipts,p_payment_comments,p_report_name)
  on conflict(nro_fila,mes_reporte) do update set ref_fact=excluded.ref_fact,vendedor=excluded.vendedor,
    esmaltes=excluded.esmaltes,abonos=excluded.abonos,numeros_recibo=excluded.numeros_recibo,
    comentarios_abonos=excluded.comentarios_abonos
  where public.reportes_ventas.organization_id=org;
  insert into public.enterprise_requests values(org,p_request_id,'save_report_row','{}',clock_timestamp());
end; $$;

revoke all on function public.enterprise_save_report_row(
  uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text
) from public,anon;
grant execute on function public.enterprise_save_report_row(
  uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text
) to authenticated;

-- Validate the replacement's signature and security before removing the old RPC.
do $$
declare
  replacement oid := to_regprocedure(
    'public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text)'
  );
  argument_names text[];
  is_security_definer boolean;
  function_config text[];
begin
  if replacement is null then
    raise exception '14-argument enterprise_save_report_row was not created';
  end if;
  select proargnames,prosecdef,proconfig
    into argument_names,is_security_definer,function_config
  from pg_proc where oid=replacement;
  if argument_names is distinct from array[
    'p_request_id','p_row_number','p_report_name','p_ref_fact','p_cliente',
    'p_commercial_name','p_invoice_date','p_sale','p_seller','p_nail_polish',
    'p_payments','p_payment_receipts','p_payment_comments','p_invoice_number'
  ]::text[] then
    raise exception 'unexpected enterprise_save_report_row argument names: %',argument_names;
  end if;
  if not is_security_definer
     or cardinality(function_config) <> 1
     or function_config[1] !~ '^search_path=(""|)$' then
    raise exception 'enterprise_save_report_row security configuration was not preserved: %',function_config;
  end if;
  if not has_function_privilege('authenticated',replacement,'EXECUTE')
     or has_function_privilege('anon',replacement,'EXECUTE') then
    raise exception 'enterprise_save_report_row privileges are incorrect';
  end if;
end $$;

drop function public.enterprise_save_report_row(
  uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb
);

do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='enterprise_save_report_row') <> 1 then
    raise exception 'enterprise_save_report_row must have exactly one signature';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
