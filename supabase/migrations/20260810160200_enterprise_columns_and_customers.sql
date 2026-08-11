begin;

alter table public.facturas_maestras add column organization_id uuid references public.organizations(id) on delete restrict;
alter table public.reportes_mensuales add column organization_id uuid references public.organizations(id) on delete restrict;
alter table public.reportes_ventas add column organization_id uuid references public.organizations(id) on delete restrict;
alter table public.vendedores add column organization_id uuid references public.organizations(id) on delete restrict;
alter table public.payment_reminders add column organization_id uuid references public.organizations(id) on delete restrict;
alter table public.payment_followups add column organization_id uuid references public.organizations(id) on delete restrict;
alter table public.payment_notification_events add column organization_id uuid references public.organizations(id) on delete restrict;
alter table public.fcm_devices add column organization_id uuid references public.organizations(id) on delete restrict;

create function public.normalize_customer_identity(value text)
returns text language sql immutable set search_path = '' as $$
  select lower(regexp_replace(trim(coalesce(value,'')), '\s+', ' ', 'g'));
$$;

create table public.billing_customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (length(trim(name)) > 0),
  commercial_name text not null default '',
  normalized_name text generated always as (public.normalize_customer_identity(name)) stored,
  normalized_commercial_name text generated always as (public.normalize_customer_identity(commercial_name)) stored,
  payment_term_days integer check (payment_term_days is null or payment_term_days >= 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id) on delete restrict,
  unique (organization_id, normalized_name, normalized_commercial_name),
  unique (id, organization_id)
);

create table public.invoice_payment_terms (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  factura_id text not null,
  customer_id uuid not null,
  exceptional_term_days integer check (exceptional_term_days is null or exceptional_term_days >= 0),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id) on delete restrict,
  primary key (organization_id, factura_id),
  foreign key (factura_id) references public.facturas_maestras(ref_fact) on update cascade on delete cascade,
  foreign key (customer_id, organization_id) references public.billing_customers(id, organization_id) on delete restrict
);

alter table public.payment_reminders
  add column date_source text not null default 'manual'
    check (date_source in ('manual','customer_term','invoice_exception')),
  add column calculated_term_days integer
    check (calculated_term_days is null or calculated_term_days >= 0);

create index facturas_maestras_organization_idx on public.facturas_maestras(organization_id, ref_fact);
create index reportes_mensuales_organization_idx on public.reportes_mensuales(organization_id);
create index reportes_ventas_organization_idx on public.reportes_ventas(organization_id, ref_fact);
create index vendedores_organization_idx on public.vendedores(organization_id);
create index payment_reminders_organization_idx on public.payment_reminders(organization_id, payment_date);
create unique index payment_reminders_org_invoice_key
  on public.payment_reminders(organization_id, factura_id) where organization_id is not null;
create index payment_followups_organization_idx on public.payment_followups(organization_id, created_at desc);
create index payment_events_organization_idx on public.payment_notification_events(organization_id, status);
create index billing_customers_status_idx on public.billing_customers(organization_id, payment_term_days, name);
create index invoice_payment_terms_customer_idx on public.invoice_payment_terms(customer_id, active);

alter table public.billing_customers enable row level security;
alter table public.invoice_payment_terms enable row level security;
create policy "members read enterprise customers" on public.billing_customers
for select to authenticated using (organization_id=public.current_organization_id());
create policy "members read enterprise invoice terms" on public.invoice_payment_terms
for select to authenticated using (organization_id=public.current_organization_id());

revoke all on public.billing_customers, public.invoice_payment_terms from public, anon, authenticated;
grant select on public.billing_customers, public.invoice_payment_terms to authenticated;
grant select, insert, update on public.billing_customers, public.invoice_payment_terms to service_role;
revoke all on function public.normalize_customer_identity(text) from public, anon, authenticated;

commit;
