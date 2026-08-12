begin;

-- A legacy payment without a receipt remains valid when its persisted value is
-- still present. Match occurrences by value instead of array position so that
-- inserting or deleting another payment cannot turn an unchanged legacy item
-- into a "modified" payment.
create or replace function public.enterprise_save_report_row(
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
  unmatched_legacy_payments numeric[];
  payment_count integer;
  matching_legacy_index integer;
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
    select coalesce(array_agg(
      case when value='null'::jsonb then null else (value #>> '{}')::bigint end
      order by ordinal), '{}'::bigint[])
      into receipts
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

  if existing_payments is not null then
    select coalesce(array_agg((payment.value #>> '{}')::numeric order by payment.ordinal), '{}')
      into unmatched_legacy_payments
    from jsonb_array_elements(existing_payments)
         with ordinality payment(value,ordinal)
    where existing_receipts[payment.ordinal] is null;
  else
    unmatched_legacy_payments := '{}';
  end if;

  if payment_count>0 then
    for i in 0..payment_count-1 loop
      if jsonb_typeof(p_payments->i)<>'number'
         or (p_payments->>i)::numeric<=0 then
        raise exception 'invalid payment value';
      end if;
      if receipts[i+1] is null then
        select legacy_index into matching_legacy_index
        from generate_subscripts(unmatched_legacy_payments,1) legacy_index
        where unmatched_legacy_payments[legacy_index]=(p_payments->>i)::numeric
        order by legacy_index limit 1;
        if matching_legacy_index is null then
          raise exception 'receipt number is required for new or modified payments';
        end if;
        unmatched_legacy_payments[matching_legacy_index]:=null;
        matching_legacy_index:=null;
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

notify pgrst, 'reload schema';

commit;
