begin;

do $$
begin
  if not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='billing_customers'
      and column_name='horario_atencion') then
    raise exception 'horario_atencion is missing';
  end if;
  if has_function_privilege('anon',
      'public.update_customer_business_hours(uuid,text)', 'execute') then
    raise exception 'anonymous role can update customer business hours';
  end if;
  if not has_function_privilege('authenticated',
      'public.update_customer_business_hours(uuid,text)', 'execute') then
    raise exception 'authenticated role cannot update customer business hours';
  end if;
end;
$$;

rollback;
