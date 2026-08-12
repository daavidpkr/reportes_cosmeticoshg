-- Run as a transaction-capable authenticated test session. No fixture survives.
begin;

do $$
declare
  test_org uuid := public.require_current_organization_id();
  test_report text := 'RPC receipt rollback ' || gen_random_uuid()::text;
  test_row integer := 2147483000;
begin
  insert into public.reportes_ventas(
    organization_id,nro_fila,ref_fact,vendedor,esmaltes,abonos,
    numeros_recibo,comentarios_abonos,mes_reporte
  ) values (
    test_org,test_row,'','',0,'[13.50,20]'::jsonb,
    array[null,2002]::bigint[],'["Histórico","Existente"]'::jsonb,test_report
  );

  -- New and historical payments may omit receipts without losing positions.
  perform public.enterprise_save_report_row(
    gen_random_uuid(),test_row,test_report,'','','',null,100,'',0,
    '[9.90,13.50,20]'::jsonb,'[null,null,2002]'::jsonb,
    '[null,"Histórico","Existente"]'::jsonb,''
  );
  if not exists (
    select 1 from public.reportes_ventas
    where organization_id=test_org and nro_fila=test_row
      and mes_reporte=test_report
      and abonos='[9.90,13.50,20]'::jsonb
      and numeros_recibo=array[null,null,2002]::bigint[]
      and comentarios_abonos='[null,"Histórico","Existente"]'::jsonb
  ) then
    raise exception 'valid payment tuple did not persist';
  end if;

  -- Removing the middle tuple keeps the remaining value/receipt/comment pairs.
  perform public.enterprise_save_report_row(
    gen_random_uuid(),test_row,test_report,'','','',null,100,'',0,
    '[9.90,20]'::jsonb,'[null,2002]'::jsonb,
    '[null,"Existente"]'::jsonb,''
  );
  if not exists (
    select 1 from public.reportes_ventas
    where organization_id=test_org and nro_fila=test_row
      and mes_reporte=test_report
      and abonos='[9.90,20]'::jsonb
      and numeros_recibo=array[null,2002]::bigint[]
      and comentarios_abonos='[null,"Existente"]'::jsonb
  ) then
    raise exception 'payment tuples became misaligned after deletion';
  end if;

  begin
    perform public.enterprise_save_report_row(
      gen_random_uuid(),test_row,test_report,'','','',null,100,'',0,
      '[9.90,20,3]'::jsonb,'[null,2002,0]'::jsonb,
      '[null,"Existente",null]'::jsonb,''
    );
    raise exception 'zero receipt was accepted';
  exception when raise_exception then
    if sqlerrm <> 'receipt numbers must be positive safe integers' then
      raise;
    end if;
  end;
end $$;

rollback;
