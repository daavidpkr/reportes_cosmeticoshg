begin;

lock table public.billing_customers in share row exclusive mode;
lock table public.invoice_payment_terms in share row exclusive mode;

create temporary table customer_merge_before on commit drop as
select
  (select count(*) from public.facturas_maestras)::bigint invoices,
  (select count(*) from public.reportes_ventas)::bigint report_rows,
  (select coalesce(sum(venta),0) from public.facturas_maestras)::numeric sales,
  (select coalesce(sum((x.value #>> '{}')::numeric),0)
     from public.reportes_ventas r
     cross join lateral jsonb_array_elements(r.abonos) x(value))::numeric payments,
  (select count(*) from public.payment_reminders)::bigint reminders,
  (select count(*) from public.payment_followups)::bigint followups;

drop index if exists public.billing_customers_org_buyer_identity_key;

create temporary table customer_identity_evidence on commit drop as
select c.id, c.organization_id,
       coalesce(c.buyer_identification_normalized, invoice_ids.buyer_id) buyer_id
from public.billing_customers c
left join lateral (
  select case when count(distinct public.normalize_buyer_identification(
                       f.identificacion_comprador)) = 1
              then min(public.normalize_buyer_identification(
                       f.identificacion_comprador)) end buyer_id
  from public.invoice_payment_terms t
  join public.facturas_maestras f
    on f.organization_id=t.organization_id and f.ref_fact=t.factura_id
  where t.organization_id=c.organization_id and t.customer_id=c.id
    and public.normalize_buyer_identification(f.identificacion_comprador) is not null
) invoice_ids on true;

create temporary table customer_merge_map on commit drop as
with invoice_counts as (
  select t.organization_id,t.customer_id,count(*) invoice_count,
    count(*) filter (where exists (
      select 1 from public.payment_reminders r
      where r.organization_id=t.organization_id and r.factura_id=t.factura_id
    ) or exists (
      select 1 from public.reportes_ventas rv
      where rv.organization_id=t.organization_id and rv.ref_fact=t.factura_id
        and jsonb_array_length(rv.abonos)>0
    )) activity_count
  from public.invoice_payment_terms t group by 1,2
), ranked as (
  select e.id,e.organization_id,e.buyer_id,
    first_value(e.id) over (partition by e.organization_id,e.buyer_id order by
      (c.payment_term_days is not null) desc,
      coalesce(ic.invoice_count,0) desc,
      coalesce(ic.activity_count,0) desc,
      (nullif(trim(c.horario_atencion),'') is not null) desc,
      (nullif(trim(c.commercial_name),'') is not null) desc,
      ((nullif(trim(c.address),'') is not null)::int+
       (nullif(trim(c.phone),'') is not null)::int+
       (nullif(trim(c.email),'') is not null)::int) desc,
      c.configuration_active desc,c.created_at,c.id) canonical_id
  from customer_identity_evidence e
  join public.billing_customers c on c.id=e.id
  left join invoice_counts ic
    on ic.organization_id=e.organization_id and ic.customer_id=e.id
  where e.buyer_id is not null
)
select organization_id,buyer_id,id duplicate_id,canonical_id
from ranked where id<>canonical_id;

-- Keep manual configuration and useful contact values when the selected
-- canonical profile lacks them. Identity and invoice-owned visible values are
-- refreshed separately below.
update public.billing_customers c set
  payment_term_days=coalesce(c.payment_term_days,d.payment_term_days),
  horario_atencion=coalesce(nullif(trim(c.horario_atencion),''),d.horario_atencion),
  commercial_name=coalesce(nullif(trim(c.commercial_name),''),d.commercial_name),
  address=coalesce(nullif(trim(c.address),''),d.address),
  phone=coalesce(nullif(trim(c.phone),''),d.phone),
  email=coalesce(nullif(trim(c.email),''),d.email),
  configuration_active=c.configuration_active or d.configuration_active,
  updated_at=clock_timestamp()
from customer_merge_map m
join public.billing_customers d on d.id=m.duplicate_id
where c.id=m.canonical_id;

update public.invoice_payment_terms t set
  customer_id=m.canonical_id,updated_at=clock_timestamp()
from customer_merge_map m
where t.organization_id=m.organization_id and t.customer_id=m.duplicate_id;

delete from public.billing_customers c using customer_merge_map m
where c.id=m.duplicate_id
  and not exists (select 1 from public.invoice_payment_terms t
                  where t.customer_id=c.id and t.organization_id=c.organization_id);

update public.billing_customers c set
  buyer_identification=e.buyer_id,
  buyer_identification_normalized=e.buyer_id,
  updated_at=clock_timestamp()
from customer_identity_evidence e
where c.id=e.id and e.buyer_id is not null
  and not exists (select 1 from customer_merge_map m where m.duplicate_id=e.id);

-- The latest valid invoice is authoritative for visible invoice-owned fields.
with latest as (
  select distinct on (t.organization_id,t.customer_id)
    t.organization_id,t.customer_id,f.cliente,f.nombre_comercial,
    f.direccion_comprador,f.telefono_comprador,f.correo_comprador,
    f.fecha,f.ref_fact
  from public.invoice_payment_terms t
  join public.facturas_maestras f
    on f.organization_id=t.organization_id and f.ref_fact=t.factura_id
  where public.normalize_buyer_identification(f.identificacion_comprador) is not null
  order by t.organization_id,t.customer_id,f.fecha desc,f.ref_fact desc
)
update public.billing_customers c set
  name=coalesce(nullif(trim(l.cliente),''),c.name),
  commercial_name=coalesce(nullif(trim(l.nombre_comercial),''),c.commercial_name),
  address=coalesce(nullif(trim(l.direccion_comprador),''),c.address),
  phone=coalesce(nullif(trim(l.telefono_comprador),''),c.phone),
  email=coalesce(nullif(trim(l.correo_comprador),''),c.email),
  profile_invoice_date=l.fecha,profile_invoice_ref=l.ref_fact,
  contact_invoice_date=l.fecha,contact_invoice_ref=l.ref_fact,
  updated_at=clock_timestamp()
from latest l where c.id=l.customer_id and c.organization_id=l.organization_id;

create unique index billing_customers_org_buyer_identity_key
  on public.billing_customers(organization_id,buyer_identification_normalized)
  where buyer_identification_normalized is not null;

create or replace function public.upsert_billing_customer_canonical(
  p_organization_id uuid,p_historical_customer_id uuid,p_identification text,
  p_identification_type text,p_name text,p_commercial_name text,
  p_invoice_date date,p_invoice_ref text,p_address text,p_phone text,p_email text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  buyer_id text:=public.normalize_buyer_identification(p_identification);
  candidate_ids uuid[]; customer_id uuid; newer boolean;
begin
  if p_organization_id is distinct from public.require_current_organization_id()
     or nullif(trim(coalesce(p_name,'')),'') is null then
    raise exception 'invalid canonical customer request';
  end if;
  if buyer_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      p_organization_id::text||':customer-id:'||buyer_id,0));
    select array_agg(id order by id) into candidate_ids
    from public.billing_customers
    where organization_id=p_organization_id
      and buyer_identification_normalized=buyer_id;
  end if;
  if coalesce(array_length(candidate_ids,1),0)=0
     and p_historical_customer_id is not null then
    select array_agg(id) into candidate_ids from public.billing_customers
    where organization_id=p_organization_id and id=p_historical_customer_id
      and (buyer_identification_normalized is null
           or buyer_identification_normalized=buyer_id or buyer_id is null);
  end if;
  if coalesce(array_length(candidate_ids,1),0)=0 then
    select array_agg(id order by id) into candidate_ids
    from public.billing_customers
    where organization_id=p_organization_id
      and buyer_identification_normalized is null
      and public.normalize_customer_match_identity(name)=
          public.normalize_customer_match_identity(p_name)
      and public.normalize_customer_match_identity(commercial_name)=
          public.normalize_customer_match_identity(p_commercial_name);
  end if;
  if coalesce(array_length(candidate_ids,1),0)>1 then
    raise exception 'ambiguous customer identity for invoice %',p_invoice_ref;
  end if;
  customer_id:=candidate_ids[1];
  if customer_id is null then
    begin
      insert into public.billing_customers(
        organization_id,name,commercial_name,buyer_identification,
        buyer_identification_normalized,buyer_identification_type,
        profile_invoice_date,profile_invoice_ref,address,phone,email,
        contact_invoice_date,contact_invoice_ref,updated_by)
      values(p_organization_id,trim(p_name),trim(coalesce(p_commercial_name,'')),
        buyer_id,buyer_id,nullif(trim(coalesce(p_identification_type,'')),''),
        p_invoice_date,trim(p_invoice_ref),
        public.clean_buyer_address(p_address),public.clean_buyer_phone(p_phone),
        public.clean_buyer_email(p_email),p_invoice_date,trim(p_invoice_ref),auth.uid())
      returning id into customer_id;
    exception when unique_violation then
      select id into customer_id from public.billing_customers
      where organization_id=p_organization_id
        and ((buyer_id is not null and buyer_identification_normalized=buyer_id)
          or (buyer_id is null and buyer_identification_normalized is null
            and public.normalize_customer_match_identity(name)=
                public.normalize_customer_match_identity(p_name)
            and public.normalize_customer_match_identity(commercial_name)=
                public.normalize_customer_match_identity(p_commercial_name)));
      if customer_id is null then raise; end if;
    end;
  end if;
  select public.invoice_profile_is_newer(p_invoice_date,p_invoice_ref,
    c.profile_invoice_date,c.profile_invoice_ref) into newer
  from public.billing_customers c where c.id=customer_id for update;
  update public.billing_customers c set
    buyer_identification=coalesce(c.buyer_identification,buyer_id),
    buyer_identification_normalized=coalesce(c.buyer_identification_normalized,buyer_id),
    buyer_identification_type=coalesce(nullif(trim(coalesce(p_identification_type,'')),''),c.buyer_identification_type),
    name=case when newer and nullif(trim(p_name),'') is not null then trim(p_name) else c.name end,
    commercial_name=case when newer and nullif(trim(coalesce(p_commercial_name,'')),'') is not null then trim(p_commercial_name) else c.commercial_name end,
    address=case when newer and public.clean_buyer_address(p_address)<>'' then public.clean_buyer_address(p_address) else c.address end,
    phone=case when newer and public.clean_buyer_phone(p_phone)<>'' then public.clean_buyer_phone(p_phone) else c.phone end,
    email=case when newer and public.clean_buyer_email(p_email)<>'' then public.clean_buyer_email(p_email) else c.email end,
    profile_invoice_date=case when newer then p_invoice_date else c.profile_invoice_date end,
    profile_invoice_ref=case when newer then trim(p_invoice_ref) else c.profile_invoice_ref end,
    contact_invoice_date=case when newer then p_invoice_date else c.contact_invoice_date end,
    contact_invoice_ref=case when newer then trim(p_invoice_ref) else c.contact_invoice_ref end,
    updated_at=clock_timestamp(),updated_by=auth.uid()
  where c.id=customer_id and c.organization_id=p_organization_id;
  return customer_id;
end $$;
revoke all on function public.upsert_billing_customer_canonical(
  uuid,uuid,text,text,text,text,date,text,text,text,text) from public,anon,authenticated;

-- Rewrite the two live writers in-place. Abort if their audited definitions
-- ever differ, so a future migration cannot silently restore a name-based path.
do $$
declare d text; changed text;
begin
  select pg_get_functiondef('public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric,text,text,text,text,text)'::regprocedure) into d;
  changed:=regexp_replace(d,
    'resolution := public\.resolve_enterprise_import_customer\(.*?customer_id := \(resolution->>''customer_id''\)::uuid;\s*', '', 'ns');
  changed:=regexp_replace(changed,
    'if customer_id is null then.*?end if;\s*\n\s*insert into public\.invoice_payment_terms',
    E'select t.customer_id into customer_id from public.invoice_payment_terms t where t.organization_id=org and t.factura_id=trim(p_ref_fact);\n  customer_id:=public.upsert_billing_customer_canonical(org,customer_id,p_identificacion_comprador,p_tipo_identificacion_comprador,p_cliente,p_nombre_comercial,p_fecha,p_ref_fact,p_direccion_comprador,p_telefono_comprador,p_correo_comprador);\n\n  insert into public.invoice_payment_terms','s');
  if changed=d or lower(changed) like '%insert into public.billing_customers%' then
    raise exception 'enterprise_upsert_invoice canonical rewrite failed';
  end if;
  execute changed;

  select pg_get_functiondef('public.enterprise_save_report_row_unchecked(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text)'::regprocedure) into d;
  changed:=regexp_replace(d,
    'insert into public\.billing_customers.*?returning id into customer_id;',
    E'select t.customer_id into customer_id from public.invoice_payment_terms t where t.organization_id=org and t.factura_id=trim(p_ref_fact);\n    customer_id:=public.upsert_billing_customer_canonical(org,customer_id,(select f.identificacion_comprador from public.facturas_maestras f where f.organization_id=org and f.ref_fact=trim(p_ref_fact)),(select f.tipo_identificacion_comprador from public.facturas_maestras f where f.organization_id=org and f.ref_fact=trim(p_ref_fact)),p_cliente,p_commercial_name,p_invoice_date,p_ref_fact,\'\',\'\',\'\');','is');
  if changed=d or lower(changed) like '%insert into public.billing_customers%' then
    raise exception 'enterprise_save_report_row_unchecked canonical rewrite failed';
  end if;
  execute changed;
end $$;

revoke insert,update,delete on public.billing_customers from anon,authenticated;

do $$
declare b customer_merge_before%rowtype; a record; residual bigint;
begin
  select * into b from customer_merge_before;
  select (select count(*) from public.facturas_maestras) invoices,
    (select count(*) from public.reportes_ventas) report_rows,
    (select coalesce(sum(venta),0) from public.facturas_maestras) sales,
    (select coalesce(sum((x.value#>>'{}')::numeric),0) from public.reportes_ventas r cross join lateral jsonb_array_elements(r.abonos) x(value)) payments,
    (select count(*) from public.payment_reminders) reminders,
    (select count(*) from public.payment_followups) followups into a;
  if row(b.invoices,b.report_rows,b.sales,b.payments,b.reminders,b.followups)
     is distinct from row(a.invoices,a.report_rows,a.sales,a.payments,a.reminders,a.followups) then
    raise exception 'customer consolidation changed financial facts';
  end if;
  select count(*) into residual from customer_merge_map m
  join public.billing_customers c on c.id=m.duplicate_id;
  if residual<>0 then raise exception 'customer duplicate retained relations'; end if;
  raise notice 'customer consolidation: canonical mappings=%, removed=%, invoices=%, payments=%',
    (select count(distinct canonical_id) from customer_merge_map),
    (select count(*) from customer_merge_map),a.invoices,a.payments;
end $$;

notify pgrst,'reload schema';
commit;
