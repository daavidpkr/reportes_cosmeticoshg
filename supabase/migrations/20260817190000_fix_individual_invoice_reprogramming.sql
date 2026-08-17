begin;

create or replace function public.invoice_term_recalculation_state(p_ref_fact text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id();
  invoice public.facturas_maestras%rowtype;
  terms public.invoice_payment_terms%rowtype;
  customer public.billing_customers%rowtype;
  reminder public.payment_reminders%rowtype;
  paid numeric; cancelled boolean; monthly_rows integer; reminder_rows integer;
  effective date;
begin
  if nullif(trim(p_ref_fact),'') is null then
    return jsonb_build_object('status','not_found','reason','invoice_not_found');
  end if;
  select * into invoice from public.facturas_maestras f
    where f.organization_id=org and f.ref_fact=trim(p_ref_fact);
  if not found then
    return jsonb_build_object('status','not_found','reason','invoice_not_found',
      'reference',trim(p_ref_fact));
  end if;
  if invoice.fecha is null then
    return jsonb_build_object('status','not_eligible','reason','invalid_invoice_date',
      'reference',invoice.ref_fact);
  end if;
  select * into terms from public.invoice_payment_terms t
    where t.organization_id=org and t.factura_id=invoice.ref_fact and t.active;
  if not found then
    return jsonb_build_object('status','not_eligible','reason','customer_changed',
      'reference',invoice.ref_fact);
  end if;
  select * into customer from public.billing_customers c
    where c.organization_id=org and c.id=terms.customer_id and c.configuration_active;
  if not found then
    return jsonb_build_object('status','not_eligible','reason','customer_changed',
      'reference',invoice.ref_fact);
  end if;
  if customer.payment_term_days is null then
    return jsonb_build_object('status','not_eligible','reason','payment_term_missing',
      'reference',invoice.ref_fact);
  end if;
  select count(*)::integer,
    coalesce(bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA'),false),
    coalesce(sum((select coalesce(sum(value::numeric),0)
      from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0)
    into monthly_rows,cancelled,paid from public.reportes_ventas rv
    where rv.organization_id=org and rv.ref_fact=invoice.ref_fact;
  if monthly_rows=0 then
    return jsonb_build_object('status','not_eligible','reason','monthly_row_missing',
      'reference',invoice.ref_fact);
  end if;
  if cancelled then
    return jsonb_build_object('status','not_eligible','reason','cancelled',
      'reference',invoice.ref_fact);
  end if;
  if invoice.venta-coalesce(paid,0)<=0.005 then
    return jsonb_build_object('status','not_eligible','reason','paid',
      'reference',invoice.ref_fact);
  end if;
  select count(*)::integer into reminder_rows from public.payment_reminders r
    where r.organization_id=org and r.factura_id=invoice.ref_fact;
  if reminder_rows>1 then
    return jsonb_build_object('status','conflict','reason','reminder_conflict',
      'reference',invoice.ref_fact);
  end if;
  select * into reminder from public.payment_reminders r
    where r.organization_id=org and r.factura_id=invoice.ref_fact;
  effective:=public.next_weekday(invoice.fecha+customer.payment_term_days);
  return jsonb_build_object(
    'status',case when reminder.id is not null and reminder.active
      and reminder.payment_date=effective then 'already_current'
      else 'confirmation_required' end,
    'reason',null,'reference',invoice.ref_fact,'ref_fact',invoice.ref_fact,
    'invoice_date',invoice.fecha,'term_days',customer.payment_term_days,
    'payment_term_days',customer.payment_term_days,
    'current_date',reminder.payment_date,'previous_date',reminder.payment_date,
    'new_date',effective,'scheduled_date',effective,
    'date_source',reminder.date_source,
    'reminder_updated_at',reminder.updated_at,
    'manual_schedule',coalesce(reminder.date_source='manual',false),
    'already_current',reminder.id is not null and reminder.active
      and reminder.payment_date=effective,
    'confirmation_required',false,'updated_count',0,
    'outstanding_balance',invoice.venta-coalesce(paid,0));
end; $$;

create or replace function public.preview_invoice_term_recalculation(p_ref_fact text)
returns jsonb language sql stable security definer set search_path='' as $$
  select public.invoice_term_recalculation_state(p_ref_fact);
$$;

create function public.reprogram_invoice_with_current_term(
  p_request_id uuid,p_ref_fact text,p_expected_term_days integer,
  p_expected_invoice_date date,p_expected_current_date date,
  p_expected_reminder_updated_at timestamptz
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id(); state jsonb; result jsonb;
  current_reminder public.payment_reminders%rowtype; affected integer:=0;
  operation_status text;
begin
  select r.result into result from public.enterprise_requests r
    where r.organization_id=org and r.request_id=p_request_id
      and r.action='reprogram_invoice_current_term';
  if found then return result; end if;

  perform 1 from public.invoice_payment_terms t
    where t.organization_id=org and t.factura_id=trim(p_ref_fact) for update;
  perform 1 from public.billing_customers c
    join public.invoice_payment_terms t
      on t.organization_id=c.organization_id and t.customer_id=c.id
    where t.organization_id=org and t.factura_id=trim(p_ref_fact) for update of c;
  perform 1 from public.facturas_maestras f
    where f.organization_id=org and f.ref_fact=trim(p_ref_fact) for update;
  perform 1 from public.reportes_ventas rv
    where rv.organization_id=org and rv.ref_fact=trim(p_ref_fact) for update;
  select * into current_reminder from public.payment_reminders r
    where r.organization_id=org and r.factura_id=trim(p_ref_fact) for update;

  state:=public.invoice_term_recalculation_state(p_ref_fact);
  if (state->>'status') in ('not_found','not_eligible','conflict') then return state; end if;
  if (state->>'term_days')::integer is distinct from p_expected_term_days
     or (state->>'invoice_date')::date is distinct from p_expected_invoice_date then
    return state||jsonb_build_object('status','confirmation_required',
      'reason','customer_changed','confirmation_required',true);
  end if;
  if (state->>'current_date')::date is distinct from p_expected_current_date
     or (state->>'reminder_updated_at')::timestamptz
        is distinct from p_expected_reminder_updated_at then
    return state||jsonb_build_object('status','confirmation_required',
      'reason','schedule_changed','confirmation_required',true);
  end if;
  if (state->>'already_current')::boolean then
    return state||jsonb_build_object('status','already_current');
  end if;

  if current_reminder.id is null then
    insert into public.payment_reminders(organization_id,user_id,factura_id,
      payment_date,active,notify_three_days,notify_one_day,date_source,
      calculated_term_days)
    values(org,auth.uid(),trim(p_ref_fact),(state->>'new_date')::date,true,true,true,
      'term_recalculation',(state->>'term_days')::integer)
    on conflict (organization_id,factura_id) where organization_id is not null
      do nothing returning * into current_reminder;
    get diagnostics affected=row_count;
    operation_status:='created';
  else
    update public.payment_reminders set payment_date=(state->>'new_date')::date,
      active=true,date_source='term_recalculation',
      calculated_term_days=(state->>'term_days')::integer
    where id=current_reminder.id and organization_id=org
    returning * into current_reminder;
    get diagnostics affected=row_count;
    operation_status:='updated';
  end if;
  if affected<>1 then
    return state||jsonb_build_object('status','conflict',
      'reason','reminder_conflict','updated_count',0);
  end if;

  update public.payment_notification_events set status='cancelled',
    next_retry_at=null,last_error_code='SCHEDULE_CHANGED',updated_at=clock_timestamp()
  where reminder_id=current_reminder.id
    and status in ('pending','processing','temporary_failure','no_devices');
  insert into public.payment_followups(organization_id,reminder_id,request_id,
    comment,action_type,previous_payment_date,requested_payment_date,
    effective_payment_date,created_by)
  values(org,current_reminder.id,p_request_id,
    'Reprogramada con el plazo actual del cliente','reschedule',
    (state->>'current_date')::date,(state->>'new_date')::date,
    (state->>'new_date')::date,auth.uid());
  result:=state||jsonb_build_object('status',operation_status,'reason',null,
    'updated_count',1,'already_current',false,'confirmation_required',false);
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'reprogram_invoice_current_term',result);
  return result;
exception when unique_violation then
  return coalesce(state,'{}'::jsonb)||jsonb_build_object('status','conflict',
    'reason','reminder_conflict','updated_count',0);
when others then
  return coalesce(state,'{}'::jsonb)||jsonb_build_object('status','conflict',
    'reason','schedule_changed','updated_count',0);
end; $$;

revoke all on function public.reprogram_invoice_with_current_term(
  uuid,text,integer,date,date) from public,anon,authenticated;
drop function public.reprogram_invoice_with_current_term(
  uuid,text,integer,date,date);
revoke all on function public.reprogram_invoice_with_current_term(
  uuid,text,integer,date,date,timestamptz) from public,anon;
grant execute on function public.reprogram_invoice_with_current_term(
  uuid,text,integer,date,date,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
