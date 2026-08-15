begin;

-- Automatic scheduling is deliberately create-only. Existing reminders are
-- commitments: edits, retries and later customer-term changes must not move them.
create or replace function public.sync_enterprise_reminder(
  p_organization_id uuid, p_factura_id text, p_request_id uuid, p_reason text
) returns date language plpgsql security definer set search_path = '' as $$
declare
  terms public.invoice_payment_terms%rowtype;
  customer public.billing_customers%rowtype;
  invoice_date date;
  days integer;
  effective date;
  source text;
  is_cancelled boolean;
  paid numeric;
  monthly_row_count integer;
begin
  if p_organization_id is distinct from public.require_current_organization_id() then
    raise exception 'organization mismatch';
  end if;

  -- Serialize with term edits and competing invoice retries.
  select * into terms from public.invoice_payment_terms
    where organization_id=p_organization_id and factura_id=p_factura_id for update;
  if not found or not terms.active then return null; end if;

  -- Never overwrite, reactivate or otherwise mutate an established schedule.
  if exists(select 1 from public.payment_reminders
            where organization_id=p_organization_id and factura_id=p_factura_id) then
    return (select payment_date from public.payment_reminders
            where organization_id=p_organization_id and factura_id=p_factura_id);
  end if;

  select f.fecha into invoice_date from public.facturas_maestras f
    where f.ref_fact=p_factura_id and f.organization_id=p_organization_id;
  if not found then raise exception 'enterprise invoice not found'; end if;

  -- A persisted monthly row is the canonical proof that invoice creation finished.
  select
    count(*)::integer,
    bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA'),
    coalesce(sum((select coalesce(sum(value::numeric),0)
                  from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0)
    into monthly_row_count,is_cancelled,paid
  from public.reportes_ventas rv
  where rv.organization_id=p_organization_id and rv.ref_fact=p_factura_id;
  if monthly_row_count=0 or coalesce(is_cancelled,false) or
     (select f.venta from public.facturas_maestras f
       where f.organization_id=p_organization_id and f.ref_fact=p_factura_id)
       - coalesce(paid,0) <= 0.005 then
    return null;
  end if;

  select * into customer from public.billing_customers
    where id=terms.customer_id and organization_id=p_organization_id;
  if not found then raise exception 'enterprise customer not found'; end if;
  days:=coalesce(terms.exceptional_term_days,customer.payment_term_days);
  if days is null then return null; end if;

  effective:=public.calculate_enterprise_payment_date(invoice_date,days);
  source:=case when terms.exceptional_term_days is null
               then 'customer_term' else 'invoice_exception' end;
  insert into public.payment_reminders(
    organization_id,user_id,factura_id,payment_date,active,
    notify_three_days,notify_one_day,date_source,calculated_term_days
  ) values(
    p_organization_id,auth.uid(),p_factura_id,effective,true,
    true,true,source,days
  ) on conflict (organization_id,factura_id) where organization_id is not null
    do nothing;

  return (select payment_date from public.payment_reminders
          where organization_id=p_organization_id and factura_id=p_factura_id);
end;
$$;

create or replace function public.preview_enterprise_customer_term(
  p_customer_id uuid,p_days integer
) returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer
  from public.invoice_payment_terms t
  join public.facturas_maestras f
    on f.ref_fact=t.factura_id and f.organization_id=t.organization_id
  where t.organization_id=public.require_current_organization_id()
    and t.customer_id=p_customer_id and t.active
    and t.exceptional_term_days is null and p_days>=0
    and not exists(select 1 from public.payment_reminders r
                   where r.organization_id=t.organization_id and r.factura_id=t.factura_id)
    and exists(
      select 1 from public.reportes_ventas rv
      where rv.organization_id=t.organization_id and rv.ref_fact=t.factura_id
      group by rv.organization_id,rv.ref_fact
      having not bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA')
        and f.venta-coalesce(sum((select coalesce(sum(value::numeric),0)
              from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0)>0.005
    );
$$;

create or replace function public.save_enterprise_customer_term(
  p_request_id uuid,p_customer_id uuid,p_days integer,p_apply boolean
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  org uuid:=public.require_current_organization_id();
  item record;
  affected integer:=0;
  scheduled date;
begin
  if p_days is null or p_days<0 then raise exception 'invalid payment term'; end if;
  if exists(select 1 from public.enterprise_requests
            where organization_id=org and request_id=p_request_id) then
    return coalesce((select (result->>'affected')::integer
      from public.enterprise_requests where organization_id=org and request_id=p_request_id),0);
  end if;
  update public.billing_customers set payment_term_days=p_days,
    updated_at=clock_timestamp(),updated_by=auth.uid()
    where id=p_customer_id and organization_id=org;
  if not found then raise exception 'enterprise customer not found'; end if;
  if p_apply then
    for item in
      select t.factura_id from public.invoice_payment_terms t
      where t.organization_id=org and t.customer_id=p_customer_id and t.active
        and t.exceptional_term_days is null
        and not exists(select 1 from public.payment_reminders r
          where r.organization_id=org and r.factura_id=t.factura_id)
    loop
      scheduled:=public.sync_enterprise_reminder(org,item.factura_id,p_request_id,
        'automatic customer payment term');
      if scheduled is not null then affected:=affected+1; end if;
    end loop;
  end if;
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'save_customer_term',jsonb_build_object('affected',affected));
  return affected;
end;
$$;

-- Recreate the current 14-argument row RPC, moving scheduling after the monthly
-- row insert. The entire operation remains one database transaction.
create or replace function public.enterprise_save_report_row(
  p_request_id uuid,p_row_number integer,p_report_name text,p_ref_fact text,
  p_cliente text,p_commercial_name text,p_invoice_date date,p_sale numeric,
  p_seller text,p_nail_polish numeric,p_payments jsonb,
  p_payment_receipts jsonb,p_payment_comments jsonb,p_invoice_number text
) returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); customer_id uuid;
declare receipts bigint[]; payment_count integer; i integer;
begin
  if p_row_number<1 or nullif(trim(p_report_name),'') is null then raise exception 'invalid report row'; end if;
  if p_payments is null or p_payment_receipts is null or p_payment_comments is null
     or jsonb_typeof(p_payments)<>'array' or jsonb_typeof(p_payment_receipts)<>'array'
     or jsonb_typeof(p_payment_comments)<>'array' then raise exception 'payment data must be arrays'; end if;
  payment_count:=jsonb_array_length(p_payments);
  if jsonb_array_length(p_payment_receipts)<>payment_count
     or jsonb_array_length(p_payment_comments)<>payment_count then raise exception 'payment arrays must be aligned'; end if;
  begin
    select coalesce(array_agg(case when value='null'::jsonb then null else (value#>>'{}')::bigint end order by ordinal),'{}'::bigint[])
      into receipts from jsonb_array_elements(p_payment_receipts) with ordinality item(value,ordinal);
  exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'invalid receipt number'; end;
  if not public.valid_receipt_numbers(receipts) then raise exception 'receipt numbers must be positive safe integers'; end if;
  if payment_count>0 then for i in 0..payment_count-1 loop
    if jsonb_typeof(p_payments->i)<>'number' or (p_payments->>i)::numeric<=0 then raise exception 'invalid payment value'; end if;
  end loop; end if;
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  if nullif(trim(p_ref_fact),'') is not null then
    if exists(select 1 from public.facturas_maestras where ref_fact=trim(p_ref_fact) and organization_id is distinct from org)
      then raise exception 'invoice belongs to another organization'; end if;
    insert into public.facturas_maestras(organization_id,ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta)
    values(org,trim(p_ref_fact),trim(p_cliente),trim(coalesce(p_commercial_name,'')),p_invoice_date,
      coalesce(nullif(trim(p_invoice_number),''),trim(p_ref_fact)),p_sale)
    on conflict(ref_fact) do update set cliente=excluded.cliente,nombre_comercial=excluded.nombre_comercial,
      fecha=excluded.fecha,nro_fact=excluded.nro_fact,venta=excluded.venta where public.facturas_maestras.organization_id=org;
    insert into public.billing_customers(organization_id,name,commercial_name,updated_by)
    values(org,trim(p_cliente),trim(coalesce(p_commercial_name,'')),auth.uid())
    on conflict(organization_id,normalized_name,normalized_commercial_name)
    do update set name=excluded.name,commercial_name=excluded.commercial_name,
      updated_at=clock_timestamp(),updated_by=auth.uid() returning id into customer_id;
    insert into public.invoice_payment_terms(organization_id,factura_id,customer_id,active,updated_by)
    values(org,trim(p_ref_fact),customer_id,true,auth.uid())
    on conflict(organization_id,factura_id) do update set customer_id=excluded.customer_id,
      updated_at=clock_timestamp(),updated_by=auth.uid();
  end if;
  if exists(select 1 from public.reportes_ventas where nro_fila=p_row_number and mes_reporte=p_report_name
            and organization_id is distinct from org) then raise exception 'report row belongs to another organization'; end if;
  insert into public.reportes_ventas(organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,numeros_recibo,comentarios_abonos,mes_reporte)
  values(org,p_row_number,trim(p_ref_fact),p_seller,p_nail_polish,p_payments,receipts,p_payment_comments,p_report_name)
  on conflict(nro_fila,mes_reporte) do update set ref_fact=excluded.ref_fact,vendedor=excluded.vendedor,
    esmaltes=excluded.esmaltes,abonos=excluded.abonos,numeros_recibo=excluded.numeros_recibo,
    comentarios_abonos=excluded.comentarios_abonos where public.reportes_ventas.organization_id=org;
  if nullif(trim(p_ref_fact),'') is not null then
    perform public.sync_enterprise_reminder(org,trim(p_ref_fact),p_request_id,'automatic invoice creation');
  end if;
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'save_report_row','{}');
end; $$;

revoke all on function public.sync_enterprise_reminder(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.preview_enterprise_customer_term(uuid,integer) from public,anon;
revoke all on function public.save_enterprise_customer_term(uuid,uuid,integer,boolean) from public,anon;
revoke all on function public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text) from public,anon;
grant execute on function public.preview_enterprise_customer_term(uuid,integer) to authenticated;
grant execute on function public.save_enterprise_customer_term(uuid,uuid,integer,boolean) to authenticated;
grant execute on function public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text) to authenticated;

notify pgrst, 'reload schema';
commit;
