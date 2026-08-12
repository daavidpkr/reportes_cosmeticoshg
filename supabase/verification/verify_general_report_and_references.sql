begin;

-- Sanitized audit: no customer names or invoice identifiers are emitted.
select organization_id, mes_reporte, count(*) as blank_reference_rows
from public.reportes_ventas
where nullif(trim(ref_fact), '') is null
group by organization_id, mes_reporte
order by organization_id, mes_reporte;

select organization_id, count(*) as orphan_report_rows
from public.reportes_ventas r
where nullif(trim(r.ref_fact), '') is not null
  and not exists (
    select 1 from public.facturas_maestras f
    where f.organization_id = r.organization_id and f.ref_fact = r.ref_fact
  )
group by organization_id;

select organization_id, count(*) as duplicate_business_rows
from (
  select organization_id, mes_reporte, nro_fila
  from public.reportes_ventas
  group by organization_id, mes_reporte, nro_fila
  having count(*) > 1
) duplicates
group by organization_id;

rollback;
