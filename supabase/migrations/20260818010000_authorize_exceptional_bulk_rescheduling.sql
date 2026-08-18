begin;

create or replace function public.enterprise_preview_bulk_invoice_rescheduling()
returns jsonb language sql stable security definer set search_path='' as $$
with raw as (
  select f.ref_fact,t.customer_id,c.name customer,c.commercial_name,f.fecha invoice_date,
    c.payment_term_days,r.payment_date current_date,r.date_source,r.updated_at reminder_updated_at,
    case when c.payment_term_days>0 then public.next_weekday(f.fecha+c.payment_term_days) end expected_date,
    count(rv.*)::integer monthly_rows,
    coalesce(bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA'),false) cancelled,
    f.venta-coalesce(sum((select coalesce(sum(value::numeric),0)
      from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0) balance
  from public.invoice_payment_terms t
  join public.facturas_maestras f on f.organization_id=t.organization_id and f.ref_fact=t.factura_id
  join public.billing_customers c on c.organization_id=t.organization_id and c.id=t.customer_id
  left join public.reportes_ventas rv on rv.organization_id=t.organization_id and rv.ref_fact=t.factura_id
  left join public.payment_reminders r on r.organization_id=t.organization_id and r.factura_id=t.factura_id
  where t.organization_id=public.require_current_organization_id() and t.active and c.configuration_active
  group by f.ref_fact,t.customer_id,c.name,c.commercial_name,f.fecha,c.payment_term_days,
    r.payment_date,r.date_source,r.updated_at,f.venta
), classified as (
  select raw.*,(current_date-expected_date) difference_days,
    case when monthly_rows=0 or cancelled or balance<=0.005 then 'excluded'
      when payment_term_days=0 then 'zero_term'
      when payment_term_days is null then 'missing_term'
      when current_date is null then 'missing_reminder'
      when current_date=expected_date then 'already_correct'
      when date_source='manual' then 'manual_review'
      when date_source is null or date_source not in ('customer_term','invoice_exception','term_recalculation') then 'manual_review'
      when abs(current_date-expected_date)<=public.bulk_schedule_tolerance_days() then 'safe_to_update'
      else 'manual_review' end classification,
    case when monthly_rows=0 then 'monthly_row_missing' when cancelled then 'cancelled'
      when balance<=0.005 then 'paid' when payment_term_days=0 then 'zero_term'
      when payment_term_days is null then 'payment_term_missing'
      when current_date is null then 'missing_reminder' when current_date=expected_date then 'already_correct'
      when date_source='manual' then 'manual_date'
      when date_source is null or date_source not in ('customer_term','invoice_exception','term_recalculation') then 'unknown_source'
      when abs(current_date-expected_date)>public.bulk_schedule_tolerance_days() then 'outside_tolerance'
      else 'within_tolerance' end reason
  from raw
), items as (
  select *,md5(concat_ws('|',ref_fact,invoice_date::text,coalesce(payment_term_days::text,'NULL'),
    coalesce(current_date::text,'NULL'),coalesce(date_source,'NULL'),
    coalesce(reminder_updated_at::text,'NULL'),balance::text,cancelled::text,monthly_rows::text)) version_token
  from classified
), payload as (
  select *,jsonb_build_object('customer_id',customer_id,'customer',customer,
    'commercial_name',commercial_name,'ref_fact',ref_fact,'invoice_date',invoice_date,
    'payment_term_days',payment_term_days,'current_scheduled_date',current_date,
    'expected_scheduled_date',expected_date,'difference_days',difference_days,
    'date_source',date_source,'balance',balance,'version_token',version_token,
    'classification',classification,'reason',reason) item from items
), aggregate_payload as (
  select coalesce(jsonb_agg(item order by abs(coalesce(difference_days,0)) desc,ref_fact),'[]'::jsonb) item_list,
    jsonb_build_object(
      'total_reviewed',count(*) filter(where classification not in ('excluded','missing_term','zero_term')),
      'already_correct',count(*) filter(where classification='already_correct'),
      'safe_to_update',count(*) filter(where classification='safe_to_update'),
      'missing_reminders',count(*) filter(where classification='missing_reminder'),
      'manual_review',count(*) filter(where classification='manual_review'),
      'missing_payment_term',count(*) filter(where classification='missing_term'),
      'zero_term_customers',count(distinct customer_id) filter(where classification='zero_term'),
      'zero_term_invoices',count(*) filter(where classification='zero_term'),
      'excluded_paid',count(*) filter(where reason='paid'),
      'excluded_cancelled',count(*) filter(where reason='cancelled'),'errors',0) counts
  from payload
)
select jsonb_build_object('preview_id',md5(item_list::text),'tolerance_days',
  public.bulk_schedule_tolerance_days(),'counts',counts,'items',item_list)
from aggregate_payload;
$$;

create function public.enterprise_apply_safe_bulk_invoice_rescheduling(
  p_request_id uuid,p_preview_id text,p_authorized_exception_refs jsonb,
  p_row_version_tokens jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); state jsonb; item jsonb; result jsonb;
declare updated integer:=0; created integer:=0; exceptional integer:=0; changed integer:=0; failures integer:=0;
declare authorized boolean; affected integer; remaining integer;
begin
  if nullif(p_preview_id,'') is null or jsonb_typeof(p_authorized_exception_refs)<>'array'
     or jsonb_typeof(p_row_version_tokens)<>'object' then raise exception 'invalid bulk authorization'; end if;
  select r.result into result from public.enterprise_requests r where r.organization_id=org
    and r.request_id=p_request_id and r.action='bulk_safe_invoice_rescheduling_v2';
  if found then return result; end if;
  state:=public.enterprise_preview_bulk_invoice_rescheduling();
  for item in select value from jsonb_array_elements(state->'items') loop
    authorized:=exists(select 1 from jsonb_array_elements_text(p_authorized_exception_refs) a(ref)
      where a.ref=item->>'ref_fact');
    if item->>'classification' not in ('safe_to_update','missing_reminder')
       and not (item->>'classification'='manual_review' and authorized) then continue; end if;
    if p_row_version_tokens->>(item->>'ref_fact') is distinct from item->>'version_token' then
      changed:=changed+1; continue;
    end if;
    begin
      if item->>'classification'='missing_reminder' then
        insert into public.payment_reminders(organization_id,user_id,factura_id,payment_date,active,
          notify_three_days,notify_one_day,date_source,calculated_term_days)
        values(org,auth.uid(),item->>'ref_fact',(item->>'expected_scheduled_date')::date,true,
          true,true,'customer_term',(item->>'payment_term_days')::integer)
        on conflict(organization_id,factura_id) where organization_id is not null do nothing;
        get diagnostics affected=row_count;
        if affected=1 then created:=created+1; else changed:=changed+1; end if;
      else
        update public.payment_reminders set payment_date=(item->>'expected_scheduled_date')::date,
          date_source='term_recalculation',calculated_term_days=(item->>'payment_term_days')::integer
        where organization_id=org and factura_id=item->>'ref_fact';
        get diagnostics affected=row_count;
        if affected=1 then
          if authorized then exceptional:=exceptional+1; else updated:=updated+1; end if;
        else changed:=changed+1; end if;
      end if;
    exception when others then failures:=failures+1;
    end;
  end loop;
  state:=public.enterprise_preview_bulk_invoice_rescheduling();
  select count(*)::integer into remaining from jsonb_array_elements(state->'items') value
    where value->>'classification'='manual_review';
  result:=jsonb_build_object('preview_id',state->>'preview_id','tolerance_days',
    public.bulk_schedule_tolerance_days(),'counts',(state->'counts')||jsonb_build_object(
      'updated',updated,'created',created,'authorized_updated',exceptional,
      'unauthorized_exceptions',remaining,'changed_since_preview',changed,'errors',failures),
    'items',state->'items');
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'bulk_safe_invoice_rescheduling_v2',result);
  return result;
end; $$;

revoke all on function public.enterprise_apply_safe_bulk_invoice_rescheduling(uuid,jsonb)
  from public,anon,authenticated;
drop function public.enterprise_apply_safe_bulk_invoice_rescheduling(uuid,jsonb);
revoke all on function public.enterprise_apply_safe_bulk_invoice_rescheduling(uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function public.enterprise_apply_safe_bulk_invoice_rescheduling(uuid,text,jsonb,jsonb)
  to authenticated;
notify pgrst,'reload schema';
commit;
