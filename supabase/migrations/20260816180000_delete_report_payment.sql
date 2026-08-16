begin;

create function public.enterprise_delete_report_payment(
  p_request_id uuid,
  p_row_number integer,
  p_report_name text,
  p_payment_index integer,
  p_expected_amount numeric,
  p_expected_receipt bigint default null,
  p_expected_comment text default ''
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  org uuid := public.require_current_organization_id();
  report_row public.reportes_ventas%rowtype;
  actual_amount numeric;
  actual_receipt bigint;
  actual_comment text;
  payment_count integer;
  i integer;
  new_payments jsonb := '[]'::jsonb;
  new_comments jsonb := '[]'::jsonb;
  new_receipts bigint[] := '{}'::bigint[];
begin
  if p_payment_index is null or p_payment_index < 0 then
    raise exception 'invalid payment index';
  end if;
  if p_expected_amount is null or p_expected_amount <= 0 then
    raise exception 'invalid expected payment';
  end if;
  if exists(
    select 1 from public.enterprise_requests er
    where er.organization_id = org and er.request_id = p_request_id
      and er.action = 'delete_report_payment'
  ) then
    return;
  end if;

  select * into report_row
  from public.reportes_ventas rv
  where rv.organization_id = org
    and rv.nro_fila = p_row_number
    and rv.mes_reporte = p_report_name
  for update;
  if not found then raise exception 'enterprise report row not found'; end if;

  if p_payment_index >= jsonb_array_length(coalesce(report_row.abonos, '[]'::jsonb)) then
    raise exception 'payment already deleted or changed';
  end if;
  actual_amount := (report_row.abonos->>p_payment_index)::numeric;
  actual_receipt := report_row.numeros_recibo[p_payment_index + 1];
  actual_comment := coalesce(report_row.comentarios_abonos->>p_payment_index, '');
  if actual_amount is distinct from p_expected_amount
     or actual_receipt is distinct from p_expected_receipt
     or actual_comment is distinct from trim(coalesce(p_expected_comment, '')) then
    raise exception 'payment already deleted or changed';
  end if;

  payment_count := jsonb_array_length(coalesce(report_row.abonos, '[]'::jsonb));
  if payment_count > 0 then
    for i in 0..payment_count - 1 loop
      if i <> p_payment_index then
        new_payments := new_payments || jsonb_build_array(report_row.abonos->i);
        new_comments := new_comments || jsonb_build_array(
          nullif(coalesce(report_row.comentarios_abonos->>i, ''), '')
        );
        new_receipts := array_append(new_receipts, report_row.numeros_recibo[i + 1]);
      end if;
    end loop;
  end if;
  update public.reportes_ventas rv set
    abonos = new_payments,
    comentarios_abonos = new_comments,
    numeros_recibo = new_receipts
  where rv.organization_id = org
    and rv.nro_fila = p_row_number
    and rv.mes_reporte = p_report_name;

  insert into public.enterprise_requests(organization_id, request_id, action, result)
  values(org, p_request_id, 'delete_report_payment', jsonb_build_object(
    'row_number', p_row_number,
    'report_name', p_report_name,
    'payment_index', p_payment_index
  ));
end;
$$;

revoke all on function public.enterprise_delete_report_payment(
  uuid,integer,text,integer,numeric,bigint,text
) from public, anon;
grant execute on function public.enterprise_delete_report_payment(
  uuid,integer,text,integer,numeric,bigint,text
) to authenticated;

commit;
