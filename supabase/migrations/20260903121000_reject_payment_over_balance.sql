-- Server-side guard for stale clients and double taps.  Keep the deployed
-- implementation intact and validate against the canonical invoice before it
-- is allowed to update a report row.
alter function public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text)
  rename to enterprise_save_report_row_unchecked;

create function public.enterprise_save_report_row(
  p_request_id uuid,p_row_number integer,p_report_name text,p_ref_fact text,
  p_cliente text,p_commercial_name text,p_invoice_date date,p_sale numeric,
  p_seller text,p_nail_polish numeric,p_payments jsonb,
  p_payment_receipts jsonb,p_payment_comments jsonb,p_invoice_number text
) returns void language plpgsql security definer set search_path = '' as $$
declare org uuid := public.require_current_organization_id();
declare canonical_sale numeric; proposed_total numeric;
begin
  select venta into canonical_sale from public.facturas_maestras
    where organization_id=org and ref_fact=trim(p_ref_fact) for update;
  select coalesce(sum((value #>> '{}')::numeric),0) into proposed_total
    from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb));
  if canonical_sale is not null and proposed_total > canonical_sale + .005 then
    raise exception 'payment exceeds current invoice balance';
  end if;
  perform public.enterprise_save_report_row_unchecked(
    p_request_id,p_row_number,p_report_name,p_ref_fact,p_cliente,p_commercial_name,
    p_invoice_date,p_sale,p_seller,p_nail_polish,p_payments,p_payment_receipts,
    p_payment_comments,p_invoice_number);
end;
$$;
revoke all on function public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text) from public,anon;
grant execute on function public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text) to authenticated;
notify pgrst, 'reload schema';
