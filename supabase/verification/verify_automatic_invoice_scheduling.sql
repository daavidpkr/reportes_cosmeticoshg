begin;

do $$
begin
  if public.calculate_enterprise_payment_date(date '2026-08-03',10)<>date '2026-08-13'
     or public.calculate_enterprise_payment_date(date '2026-08-10',5)<>date '2026-08-17'
     or public.calculate_enterprise_payment_date(date '2026-08-11',5)<>date '2026-08-17'
     or public.calculate_enterprise_payment_date(date '2026-08-12',5)<>date '2026-08-17' then
    raise exception 'calendar-day or weekend calculation regression';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='enterprise_save_report_row')<>1 then
    raise exception 'enterprise_save_report_row must have one signature';
  end if;
  if has_function_privilege('anon',
      'public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text)',
      'EXECUTE') then
    raise exception 'anonymous report writes must remain forbidden';
  end if;
  if has_function_privilege('authenticated',
      'public.sync_enterprise_reminder(uuid,text,uuid,text)','EXECUTE') then
    raise exception 'internal scheduling function is exposed';
  end if;
  if exists(select 1 from public.payment_reminders group by organization_id,factura_id having count(*)>1) then
    raise exception 'duplicate logical reminders found';
  end if;
  if exists(select 1 from public.payment_reminders r where not exists(
    select 1 from public.facturas_maestras f
    where f.organization_id=r.organization_id and f.ref_fact=r.factura_id)) then
    raise exception 'orphan reminders found';
  end if;
end $$;

rollback;
