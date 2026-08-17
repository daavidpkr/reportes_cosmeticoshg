begin;

alter table public.payment_reminders
  drop constraint payment_reminders_date_source_check;
alter table public.payment_reminders
  add constraint payment_reminders_date_source_check
  check (date_source in ('manual','customer_term','invoice_exception','term_recalculation'));

create function public.invoice_term_recalculation_state(p_ref_fact text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id();
  invoice public.facturas_maestras%rowtype;
  terms public.invoice_payment_terms%rowtype;
  customer public.billing_customers%rowtype;
  reminder public.payment_reminders%rowtype;
  paid numeric; cancelled boolean; row_count integer; effective date;
begin
  if nullif(trim(p_ref_fact),'') is null then raise exception 'invalid invoice reference'; end if;
  select * into invoice from public.facturas_maestras f
    where f.organization_id=org and f.ref_fact=trim(p_ref_fact);
  if not found or invoice.fecha is null then raise exception 'enterprise invoice not found'; end if;
  select * into terms from public.invoice_payment_terms t
    where t.organization_id=org and t.factura_id=invoice.ref_fact and t.active;
  if not found then raise exception 'invoice has no active payment terms'; end if;
  select * into customer from public.billing_customers c
    where c.organization_id=org and c.id=terms.customer_id and c.configuration_active;
  if not found then raise exception 'enterprise customer not found'; end if;
  if customer.payment_term_days is null then raise exception 'customer payment term is pending'; end if;
  select count(*)::integer,
    coalesce(bool_or(upper(trim(coalesce(rv.vendedor,'')))='ANULADA'),false),
    coalesce(sum((select coalesce(sum(value::numeric),0)
      from jsonb_array_elements_text(coalesce(rv.abonos,'[]'::jsonb)))),0)
    into row_count,cancelled,paid from public.reportes_ventas rv
    where rv.organization_id=org and rv.ref_fact=invoice.ref_fact;
  if row_count=0 then raise exception 'invoice has no monthly row'; end if;
  if cancelled then raise exception 'invoice is cancelled'; end if;
  if invoice.venta-coalesce(paid,0)<=0.005 then raise exception 'invoice is paid'; end if;
  select * into reminder from public.payment_reminders r
    where r.organization_id=org and r.factura_id=invoice.ref_fact;
  effective:=public.calculate_enterprise_payment_date(invoice.fecha,customer.payment_term_days);
  return jsonb_build_object(
    'reference',invoice.ref_fact,'invoice_date',invoice.fecha,
    'term_days',customer.payment_term_days,'current_date',reminder.payment_date,
    'new_date',effective,'manual_schedule',coalesce(reminder.date_source='manual',false),
    'already_current',reminder.id is not null and reminder.active and reminder.payment_date=effective,
    'confirmation_required',false,'updated_count',0);
end; $$;

create function public.preview_invoice_term_recalculation(p_ref_fact text)
returns jsonb language sql stable security definer set search_path='' as $$
  select public.invoice_term_recalculation_state(p_ref_fact);
$$;

create function public.reprogram_invoice_with_current_term(
  p_request_id uuid,p_ref_fact text,p_expected_term_days integer,
  p_expected_invoice_date date,p_expected_current_date date
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  org uuid:=public.require_current_organization_id(); state jsonb; result jsonb;
  reminder_id uuid; affected integer;
begin
  select r.result into result from public.enterprise_requests r
    where r.organization_id=org and r.request_id=p_request_id
      and r.action='reprogram_invoice_current_term';
  if found then return result; end if;

  -- Locks serialize a term edit, report update and competing reprogram request.
  perform 1 from public.invoice_payment_terms t
    where t.organization_id=org and t.factura_id=trim(p_ref_fact) for update;
  perform 1 from public.billing_customers c join public.invoice_payment_terms t on t.customer_id=c.id
    where t.organization_id=org and t.factura_id=trim(p_ref_fact) for update of c;
  perform 1 from public.facturas_maestras f
    where f.organization_id=org and f.ref_fact=trim(p_ref_fact) for update;
  perform 1 from public.reportes_ventas rv
    where rv.organization_id=org and rv.ref_fact=trim(p_ref_fact) for update;
  perform 1 from public.payment_reminders r
    where r.organization_id=org and r.factura_id=trim(p_ref_fact) for update;
  state:=public.invoice_term_recalculation_state(p_ref_fact);

  if (state->>'term_days')::integer is distinct from p_expected_term_days
     or (state->>'invoice_date')::date is distinct from p_expected_invoice_date
     or (state->>'current_date')::date is distinct from p_expected_current_date then
    return state||jsonb_build_object('confirmation_required',true);
  end if;
  if (state->>'already_current')::boolean then return state; end if;

  insert into public.payment_reminders(
    organization_id,user_id,factura_id,payment_date,active,notify_three_days,
    notify_one_day,date_source,calculated_term_days)
  values(org,auth.uid(),trim(p_ref_fact),(state->>'new_date')::date,true,true,true,
    'term_recalculation',(state->>'term_days')::integer)
  on conflict (organization_id,factura_id) where organization_id is not null
  do update set payment_date=excluded.payment_date,active=true,
    date_source=excluded.date_source,calculated_term_days=excluded.calculated_term_days
  returning id into reminder_id;
  get diagnostics affected=row_count;
  if affected<>1 then raise exception 'individual reprogramming affected % reminders',affected; end if;

  insert into public.payment_followups(organization_id,reminder_id,request_id,comment,
    action_type,previous_payment_date,requested_payment_date,effective_payment_date,created_by)
  values(org,reminder_id,p_request_id,'Reprogramada con el plazo actual del cliente',
    'reschedule',
    (state->>'current_date')::date,(state->>'new_date')::date,(state->>'new_date')::date,auth.uid())
  on conflict(reminder_id,request_id) do nothing;
  result:=state||jsonb_build_object('updated_count',1,'already_current',false);
  insert into public.enterprise_requests(organization_id,request_id,action,result)
    values(org,p_request_id,'reprogram_invoice_current_term',result);
  return result;
end; $$;

revoke all on function public.invoice_term_recalculation_state(text) from public,anon,authenticated;
revoke all on function public.preview_invoice_term_recalculation(text) from public,anon;
revoke all on function public.reprogram_invoice_with_current_term(uuid,text,integer,date,date) from public,anon;
grant execute on function public.preview_invoice_term_recalculation(text) to authenticated;
grant execute on function public.reprogram_invoice_with_current_term(uuid,text,integer,date,date) to authenticated;
notify pgrst,'reload schema';
commit;
