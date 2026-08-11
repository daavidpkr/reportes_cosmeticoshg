begin;

create function public.enterprise_save_monthly_report(p_request_id uuid,p_year integer,p_month integer)
returns text language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); declare report_id text;
begin
  if p_year<2000 or p_month not between 1 and 12 then raise exception 'invalid report period'; end if;
  report_id:=p_year::text||'-'||lpad(p_month::text,2,'0');
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return report_id; end if;
  if exists(select 1 from public.reportes_mensuales where id=report_id and organization_id is distinct from org) then
    raise exception 'report id belongs to another organization';
  end if;
  insert into public.reportes_mensuales(id,anio,mes,organization_id)
  values(report_id,p_year,p_month,org)
  on conflict(id) do update set anio=excluded.anio,mes=excluded.mes
  where public.reportes_mensuales.organization_id=org;
  insert into public.enterprise_requests values(org,p_request_id,'save_monthly_report',jsonb_build_object('id',report_id),clock_timestamp());
  return report_id;
end; $$;

create function public.enterprise_delete_monthly_report(p_request_id uuid,p_year integer,p_month integer)
returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); declare report_id text:=p_year::text||'-'||lpad(p_month::text,2,'0');
begin
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  delete from public.reportes_mensuales where id=report_id and organization_id=org;
  insert into public.enterprise_requests values(org,p_request_id,'delete_monthly_report','{}',clock_timestamp());
end; $$;

create function public.enterprise_save_report_row(
  p_request_id uuid,p_row_number integer,p_report_name text,p_ref_fact text,
  p_cliente text,p_commercial_name text,p_invoice_date date,p_sale numeric,
  p_seller text,p_nail_polish numeric,p_payments jsonb,p_payment_comments jsonb
) returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); declare customer_id uuid;
begin
  if p_row_number<1 or nullif(trim(p_report_name),'') is null then raise exception 'invalid report row'; end if;
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  if nullif(trim(p_ref_fact),'') is not null then
    if exists(select 1 from public.facturas_maestras where ref_fact=trim(p_ref_fact) and organization_id is distinct from org) then
      raise exception 'invoice belongs to another organization';
    end if;
    insert into public.facturas_maestras(organization_id,ref_fact,cliente,nombre_comercial,fecha,nro_fact,venta)
    values(org,trim(p_ref_fact),trim(p_cliente),trim(coalesce(p_commercial_name,'')),p_invoice_date,trim(p_ref_fact),p_sale)
    on conflict(ref_fact) do update set cliente=excluded.cliente,nombre_comercial=excluded.nombre_comercial,
      fecha=excluded.fecha,venta=excluded.venta where public.facturas_maestras.organization_id=org;
    insert into public.billing_customers(organization_id,name,commercial_name,updated_by)
    values(org,trim(p_cliente),trim(coalesce(p_commercial_name,'')),auth.uid())
    on conflict(organization_id,normalized_name,normalized_commercial_name)
    do update set updated_at=clock_timestamp(),updated_by=auth.uid() returning id into customer_id;
    insert into public.invoice_payment_terms(organization_id,factura_id,customer_id,active,updated_by)
    values(org,trim(p_ref_fact),customer_id,true,auth.uid())
    on conflict(organization_id,factura_id) do update set customer_id=excluded.customer_id,
      updated_at=clock_timestamp(),updated_by=auth.uid();
    perform public.sync_enterprise_reminder(org,trim(p_ref_fact),p_request_id,'Reprogramación automática por edición de factura');
  end if;
  if exists(select 1 from public.reportes_ventas where nro_fila=p_row_number and mes_reporte=p_report_name
            and organization_id is distinct from org) then raise exception 'report row belongs to another organization'; end if;
  insert into public.reportes_ventas(organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,comentarios_abonos,mes_reporte)
  values(org,p_row_number,trim(p_ref_fact),p_seller,p_nail_polish,p_payments,p_payment_comments,p_report_name)
  on conflict(nro_fila,mes_reporte) do update set ref_fact=excluded.ref_fact,vendedor=excluded.vendedor,
    esmaltes=excluded.esmaltes,abonos=excluded.abonos,comentarios_abonos=excluded.comentarios_abonos
  where public.reportes_ventas.organization_id=org;
  insert into public.enterprise_requests values(org,p_request_id,'save_report_row','{}',clock_timestamp());
end; $$;

create function public.enterprise_delete_report_row(p_request_id uuid,p_row_number integer,p_report_name text)
returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id();
begin
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  delete from public.reportes_ventas where organization_id=org and nro_fila=p_row_number and mes_reporte=p_report_name;
  insert into public.enterprise_requests values(org,p_request_id,'delete_report_row','{}',clock_timestamp());
end; $$;

create function public.enterprise_delete_invoice(p_request_id uuid,p_factura_id text)
returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id();
begin
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  if exists(select 1 from public.payment_reminders where organization_id=org and factura_id=p_factura_id) then
    raise exception 'invoice with reminder cannot be deleted';
  end if;
  delete from public.facturas_maestras where organization_id=org and ref_fact=p_factura_id;
  insert into public.enterprise_requests values(org,p_request_id,'delete_invoice','{}',clock_timestamp());
end; $$;

create function public.enterprise_delete_report_rows(p_request_id uuid,p_report_name text)
returns integer language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); declare affected integer;
begin
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then
    return coalesce((select (result->>'affected')::integer from public.enterprise_requests where organization_id=org and request_id=p_request_id),0);
  end if;
  delete from public.reportes_ventas where organization_id=org and mes_reporte=p_report_name;
  get diagnostics affected=row_count;
  insert into public.enterprise_requests values(org,p_request_id,'delete_report_rows',jsonb_build_object('affected',affected),clock_timestamp());
  return affected;
end; $$;

create function public.enterprise_save_seller(p_request_id uuid,p_old_code text,p_code text,p_name text)
returns boolean language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); declare clean_code text:=upper(trim(p_code));
begin
  if clean_code='' or nullif(trim(p_name),'') is null then raise exception 'invalid seller'; end if;
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return true; end if;
  if p_old_code is null then
    if exists(select 1 from public.vendedores where codigo=clean_code and organization_id is distinct from org) then raise exception 'seller code belongs to another organization'; end if;
    insert into public.vendedores(codigo,nombre,organization_id) values(clean_code,trim(p_name),org);
  else
    update public.vendedores set codigo=clean_code,nombre=trim(p_name)
      where codigo=upper(trim(p_old_code)) and organization_id=org;
    if not found then raise exception 'enterprise seller not found'; end if;
  end if;
  insert into public.enterprise_requests values(org,p_request_id,'save_seller','{}',clock_timestamp());
  return true;
exception when unique_violation then return false;
end; $$;

create function public.enterprise_delete_seller(p_request_id uuid,p_code text)
returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id();
begin
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  delete from public.vendedores where organization_id=org and codigo=upper(trim(p_code));
  insert into public.enterprise_requests values(org,p_request_id,'delete_seller','{}',clock_timestamp());
end; $$;

create or replace function public.register_fcm_device(device_token text,device_platform text default 'android')
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; declare org uuid:=public.require_current_organization_id();
begin
  if length(trim(device_token))<20 or length(device_token)>4096 then raise exception 'invalid token'; end if;
  if device_platform<>'android' then raise exception 'unsupported platform'; end if;
  insert into public.fcm_devices(user_id,organization_id,token,platform,active,last_seen_at)
  values(auth.uid(),org,device_token,device_platform,true,clock_timestamp())
  on conflict(token) do update set user_id=auth.uid(),organization_id=org,platform=excluded.platform,
    active=true,last_seen_at=clock_timestamp(),updated_at=clock_timestamp()
  returning id into result;
  return result;
end; $$;

create or replace function public.deactivate_fcm_device(device_token text)
returns void language sql security definer set search_path='' as $$
  update public.fcm_devices set active=false,updated_at=clock_timestamp()
  where token=device_token and user_id=auth.uid()
    and organization_id=public.require_current_organization_id();
$$;

create function public.enterprise_save_payment_reminder(
  p_request_id uuid,p_factura_id text,p_payment_date date,p_active boolean,
  p_notify_three_days boolean,p_notify_one_day boolean
) returns uuid language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); declare result uuid;
begin
  if not p_notify_three_days and not p_notify_one_day then raise exception 'notice required'; end if;
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then
    return (select (result->>'reminder_id')::uuid from public.enterprise_requests
      where organization_id=org and request_id=p_request_id);
  end if;
  if not exists(select 1 from public.facturas_maestras where organization_id=org and ref_fact=p_factura_id) then raise exception 'enterprise invoice not found'; end if;
  select id into result from public.payment_reminders where organization_id=org and factura_id=p_factura_id for update;
  if found then
    update public.payment_reminders set payment_date=p_payment_date,active=p_active,
      notify_three_days=p_notify_three_days,notify_one_day=p_notify_one_day,
      date_source='manual',calculated_term_days=null where id=result;
  else
    insert into public.payment_reminders(organization_id,user_id,factura_id,payment_date,active,
      notify_three_days,notify_one_day,date_source)
    values(org,auth.uid(),p_factura_id,p_payment_date,p_active,p_notify_three_days,p_notify_one_day,'manual') returning id into result;
  end if;
  insert into public.enterprise_requests values
    (org,p_request_id,'save_payment_reminder',jsonb_build_object('reminder_id',result),clock_timestamp());
  return result;
end; $$;

create function public.enterprise_deactivate_payment_reminder(p_request_id uuid,p_reminder_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id(); declare version uuid;
begin
  if exists(select 1 from public.enterprise_requests where organization_id=org and request_id=p_request_id) then return; end if;
  select schedule_version into version from public.payment_reminders
    where id=p_reminder_id and organization_id=org for update;
  if not found then raise exception 'enterprise reminder not found'; end if;
  update public.payment_reminders set active=false where id=p_reminder_id;
  update public.payment_notification_events set status='cancelled',next_retry_at=null,
    last_error_code='REMINDER_INACTIVE',updated_at=clock_timestamp()
  where reminder_id=p_reminder_id and schedule_version=version
    and status in('pending','processing','temporary_failure','no_devices');
  insert into public.enterprise_requests values(org,p_request_id,'deactivate_payment_reminder','{}',clock_timestamp());
end; $$;

create or replace function public.add_payment_followup(
  p_reminder_id uuid,p_request_id uuid,p_comment text default null,
  p_requested_payment_date date default null
) returns table(followup_id uuid,action_type text,effective_payment_date date)
language plpgsql security definer set search_path='' as $$
declare org uuid:=public.require_current_organization_id();
declare reminder public.payment_reminders%rowtype; declare clean_comment text:=nullif(trim(p_comment),'');
declare effective date; declare kind text; declare inserted_id uuid;
begin
  select * into reminder from public.payment_reminders
    where id=p_reminder_id and organization_id=org for update;
  if not found then raise exception 'enterprise reminder not found'; end if;
  if clean_comment is null and p_requested_payment_date is null then raise exception 'comment or payment date required'; end if;
  select f.id,f.action_type,coalesce(f.effective_payment_date,reminder.payment_date)
    into inserted_id,kind,effective from public.payment_followups f
    where f.reminder_id=p_reminder_id and f.request_id=p_request_id;
  if found then return query select inserted_id,kind,effective; return; end if;
  effective:=coalesce(public.next_weekday(p_requested_payment_date),reminder.payment_date);
  kind:=case when p_requested_payment_date is null then 'comment'
    when clean_comment is null then 'reschedule' else 'comment_and_reschedule' end;
  if p_requested_payment_date is not null and effective is distinct from reminder.payment_date then
    update public.payment_reminders set payment_date=effective,date_source='manual',calculated_term_days=null
      where id=p_reminder_id;
    update public.payment_notification_events set status='cancelled',next_retry_at=null,
      last_error_code='SCHEDULE_CHANGED',updated_at=clock_timestamp()
    where reminder_id=p_reminder_id and schedule_version=reminder.schedule_version
      and status in('pending','processing','temporary_failure','no_devices');
  end if;
  insert into public.payment_followups(organization_id,reminder_id,request_id,comment,action_type,
    previous_payment_date,requested_payment_date,effective_payment_date,created_by)
  values(org,p_reminder_id,p_request_id,clean_comment,kind,
    case when p_requested_payment_date is null then null else reminder.payment_date end,
    p_requested_payment_date,case when p_requested_payment_date is null then null else effective end,auth.uid())
  returning id into inserted_id;
  return query select inserted_id,kind,effective;
end; $$;

revoke all on function public.enterprise_save_monthly_report(uuid,integer,integer) from public,anon;
revoke all on function public.enterprise_delete_monthly_report(uuid,integer,integer) from public,anon;
revoke all on function public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb) from public,anon;
revoke all on function public.enterprise_delete_report_row(uuid,integer,text) from public,anon;
revoke all on function public.enterprise_delete_invoice(uuid,text) from public,anon;
revoke all on function public.enterprise_delete_report_rows(uuid,text) from public,anon;
revoke all on function public.enterprise_save_seller(uuid,text,text,text) from public,anon;
revoke all on function public.enterprise_delete_seller(uuid,text) from public,anon;
revoke all on function public.enterprise_save_payment_reminder(uuid,text,date,boolean,boolean,boolean) from public,anon;
revoke all on function public.enterprise_deactivate_payment_reminder(uuid,uuid) from public,anon;
grant execute on function public.enterprise_save_monthly_report(uuid,integer,integer) to authenticated;
grant execute on function public.enterprise_delete_monthly_report(uuid,integer,integer) to authenticated;
grant execute on function public.enterprise_save_report_row(uuid,integer,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb) to authenticated;
grant execute on function public.enterprise_delete_report_row(uuid,integer,text) to authenticated;
grant execute on function public.enterprise_delete_invoice(uuid,text) to authenticated;
grant execute on function public.enterprise_delete_report_rows(uuid,text) to authenticated;
grant execute on function public.enterprise_save_seller(uuid,text,text,text) to authenticated;
grant execute on function public.enterprise_delete_seller(uuid,text) to authenticated;
grant execute on function public.enterprise_save_payment_reminder(uuid,text,date,boolean,boolean,boolean) to authenticated;
grant execute on function public.enterprise_deactivate_payment_reminder(uuid,uuid) to authenticated;
revoke all on function public.add_payment_followup(uuid,uuid,text,date) from public,anon;
grant execute on function public.add_payment_followup(uuid,uuid,text,date) to authenticated;

commit;
