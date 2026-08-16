begin;

do $$
begin
  if exists(
    select 1 from pg_constraint c
    join pg_class child on child.oid=c.conrelid
    join pg_class parent on parent.oid=c.confrelid
    where c.contype='f' and parent.relname='billing_customers'
      and child.relname in ('facturas_maestras','reportes_ventas','payment_reminders')
      and c.confdeltype='c'
  ) then raise exception 'destructive customer cascade found'; end if;
  if not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='billing_customers'
      and column_name='configuration_active') then
    raise exception 'configuration deletion marker missing';
  end if;
  if has_function_privilege('anon',
    'public.delete_enterprise_customer_configuration(uuid,text,text)','EXECUTE')
    or has_function_privilege('anon',
    'public.schedule_enterprise_customer_pending(uuid,text,text)','EXECUTE') then
    raise exception 'anonymous client action access found';
  end if;
  if exists(select 1 from public.payment_reminders
    group by organization_id,factura_id having count(*)>1) then
    raise exception 'duplicate logical reminders found';
  end if;
  if exists(select 1 from public.payment_reminders r where not exists(
    select 1 from public.facturas_maestras f
    where f.organization_id=r.organization_id and f.ref_fact=r.factura_id)) then
    raise exception 'orphan reminders found';
  end if;
end $$;

-- Destructive scenario tests must add isolated fixture data here and remain
-- inside this transaction. No production row is changed by this verification.
rollback;
