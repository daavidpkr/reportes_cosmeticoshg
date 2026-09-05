-- Correct the explicit canonical history RPC introduced in 20260904120000.
-- The previous definition calculated overdue in `filtered` but read it from
-- `invoice_data` for the summary. This version defines it at invoice level.
begin;

create or replace function public.list_customer_invoice_history(
  p_customer_id uuid,p_offset integer default 0,p_limit integer default 25,
  p_status text default 'all',p_search text default '',p_sort text default 'recent'
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); customer public.billing_customers%rowtype; result jsonb;
begin
  if p_offset<0 or p_limit<1 or p_limit>50 then raise exception 'invalid pagination'; end if;
  if p_status not in ('all','pending','paid','overdue','cancelled') or p_sort not in ('recent','oldest','sale','balance') then raise exception 'invalid filter'; end if;
  select * into customer from public.billing_customers c where c.id=p_customer_id and c.organization_id=org;
  if not found then raise exception 'enterprise customer not found'; end if;
  with invoice_data as (
    select f.ref_fact reference,coalesce(f.nro_fact,f.ref_fact) invoice_number,f.fecha invoice_date,f.venta sale,
      coalesce(x.seller,'') seller,coalesce(x.report_month,'') report_month,coalesce(x.paid,0) paid,coalesce(x.cancelled,false) cancelled,
      case when coalesce(x.cancelled,false) then 0 else greatest(f.venta-coalesce(x.paid,0),0) end balance,
      r.payment_date reminder_date,coalesce(r.calendar_comment,'') calendar_comment,coalesce(x.payments,'[]'::jsonb) payments
    from public.invoice_payment_terms t join public.facturas_maestras f on f.organization_id=t.organization_id and f.ref_fact=t.factura_id
    left join lateral (
      select max(rv.vendedor) filter(where upper(trim(coalesce(rv.vendedor,'')))<>'ANULADA') seller,max(rv.mes_reporte) report_month,
        bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA') cancelled,
        coalesce(sum((select coalesce(sum(v.value::numeric),0) from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)) v)),0) paid,
        coalesce(jsonb_agg(payment.item) filter(where payment.item is not null),'[]'::jsonb) payments
      from public.reportes_ventas rv left join lateral (
        select jsonb_agg(jsonb_build_object('amount',(p.value #>> '{}')::numeric,'receipt',rv.numeros_recibo[p.ordinal::integer],'comment',rv.comentarios_abonos->>((p.ordinal-1)::integer)) order by p.ordinal) item
        from jsonb_array_elements(coalesce(rv.abonos,'[]'::jsonb)) with ordinality p(value,ordinal)
      ) payment on true where rv.organization_id=org and rv.ref_fact=f.ref_fact
    ) x on true
    left join lateral (select pr.payment_date,pr.calendar_comment from public.payment_reminders pr where pr.organization_id=org and pr.factura_id=f.ref_fact and pr.active order by pr.updated_at desc,pr.id desc limit 1) r on true
    where t.organization_id=org and t.customer_id=customer.id and t.active
  ), filtered as (
    select *,not cancelled and balance>.005 and reminder_date<timezone('America/Guayaquil',now())::date overdue from invoice_data
    where (trim(coalesce(p_search,''))='' or reference ilike '%'||trim(p_search)||'%' or invoice_number ilike '%'||trim(p_search)||'%' or seller ilike '%'||trim(p_search)||'%')
      and case p_status when 'pending' then not cancelled and balance>.005 when 'paid' then not cancelled and balance<=.005 when 'overdue' then not cancelled and balance>.005 and reminder_date<timezone('America/Guayaquil',now())::date when 'cancelled' then cancelled else true end
  ), page as (
    select * from filtered order by case when p_sort='oldest' then invoice_date end asc,case when p_sort='sale' then sale end desc,case when p_sort='balance' then balance end desc,case when p_sort='recent' then invoice_date end desc,reference desc offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'summary',(select jsonb_build_object('total_sales',coalesce(sum(sale) filter(where not cancelled),0),'total_paid',coalesce(sum(paid) filter(where not cancelled),0),'balance',coalesce(sum(balance) filter(where not cancelled),0),'total_invoices',count(*),'paid_invoices',count(*) filter(where not cancelled and balance<=.005),'pending_invoices',count(*) filter(where not cancelled and balance>.005),'overdue_invoices',count(*) filter(where not cancelled and balance>.005 and reminder_date<timezone('America/Guayaquil',now())::date),'cancelled_invoices',count(*) filter(where cancelled),'last_purchase',max(invoice_date) filter(where not cancelled),'next_payment',min(reminder_date) filter(where not cancelled and balance>.005)) from invoice_data),
    'filtered_count',(select count(*) from filtered),
    'invoices',coalesce((select jsonb_agg(jsonb_build_object('reference',reference,'invoice_number',invoice_number,'invoice_date',invoice_date,'seller',seller,'report_month',report_month,'sale',sale,'paid',paid,'balance',balance,'cancelled',cancelled,'overdue',overdue,'reminder_date',reminder_date,'calendar_comment',calendar_comment,'payments',payments) order by invoice_date desc,reference desc) from page),'[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke all on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text) from public,anon;
grant execute on function public.list_customer_invoice_history(uuid,integer,integer,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
