begin;

select set_config(
  'request.jwt.claim.sub',
  (select m.user_id::text from public.organization_members m
   where m.active order by m.created_at limit 1),
  true
);
set local role authenticated;

do $$
declare
  org uuid := public.require_current_organization_id();
  buyer_id text := 'TEST' || replace(gen_random_uuid()::text, '-', '');
  base_ref bigint := floor(extract(epoch from clock_timestamp()) * 1000000)::bigint;
  ref_9 text := (base_ref + 9)::text;
  ref_10 text := (base_ref + 10)::text;
  ref_11 text := (base_ref + 11)::text;
  customer_id uuid;
  current_customer record;
  current_invoice record;
  legacy_customer_id uuid;
  legacy_name text := 'LEGACY CONTACT ' || gen_random_uuid()::text;
begin
  customer_id := (public.enterprise_upsert_invoice(
    gen_random_uuid(), ref_9, 'Contacto sintético', 'Local sintético',
    '2098-01-01', ref_9, 10, buyer_id, '04',
    'Dirección anterior', '0990000000', 'old@example.com'
  )->>'customer_id')::uuid;

  if customer_id is distinct from (public.enterprise_upsert_invoice(
    gen_random_uuid(), ref_10, 'Contacto sintético', 'Local sintético',
    '2098-01-01', ref_10, 10, buyer_id, '04',
    'Dirección reciente', '+593991112222', 'NEW@EXAMPLE.COM'
  )->>'customer_id')::uuid then
    raise exception 'buyer identity did not resolve to one canonical customer';
  end if;

  perform public.enterprise_upsert_invoice(
    gen_random_uuid(), ref_11, 'Contacto sintético', 'Local sintético',
    '2098-01-01', ref_11, 10, buyer_id, '04', '', 'vacío', 'correo-inválido'
  );
  perform public.enterprise_upsert_invoice(
    gen_random_uuid(), ref_9, 'Contacto sintético', 'Local sintético',
    '2098-01-01', ref_9, 10, buyer_id, '04',
    'No debe ganar', '0988888888', 'lose@example.com'
  );

  select c.address, c.phone, c.email, c.contact_invoice_ref
  into current_customer from public.billing_customers c
  where c.id = customer_id and c.organization_id = org;
  if (current_customer.address, current_customer.phone,
      current_customer.email, current_customer.contact_invoice_ref)
     is distinct from
     ('Dirección reciente', '+593991112222', 'new@example.com', ref_11) then
    raise exception 'latest non-empty canonical contact selection failed';
  end if;

  select f.direccion_comprador, f.telefono_comprador, f.correo_comprador
  into current_invoice from public.facturas_maestras f
  where f.organization_id = org and f.ref_fact = ref_10;
  if (current_invoice.direccion_comprador, current_invoice.telefono_comprador,
      current_invoice.correo_comprador) is distinct from
     ('Dirección reciente', '+593991112222', 'new@example.com') then
    raise exception 'invoice contact evidence was not preserved';
  end if;

  select f.direccion_comprador, f.telefono_comprador, f.correo_comprador
  into current_invoice from public.facturas_maestras f
  where f.organization_id = org and f.ref_fact = ref_11;
  if (current_invoice.direccion_comprador, current_invoice.telefono_comprador,
      current_invoice.correo_comprador) is distinct from ('', '', '') then
    raise exception 'invalid or empty invoice contact was not cleaned';
  end if;

  legacy_customer_id := (public.enterprise_upsert_invoice(
    gen_random_uuid(), (base_ref + 20)::text, legacy_name, '', '2098-01-01',
    (base_ref + 20)::text, 10, '', '', 'Dirección legado',
    '0997777777', 'legacy@example.com'
  )->>'customer_id')::uuid;
  if exists (select 1 from public.billing_customers c
    where c.id = legacy_customer_id and c.organization_id = org
      and (c.address <> '' or c.phone <> '' or c.email <> '')) then
    raise exception 'unidentified legacy customer received canonical contact';
  end if;

  if not (select c.relrowsecurity from pg_class c
          where c.oid = 'public.billing_customers'::regclass) then
    raise exception 'billing_customers RLS is disabled';
  end if;
  if has_table_privilege('anon', 'public.billing_customers', 'select')
     or not has_table_privilege(
       'authenticated', 'public.billing_customers', 'select')
     or has_table_privilege(
       'authenticated', 'public.billing_customers', 'update') then
    raise exception 'billing_customers grants are unsafe';
  end if;
  if has_function_privilege('anon',
       'public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric,text,text,text,text,text)',
       'execute')
     or not has_function_privilege('authenticated',
       'public.enterprise_upsert_invoice(uuid,text,text,text,date,text,numeric,text,text,text,text,text)',
       'execute') then
    raise exception 'enterprise_upsert_invoice grants are unsafe';
  end if;
end $$;

select jsonb_build_object(
  'canonical_identity', true,
  'latest_invoice_wins', true,
  'empty_does_not_overwrite', true,
  'invoice_evidence', true,
  'legacy_identity_safe', true,
  'rls', true,
  'permissions', true,
  'rpc', true
) as buyer_contact_audit;

rollback;
