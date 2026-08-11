-- ADMINISTRATIVE SCRIPT. PREPARED ONLY; DO NOT RUN WITHOUT EXPLICIT AUTHORIZATION.
-- Requires a verified backup and service-level database access.
begin;

do $$
begin
  if (select count(*) from auth.users) <> 1 then
    raise exception 'expected exactly one audited initial user; repeat the audit';
  end if;
  if (select count(*) from public.facturas_maestras) <> 15
     or (select count(*) from public.reportes_ventas) <> 15
     or (select count(*) from public.reportes_mensuales) <> 1
     or (select count(*) from public.vendedores) <> 2 then
    raise exception 'historical counts changed; repeat backup and audit';
  end if;
end;
$$;

insert into public.organizations(name,active)
values('Cosméticos HG',true)
on conflict ((lower(regexp_replace(trim(name),'\s+',' ','g'))))
do update set active=true,updated_at=clock_timestamp();

insert into public.organization_members(organization_id,user_id,role,active,created_by)
select o.id,u.id,'admin',true,u.id
from public.organizations o cross join auth.users u
where o.name='Cosméticos HG'
on conflict(organization_id,user_id) do update set
  role='admin',active=true,revoked_at=null;

update public.facturas_maestras set organization_id=(select id from public.organizations where name='Cosméticos HG')
where organization_id is null;
update public.reportes_mensuales set organization_id=(select id from public.organizations where name='Cosméticos HG')
where organization_id is null;
update public.reportes_ventas set organization_id=(select id from public.organizations where name='Cosméticos HG')
where organization_id is null;
update public.vendedores set organization_id=(select id from public.organizations where name='Cosméticos HG')
where organization_id is null;
update public.payment_reminders set organization_id=(select id from public.organizations where name='Cosméticos HG')
where organization_id is null;
update public.payment_followups f set organization_id=r.organization_id
from public.payment_reminders r where f.reminder_id=r.id and f.organization_id is null;
update public.payment_notification_events e set organization_id=r.organization_id
from public.payment_reminders r where e.reminder_id=r.id and e.organization_id is null;
update public.fcm_devices d set organization_id=m.organization_id
from public.organization_members m where d.user_id=m.user_id and m.active and d.organization_id is null;

insert into public.billing_customers(
  organization_id,name,commercial_name,updated_by
)
select distinct on (
  f.organization_id,
  public.normalize_customer_identity(f.cliente),
  public.normalize_customer_identity(f.nombre_comercial)
)
  f.organization_id,trim(f.cliente),trim(f.nombre_comercial),m.user_id
from public.facturas_maestras f
join public.organization_members m
  on m.organization_id=f.organization_id and m.active and m.role='admin'
order by f.organization_id,
  public.normalize_customer_identity(f.cliente),
  public.normalize_customer_identity(f.nombre_comercial),f.ref_fact
on conflict (organization_id,normalized_name,normalized_commercial_name)
do update set name=excluded.name,commercial_name=excluded.commercial_name,
  updated_at=clock_timestamp(),updated_by=excluded.updated_by;

insert into public.invoice_payment_terms(
  organization_id,factura_id,customer_id,active,updated_by
)
select f.organization_id,f.ref_fact,c.id,true,m.user_id
from public.facturas_maestras f
join public.billing_customers c
  on c.organization_id=f.organization_id
 and c.normalized_name=public.normalize_customer_identity(f.cliente)
 and c.normalized_commercial_name=public.normalize_customer_identity(f.nombre_comercial)
join public.organization_members m
  on m.organization_id=f.organization_id and m.active and m.role='admin'
on conflict (organization_id,factura_id) do update set
  customer_id=excluded.customer_id,active=true,
  updated_at=clock_timestamp(),updated_by=excluded.updated_by;

do $$
begin
  if exists(select 1 from public.facturas_maestras where organization_id is null)
     or exists(select 1 from public.reportes_mensuales where organization_id is null)
     or exists(select 1 from public.reportes_ventas where organization_id is null)
     or exists(select 1 from public.vendedores where organization_id is null)
     or exists(select 1 from public.payment_reminders where organization_id is null)
     or exists(select 1 from public.payment_followups where organization_id is null)
     or exists(select 1 from public.payment_notification_events where organization_id is null)
     or exists(select 1 from public.fcm_devices where organization_id is null)
     or (select count(*) from public.invoice_payment_terms)
        <> (select count(*) from public.facturas_maestras)
     or exists (
       select 1 from public.invoice_payment_terms t
       join public.facturas_maestras f on f.ref_fact=t.factura_id
       where t.organization_id<>f.organization_id
     ) then
    raise exception 'enterprise backfill left unassigned records';
  end if;
end;
$$;

commit;
