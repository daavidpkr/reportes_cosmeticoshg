begin;

create function public.bulk_schedule_tolerance_days()
returns integer language sql immutable set search_path='' as $$ select 7 $$;

create function public.enterprise_preview_bulk_invoice_rescheduling()
returns jsonb language sql stable security definer set search_path='' as $$
with raw as (
  select f.ref_fact,t.customer_id,c.name customer,c.commercial_name,f.fecha invoice_date,
    c.payment_term_days,r.payment_date current_date,r.date_source,r.updated_at reminder_updated_at,
    public.next_weekday(f.fecha+c.payment_term_days) expected_date,
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
    case when monthly_rows=0 then 'excluded'
      when cancelled then 'excluded'
      when balance<=0.005 then 'excluded'
      when payment_term_days is null then 'missing_term'
      when current_date is null then 'missing_reminder'
      when current_date=expected_date then 'already_correct'
      when date_source='manual' then 'manual_review'
      when date_source is null or date_source not in ('customer_term','invoice_exception','term_recalculation') then 'manual_review'
      when abs(current_date-expected_date)<=public.bulk_schedule_tolerance_days() then 'safe_to_update'
      else 'manual_review' end classification,
    case when monthly_rows=0 then 'monthly_row_missing' when cancelled then 'cancelled'
      when balance<=0.005 then 'paid' when payment_term_days is null then 'payment_term_missing'
      when current_date is null then 'missing_reminder' when current_date=expected_date then 'already_correct'
      when date_source='manual' then 'manual_date'
      when date_source is null or date_source not in ('customer_term','invoice_exception','term_recalculation') then 'unknown_source'
      when abs(current_date-expected_date)>public.bulk_schedule_tolerance_days() then 'outside_tolerance'
      else 'within_tolerance' end reason
  from raw
), payload as (
  select *,jsonb_build_object('customer_id',customer_id,'customer',customer,
    'commercial_name',commercial_name,'ref_fact',ref_fact,'invoice_date',invoice_date,
    'payment_term_days',payment_term_days,'current_scheduled_date',current_date,
    'expected_scheduled_date',expected_date,'difference_days',difference_days,
    'date_source',date_source,'reminder_updated_at',reminder_updated_at,
    'classification',classification,'reason',reason) item from classified
)
select jsonb_build_object('tolerance_days',public.bulk_schedule_tolerance_days(),
  'counts',jsonb_build_object(
    'total_reviewed',count(*) filter(where classification not in ('excluded','missing_term')),
    'already_correct',count(*) filter(where classification='already_correct'),
    'safe_to_update',count(*) filter(where classification='safe_to_update'),
    'missing_reminders',count(*) filter(where classification='missing_reminder'),
    'manual_review',count(*) filter(where classification='manual_review'),
    'missing_payment_term',count(*) filter(where classification='missing_term'),
    'excluded_paid',count(*) filter(where reason='paid'),
    'excluded_cancelled',count(*) filter(where reason='cancelled'),'errors',0),
  'items',coalesce(jsonb_agg(item order by abs(coalesce(difference_days,0)) desc,ref_fact),'[]'::jsonb))
from payload;
$$;

create function public.enterprise_apply_safe_bulk_invoice_rescheduling(
  p_request_id uuid,p_preview jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); current_state jsonb; item jsonb;
declare snapshot jsonb; result jsonb; target public.payment_reminders%rowtype;
declare updated integer:=0; created integer:=0; changed integer:=0; failures integer:=0;
declare exceptions jsonb:='[]'::jsonb;
begin
  if p_preview is null or jsonb_typeof(p_preview->'items')<>'array' then raise exception 'invalid preview'; end if;
  select r.result into result from public.enterprise_requests r where r.organization_id=org
    and r.request_id=p_request_id and r.action='bulk_safe_invoice_rescheduling';
  if found then return result; end if;
  current_state:=public.enterprise_preview_bulk_invoice_rescheduling();
  for snapshot in select value from jsonb_array_elements(p_preview->'items') loop
    if snapshot->>'classification' not in ('safe_to_update','missing_reminder') then continue; end if;
    select value into item from jsonb_array_elements(current_state->'items')
      where value->>'ref_fact'=snapshot->>'ref_fact';
    if item is null or item->>'classification' is distinct from snapshot->>'classification'
       or item->>'payment_term_days' is distinct from snapshot->>'payment_term_days'
       or item->>'current_scheduled_date' is distinct from snapshot->>'current_scheduled_date'
       or item->>'expected_scheduled_date' is distinct from snapshot->>'expected_scheduled_date'
       or item->>'date_source' is distinct from snapshot->>'date_source' then
      changed:=changed+1;
      exceptions:=exceptions||coalesce(item,snapshot)||jsonb_build_object(
        'classification','changed_since_preview','reason','changed_since_preview');
      continue;
    end if;
    begin
      if item->>'classification'='missing_reminder' then
        insert into public.payment_reminders(organization_id,user_id,factura_id,payment_date,active,
          notify_three_days,notify_one_day,date_source,calculated_term_days)
        values(org,auth.uid(),item->>'ref_fact',(item->>'expected_scheduled_date')::date,true,
          true,true,'customer_term',(item->>'payment_term_days')::integer)
        on conflict(organization_id,factura_id) where organization_id is not null do nothing
        returning * into target;
        if target.id is null then changed:=changed+1; else created:=created+1; end if;
      else
        update public.payment_reminders set payment_date=(item->>'expected_scheduled_date')::date,
          date_source='term_recalculation',calculated_term_days=(item->>'payment_term_days')::integer
        where organization_id=org and factura_id=item->>'ref_fact'
          and payment_date=(item->>'current_scheduled_date')::date
          and date_source=item->>'date_source';
        if found then updated:=updated+1; else changed:=changed+1; end if;
      end if;
    exception when others then failures:=failures+1;
      exceptions:=exceptions||item||jsonb_build_object('classification','manual_review','reason','unknown_source');
    end;
  end loop;
  current_state:=public.enterprise_preview_bulk_invoice_rescheduling();
  result:=jsonb_build_object('tolerance_days',public.bulk_schedule_tolerance_days(),
    'counts',(current_state->'counts')||jsonb_build_object('updated',updated,'created',created,
      'changed_since_preview',changed,'errors',failures),
    'items',coalesce(current_state->'items','[]'::jsonb)||exceptions);
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'bulk_safe_invoice_rescheduling',result);
  return result;
end; $$;

revoke all on function public.bulk_schedule_tolerance_days() from public,anon,authenticated;
revoke all on function public.enterprise_preview_bulk_invoice_rescheduling() from public,anon;
revoke all on function public.enterprise_apply_safe_bulk_invoice_rescheduling(uuid,jsonb) from public,anon;
grant execute on function public.enterprise_preview_bulk_invoice_rescheduling() to authenticated;
grant execute on function public.enterprise_apply_safe_bulk_invoice_rescheduling(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
