begin;

create function public.record_calendar_payment(
  p_request_id uuid,
  p_reminder_id uuid,
  p_amount numeric,
  p_comment text default '',
  p_receipt_number bigint default null,
  p_pay_in_full boolean default false
) returns table(remaining_balance numeric)
language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  invoice_ref text;
  invoice_total numeric;
  already_paid numeric;
  current_balance numeric;
  target_row record;
  stored jsonb;
begin
  if not coalesce(p_pay_in_full, false) and (p_amount is null or p_amount <= 0) then
    raise exception 'payment must be greater than zero';
  end if;
  if p_receipt_number is not null and p_receipt_number <= 0 then
    raise exception 'invalid receipt number';
  end if;
  if char_length(trim(coalesce(p_comment, ''))) > 500 then
    raise exception 'comment too long';
  end if;

  select er.result into stored
  from public.enterprise_requests er
  where er.organization_id = org and er.request_id = p_request_id
    and er.action = 'record_calendar_payment';
  if found then
    return query select (stored->>'remaining_balance')::numeric;
    return;
  end if;

  select r.factura_id, f.venta into invoice_ref, invoice_total
  from public.payment_reminders r
  join public.facturas_maestras f
    on f.organization_id = r.organization_id and f.ref_fact = r.factura_id
  where r.id = p_reminder_id and r.organization_id = org and r.active
  for update of r, f;
  if not found then raise exception 'pending invoice not found'; end if;

  perform 1 from public.reportes_ventas rv
  where rv.organization_id = org and rv.ref_fact = invoice_ref
  for update;

  select coalesce(sum((select coalesce(sum(value::numeric), 0)
      from jsonb_array_elements_text(coalesce(rv.abonos, '[]'::jsonb)))), 0)
    into already_paid
  from public.reportes_ventas rv
  where rv.organization_id = org and rv.ref_fact = invoice_ref
    and upper(trim(coalesce(rv.vendedor, ''))) <> 'ANULADA';
  current_balance := greatest(invoice_total - already_paid, 0);
  if current_balance <= 0.005 then raise exception 'invoice is already paid'; end if;
  if coalesce(p_pay_in_full, false) then p_amount := current_balance; end if;
  if p_amount > current_balance + 0.005 then raise exception 'payment exceeds current balance'; end if;

  select rv.nro_fila, rv.mes_reporte into target_row
  from public.reportes_ventas rv
  where rv.organization_id = org and rv.ref_fact = invoice_ref
    and upper(trim(coalesce(rv.vendedor, ''))) <> 'ANULADA'
  order by rv.mes_reporte, rv.nro_fila limit 1;
  if not found then raise exception 'report row not found'; end if;

  update public.reportes_ventas rv set
    abonos = coalesce(rv.abonos, '[]'::jsonb) || to_jsonb(p_amount),
    numeros_recibo = array_append(coalesce(rv.numeros_recibo, '{}'::bigint[]), p_receipt_number),
    comentarios_abonos = coalesce(rv.comentarios_abonos, '[]'::jsonb) ||
      to_jsonb(nullif(trim(coalesce(p_comment, '')), ''))
  where rv.organization_id = org and rv.nro_fila = target_row.nro_fila
    and rv.mes_reporte = target_row.mes_reporte;

  current_balance := greatest(current_balance - p_amount, 0);
  stored := jsonb_build_object('remaining_balance', current_balance);
  insert into public.enterprise_requests(organization_id, request_id, action, result)
  values(org, p_request_id, 'record_calendar_payment', stored);
  return query select current_balance;
end;
$$;

revoke all on function public.record_calendar_payment(uuid,uuid,numeric,text,bigint,boolean)
  from public, anon;
grant execute on function public.record_calendar_payment(uuid,uuid,numeric,text,bigint,boolean)
  to authenticated;

commit;
