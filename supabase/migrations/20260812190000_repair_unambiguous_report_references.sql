begin;

-- Repair only blank report references for which exactly one unlinked invoice in
-- the same organization and calendar month proves the relationship. The
-- business reference must also equal nro_fact after removing leading zeroes.
-- Ambiguous rows deliberately remain untouched for manual review.
with month_names(name, month_number) as (
  values ('Enero',1),('Febrero',2),('Marzo',3),('Abril',4),('Mayo',5),
         ('Junio',6),('Julio',7),('Agosto',8),('Septiembre',9),
         ('Octubre',10),('Noviembre',11),('Diciembre',12)
), candidates as (
  select r.id as report_row_id, f.ref_fact,
         count(*) over (partition by r.id) as candidate_count
  from public.reportes_ventas r
  join month_names mn on r.mes_reporte like mn.name || ' %'
  join public.facturas_maestras f
    on f.organization_id = r.organization_id
   and extract(month from f.fecha)::integer = mn.month_number
   and extract(year from f.fecha)::integer =
       substring(r.mes_reporte from '([0-9]{4})$')::integer
   and nullif(ltrim(f.nro_fact, '0'), '') = nullif(ltrim(f.ref_fact, '0'), '')
  where nullif(trim(r.ref_fact), '') is null
    and not exists (
      select 1 from public.reportes_ventas linked
      where linked.organization_id = r.organization_id
        and linked.ref_fact = f.ref_fact
    )
), proven as (
  select report_row_id, ref_fact from candidates where candidate_count = 1
)
update public.reportes_ventas r
set ref_fact = p.ref_fact
from proven p
where r.id = p.report_row_id
  and nullif(trim(r.ref_fact), '') is null;

commit;
