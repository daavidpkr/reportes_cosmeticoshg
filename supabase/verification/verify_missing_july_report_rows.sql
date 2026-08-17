-- Run as an authenticated organization member. This script is read-only.
select * from public.enterprise_find_missing_report_rows(2026,7);

select f.ref_fact, true as facturas_maestras,
       (r.ref_fact is not null) as reportes_ventas,
       f.fecha,f.venta,r.mes_reporte,r.nro_fila,r.vendedor,r.esmaltes,
       r.abonos,r.comentarios_abonos,r.numeros_recibo
from public.facturas_maestras f
left join public.reportes_ventas r
  on r.organization_id=f.organization_id and r.ref_fact=f.ref_fact
where f.organization_id=public.require_current_organization_id()
  and f.ref_fact between '000000655' and '000000666'
order by f.fecha,r.nro_fila,f.ref_fact;

select count(*)-count(distinct f.ref_fact) as history_duplicates
from public.facturas_maestras f
left join public.reportes_ventas r
  on r.organization_id=f.organization_id and r.ref_fact=f.ref_fact
where f.organization_id=public.require_current_organization_id()
  and f.ref_fact='000000664';

select coalesce(sum(f.venta),0) total_ventas,
  coalesce(sum((select coalesce(sum(v::numeric),0)
    from jsonb_array_elements_text(coalesce(r.abonos,'[]'::jsonb)) v)),0) total_cobros,
  coalesce(sum(f.venta),0)-coalesce(sum((select coalesce(sum(v::numeric),0)
    from jsonb_array_elements_text(coalesce(r.abonos,'[]'::jsonb)) v)),0) por_cobrar
from public.reportes_ventas r join public.facturas_maestras f
  on f.organization_id=r.organization_id and f.ref_fact=r.ref_fact
where r.organization_id=public.require_current_organization_id()
  and r.mes_reporte='Julio 2026'
  and upper(trim(coalesce(r.vendedor,'')))<>'ANULADA';
