begin;

create or replace function public.enterprise_report_aggregates()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  org uuid := public.require_current_organization_id();
  result jsonb;
begin
  with invoice_state as (
    select
      f.ref_fact,
      f.venta,
      bool_or(upper(trim(coalesce(rv.vendedor, ''))) = 'ANULADA') as cancelled,
      coalesce(max(rv.esmaltes) filter (
        where upper(trim(coalesce(rv.vendedor, ''))) <> 'ANULADA'
      ), 0) as nail_polish,
      coalesce(sum((
        select coalesce(sum(value::numeric), 0)
        from jsonb_array_elements_text(coalesce(rv.abonos, '[]'::jsonb)) value
      )), 0) as paid
    from public.facturas_maestras f
    join public.reportes_ventas rv
      on rv.organization_id = f.organization_id
     and rv.ref_fact = f.ref_fact
    where f.organization_id = org
      and trim(f.ref_fact) <> ''
    group by f.ref_fact, f.venta
  )
  select jsonb_build_object(
    'historical_nail_polish',
      coalesce(sum(nail_polish) filter (where not cancelled), 0),
    'historical_sales',
      coalesce(sum(venta) filter (where not cancelled), 0),
    'total_receivable',
      coalesce(sum(greatest(venta - paid, 0)) filter (
        where not cancelled and venta - paid > .005
      ), 0)
  )
  into result
  from invoice_state;

  return result;
end;
$$;

revoke all on function public.enterprise_report_aggregates() from public, anon;
grant execute on function public.enterprise_report_aggregates()
  to authenticated, service_role;

commit;
