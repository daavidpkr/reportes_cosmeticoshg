-- Buyer identity is internal. Existing profiles contain no proven buyer ID, so
-- this migration never merges, labels, or deletes historical customers.
begin;

create or replace function public.normalize_buyer_identification(value text)
returns text language sql immutable set search_path='' as $$
  select nullif(upper(regexp_replace(trim(coalesce(value,'')), '[^[:alnum:]]', '', 'g')), '');
$$;

alter table public.facturas_maestras
  add column if not exists identificacion_comprador text,
  add column if not exists tipo_identificacion_comprador text;
alter table public.billing_customers
  add column if not exists buyer_identification text,
  add column if not exists buyer_identification_normalized text,
  add column if not exists buyer_identification_type text,
  add column if not exists profile_invoice_date date,
  add column if not exists profile_invoice_ref text;
create index if not exists facturas_maestras_buyer_identity_idx
  on public.facturas_maestras(organization_id,identificacion_comprador);
create unique index if not exists billing_customers_org_buyer_identity_key
  on public.billing_customers(organization_id,buyer_identification_normalized)
  where buyer_identification_normalized is not null;

-- Do not leave an overload through which a stale client can bypass buyer ID.
drop function if exists public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric);
create function public.enterprise_upsert_invoice(
  p_request_id uuid,p_ref_fact text,p_cliente text,p_nombre_comercial text,
  p_fecha date,p_nro_fact text,p_venta numeric,p_identificacion_comprador text,
  p_tipo_identificacion_comprador text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id(); customer_id uuid; result jsonb;
  buyer_id text:=public.normalize_buyer_identification(p_identificacion_comprador); legacy_ids uuid[];
begin
  if nullif(trim(p_ref_fact),'') is null or nullif(trim(p_cliente),'') is null or p_fecha is null then raise exception 'invalid invoice'; end if;
  select r.result into result from public.enterprise_requests r where r.organization_id=org and r.request_id=p_request_id and r.action='upsert_invoice';
  if found then return result; end if;
  insert into public.facturas_maestras(organization_id,ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta,identificacion_comprador,tipo_identificacion_comprador)
  values(org,trim(p_ref_fact),trim(p_cliente),trim(coalesce(p_nombre_comercial,'')),p_fecha,trim(p_nro_fact),p_venta,buyer_id,nullif(trim(coalesce(p_tipo_identificacion_comprador,'')),''))
  on conflict(ref_fact) do update set cliente=excluded.cliente,nombre_comercial=excluded.nombre_comercial,fecha=excluded.fecha,nro_fact=excluded.nro_fact,venta=excluded.venta,identificacion_comprador=coalesce(excluded.identificacion_comprador,public.facturas_maestras.identificacion_comprador),tipo_identificacion_comprador=coalesce(excluded.tipo_identificacion_comprador,public.facturas_maestras.tipo_identificacion_comprador) where public.facturas_maestras.organization_id=org;
  if buyer_id is not null then
    select c.id into customer_id from public.billing_customers c where c.organization_id=org and c.buyer_identification_normalized=buyer_id for update;
    if not found then
      -- Claim legacy data only for exactly one exact name+commercial match.
      -- Similar rows are intentionally left separate (e.g. GETY variants).
      select array_agg(c.id order by c.id) into legacy_ids from public.billing_customers c where c.organization_id=org and c.buyer_identification_normalized is null and c.normalized_name=public.normalize_customer_identity(p_cliente) and c.normalized_commercial_name=public.normalize_customer_identity(coalesce(p_nombre_comercial,''));
      if coalesce(array_length(legacy_ids,1),0)=1 then
        customer_id:=legacy_ids[1];
        update public.billing_customers c set buyer_identification=buyer_id,buyer_identification_normalized=buyer_id,buyer_identification_type=nullif(trim(coalesce(p_tipo_identificacion_comprador,'')),''),profile_invoice_date=p_fecha,profile_invoice_ref=trim(p_ref_fact),updated_at=clock_timestamp(),updated_by=auth.uid() where c.id=customer_id;
      else
        insert into public.billing_customers(organization_id,name,commercial_name,buyer_identification,buyer_identification_normalized,buyer_identification_type,profile_invoice_date,profile_invoice_ref,updated_by) values(org,trim(p_cliente),trim(coalesce(p_nombre_comercial,'')),buyer_id,buyer_id,nullif(trim(coalesce(p_tipo_identificacion_comprador,'')),''),p_fecha,trim(p_ref_fact),auth.uid()) returning id into customer_id;
      end if;
    end if;
    update public.billing_customers c set
      name=case when p_fecha>coalesce(c.profile_invoice_date,'-infinity'::date) or (p_fecha=c.profile_invoice_date and trim(p_ref_fact)>=coalesce(c.profile_invoice_ref,'')) then trim(p_cliente) else c.name end,
      commercial_name=case when (p_fecha>coalesce(c.profile_invoice_date,'-infinity'::date) or (p_fecha=c.profile_invoice_date and trim(p_ref_fact)>=coalesce(c.profile_invoice_ref,''))) and trim(coalesce(p_nombre_comercial,''))<>'' then trim(p_nombre_comercial) else c.commercial_name end,
      buyer_identification_type=coalesce(nullif(trim(coalesce(p_tipo_identificacion_comprador,'')),''),c.buyer_identification_type),
      profile_invoice_date=case when p_fecha>=coalesce(c.profile_invoice_date,'-infinity'::date) then p_fecha else c.profile_invoice_date end,
      profile_invoice_ref=case when p_fecha>=coalesce(c.profile_invoice_date,'-infinity'::date) then trim(p_ref_fact) else c.profile_invoice_ref end,updated_at=clock_timestamp(),updated_by=auth.uid() where c.id=customer_id;
  else
    insert into public.billing_customers(organization_id,name,commercial_name,profile_invoice_date,profile_invoice_ref,updated_by) values(org,trim(p_cliente),trim(coalesce(p_nombre_comercial,'')),p_fecha,trim(p_ref_fact),auth.uid()) on conflict(organization_id,normalized_name,normalized_commercial_name) do update set updated_at=clock_timestamp(),updated_by=auth.uid() returning id into customer_id;
  end if;
  insert into public.invoice_payment_terms(organization_id,factura_id,customer_id,active,updated_by) values(org,trim(p_ref_fact),customer_id,true,auth.uid()) on conflict(organization_id,factura_id) do update set customer_id=excluded.customer_id,updated_at=clock_timestamp(),updated_by=auth.uid();
  perform public.sync_enterprise_reminder(org,trim(p_ref_fact),p_request_id,'Automatic reschedule from invoice data');
  result:=jsonb_build_object('factura_id',trim(p_ref_fact),'customer_id',customer_id);
  insert into public.enterprise_requests(organization_id,request_id,action,result) values(org,p_request_id,'upsert_invoice',result); return result;
end $$;
revoke all on function public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric,text,text) from public,anon;
grant execute on function public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric,text,text) to authenticated;

-- Final canonical importer. It retains the per-invoice term behavior added by
-- 20260903120000 while also carrying seller and buyer identity.
create or replace function public.enterprise_import_monthly_invoices(p_request_id uuid,p_year integer,p_month integer,p_invoices jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); item jsonb; invoice_ref text; invoice_date date; seller_label text; report_name text; next_row integer; inserted_rows integer:=0; customer_id uuid; proposed_days integer; upsert_result jsonb;
begin
  if p_year<2000 or p_month not between 1 and 12 or p_invoices is null or jsonb_typeof(p_invoices)<>'array' then raise exception 'invalid monthly invoice batch'; end if;
  if exists(select 1 from public.enterprise_requests r where r.organization_id=org and r.request_id=p_request_id) then return coalesce((select (r.result->>'inserted_rows')::integer from public.enterprise_requests r where r.organization_id=org and r.request_id=p_request_id),0); end if;
  for item in select value from jsonb_array_elements(p_invoices) loop
    if item ? 'payment_term_days' then begin proposed_days:=(item->>'payment_term_days')::integer; exception when others then raise exception 'invalid payment term'; end; if proposed_days<0 or proposed_days>3650 then raise exception 'invalid payment term'; end if; end if;
  end loop;
  report_name:=(array['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[p_month]||' '||p_year::text;
  perform 1 from public.reportes_mensuales where id=p_year::text||'-'||lpad(p_month::text,2,'0') and organization_id=org for update; if not found then raise exception 'monthly report not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(org::text||':'||report_name,0)); select coalesce(max(nro_fila),0) into next_row from public.reportes_ventas where organization_id=org and mes_reporte=report_name;
  for item in select value from jsonb_array_elements(p_invoices) order by case when trim(value->>'ref_fact')~'^[0-9]+$' then 0 else 1 end,case when trim(value->>'ref_fact')~'^[0-9]+$' then trim(value->>'ref_fact')::numeric end,trim(value->>'ref_fact') loop
    invoice_ref:=trim(coalesce(item->>'ref_fact','')); seller_label:=trim(coalesce(item->>'vendedor','')); begin invoice_date:=(item->>'fecha')::date; exception when others then raise exception 'invalid invoice date for %',invoice_ref; end;
    if invoice_ref='' or invoice_ref<>trim(coalesce(item->>'nro_fact','')) or invoice_date<make_date(p_year,p_month,1) or invoice_date>=(make_date(p_year,p_month,1)+interval '1 month')::date or seller_label='' then raise exception 'invalid invoice % for selected report',invoice_ref; end if;
    if not exists(select 1 from public.vendedores v where v.organization_id=org and seller_label=case when trim(v.codigo)='' then trim(v.nombre) else trim(v.codigo)||' - '||trim(v.nombre) end) then raise exception 'invalid seller for invoice %',invoice_ref; end if;
    upsert_result:=public.enterprise_upsert_invoice(gen_random_uuid(),invoice_ref,trim(coalesce(item->>'cliente','')),trim(coalesce(item->>'nombre_comercial','')),invoice_date,invoice_ref,(item->>'venta')::numeric,coalesce(item->>'identificacion_comprador',''),coalesce(item->>'tipo_identificacion_comprador','')); customer_id:=(upsert_result->>'customer_id')::uuid;
    if item ? 'payment_term_days' then
      proposed_days:=(item->>'payment_term_days')::integer;
      update public.billing_customers c set payment_term_days=proposed_days,updated_at=clock_timestamp(),updated_by=auth.uid() where c.id=customer_id and c.organization_id=org and c.payment_term_days is null;
      if not found and exists(select 1 from public.billing_customers c where c.id=customer_id and c.organization_id=org and c.payment_term_days<>proposed_days) then raise exception 'payment term changed concurrently'; end if;
      perform public.sync_enterprise_reminder(org,invoice_ref,p_request_id,'Automatic schedule after imported customer term');
    end if;
    if not exists(select 1 from public.reportes_ventas r where r.organization_id=org and r.mes_reporte=report_name and r.ref_fact=invoice_ref) then next_row:=next_row+1; insert into public.reportes_ventas(organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,numeros_recibo,comentarios_abonos,mes_reporte) values(org,next_row,invoice_ref,seller_label,0,'[]'::jsonb,'{}'::bigint[],'[]'::jsonb,report_name); inserted_rows:=inserted_rows+1; end if;
  end loop;
  insert into public.enterprise_requests(organization_id,request_id,action,result) values(org,p_request_id,'import_monthly_invoices',jsonb_build_object('inserted_rows',inserted_rows)); return inserted_rows;
end $$;
revoke all on function public.enterprise_import_monthly_invoices(uuid,integer,integer,jsonb) from public,anon;
grant execute on function public.enterprise_import_monthly_invoices(uuid,integer,integer,jsonb) to authenticated;
-- 20260903120000 renamed the legacy implementation; it remains only as an
-- implementation artifact and must not be an alternate authenticated route.
revoke all on function public.enterprise_import_monthly_invoices_without_terms(uuid,integer,integer,jsonb) from public,anon,authenticated;

-- Canonical ID APIs replace mutable name/commercial-name inputs.
drop function if exists public.delete_enterprise_customer_configuration(uuid,text,text);
drop function if exists public.schedule_enterprise_customer_pending(uuid,text,text);
create function public.delete_enterprise_customer_configuration(p_request_id uuid,p_customer_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); begin
  if p_request_id is null or p_customer_id is null then raise exception 'invalid customer identity'; end if;
  if exists(select 1 from public.enterprise_requests r where r.organization_id=org and r.request_id=p_request_id) then return; end if;
  update public.billing_customers set configuration_active=false,payment_term_days=null,updated_at=clock_timestamp(),updated_by=auth.uid() where id=p_customer_id and organization_id=org and configuration_active; if not found then raise exception 'enterprise customer not found'; end if;
  insert into public.enterprise_requests(organization_id,request_id,action,result) values(org,p_request_id,'delete_customer_configuration',jsonb_build_object('deleted',true)); end $$;
create function public.schedule_enterprise_customer_pending(p_request_id uuid,p_customer_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); customer public.billing_customers%rowtype; item record; result jsonb; created_count integer:=0; existing_count integer:=0; total_count integer:=0;
begin
  if p_request_id is null or p_customer_id is null then raise exception 'invalid customer identity'; end if;
  select r.result into result from public.enterprise_requests r where r.organization_id=org and r.request_id=p_request_id; if found then return result; end if;
  select * into customer from public.billing_customers where id=p_customer_id and organization_id=org and configuration_active for update; if not found then raise exception 'enterprise customer not found'; end if; if customer.payment_term_days is null then raise exception 'customer payment term is pending'; end if;
  select count(*)::integer,count(*) filter(where exists(select 1 from public.payment_reminders r where r.organization_id=t.organization_id and r.factura_id=t.factura_id))::integer into total_count,existing_count from public.invoice_payment_terms t where t.organization_id=org and t.customer_id=customer.id and t.active;
  for item in select t.factura_id from public.invoice_payment_terms t where t.organization_id=org and t.customer_id=customer.id and t.active and not exists(select 1 from public.payment_reminders r where r.organization_id=org and r.factura_id=t.factura_id) loop if public.sync_enterprise_reminder(org,item.factura_id,p_request_id,'manual customer reminder recovery') is not null then created_count:=created_count+1; end if; end loop;
  result:=jsonb_build_object('eligible_count',created_count,'created_count',created_count,'skipped_existing_count',existing_count,'skipped_count',greatest(total_count-existing_count-created_count,0)); insert into public.enterprise_requests(organization_id,request_id,action,result) values(org,p_request_id,'schedule_customer_pending',result); return result;
end $$;
revoke all on function public.delete_enterprise_customer_configuration(uuid,uuid) from public,anon;
revoke all on function public.schedule_enterprise_customer_pending(uuid,uuid) from public,anon;
grant execute on function public.delete_enterprise_customer_configuration(uuid,uuid) to authenticated;
grant execute on function public.schedule_enterprise_customer_pending(uuid,uuid) to authenticated;

-- Explicit history ownership through invoice_payment_terms, never display text.
create or replace function public.list_customer_invoice_history(p_customer_id uuid,p_offset integer default 0,p_limit integer default 25,p_status text default 'all',p_search text default '',p_sort text default 'recent') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); customer public.billing_customers%rowtype; result jsonb;
begin
  if p_offset<0 or p_limit<1 or p_limit>50 then raise exception 'invalid pagination'; end if; if p_status not in ('all','pending','paid','overdue','cancelled') or p_sort not in ('recent','oldest','sale','balance') then raise exception 'invalid filter'; end if;
  select * into customer from public.billing_customers c where c.id=p_customer_id and c.organization_id=org; if not found then raise exception 'enterprise customer not found'; end if;
  with invoice_data as (select f.ref_fact reference,coalesce(f.nro_fact,f.ref_fact) invoice_number,f.fecha invoice_date,f.venta sale,coalesce(x.paid,0) paid,coalesce(x.cancelled,false) cancelled,case when coalesce(x.cancelled,false) then 0 else greatest(f.venta-coalesce(x.paid,0),0) end balance,coalesce(x.seller,'') seller,coalesce(x.report_month,'') report_month,r.payment_date reminder_date,coalesce(r.calendar_comment,'') calendar_comment,coalesce(x.payments,'[]'::jsonb) payments from public.invoice_payment_terms t join public.facturas_maestras f on f.organization_id=t.organization_id and f.ref_fact=t.factura_id left join lateral (select max(rv.vendedor) filter(where upper(trim(coalesce(rv.vendedor,'')))<>'ANULADA') seller,max(rv.mes_reporte) report_month,bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA') cancelled,coalesce(sum((select coalesce(sum(v.value::numeric),0) from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)) v)),0) paid,coalesce(jsonb_agg(rv.abonos),'[]'::jsonb) payments from public.reportes_ventas rv where rv.organization_id=org and rv.ref_fact=f.ref_fact) x on true left join lateral (select pr.payment_date,pr.calendar_comment from public.payment_reminders pr where pr.organization_id=org and pr.factura_id=f.ref_fact and pr.active order by pr.updated_at desc,pr.id desc limit 1) r on true where t.organization_id=org and t.customer_id=customer.id and t.active), filtered as (select *,not cancelled and balance>.005 and reminder_date<timezone('America/Guayaquil',now())::date overdue from invoice_data where (trim(coalesce(p_search,''))='' or reference ilike '%'||trim(p_search)||'%' or invoice_number ilike '%'||trim(p_search)||'%' or seller ilike '%'||trim(p_search)||'%') and case p_status when 'pending' then not cancelled and balance>.005 when 'paid' then not cancelled and balance<=.005 when 'overdue' then not cancelled and balance>.005 and reminder_date<timezone('America/Guayaquil',now())::date when 'cancelled' then cancelled else true end), page as (select * from filtered order by case when p_sort='oldest' then invoice_date end asc,case when p_sort='sale' then sale end desc,case when p_sort='balance' then balance end desc,case when p_sort='recent' then invoice_date end desc,reference desc offset p_offset limit p_limit) select jsonb_build_object('summary',(select jsonb_build_object('total_sales',coalesce(sum(sale) filter(where not cancelled),0),'total_paid',coalesce(sum(paid) filter(where not cancelled),0),'balance',coalesce(sum(balance) filter(where not cancelled),0),'total_invoices',count(*),'paid_invoices',count(*) filter(where not cancelled and balance<=.005),'pending_invoices',count(*) filter(where not cancelled and balance>.005),'overdue_invoices',count(*) filter(where overdue),'cancelled_invoices',count(*) filter(where cancelled),'last_purchase',max(invoice_date) filter(where not cancelled),'next_payment',min(reminder_date) filter(where not cancelled and balance>.005)) from invoice_data),'filtered_count',(select count(*) from filtered),'invoices',coalesce((select jsonb_agg(jsonb_build_object('reference',reference,'invoice_number',invoice_number,'invoice_date',invoice_date,'seller',seller,'report_month',report_month,'sale',sale,'paid',paid,'balance',balance,'cancelled',cancelled,'overdue',overdue,'reminder_date',reminder_date,'calendar_comment',calendar_comment,'payments',payments) order by invoice_date desc,reference desc) from page),'[]'::jsonb)) into result; return result;
end $$;
revoke all on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text) from public,anon;
grant execute on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
