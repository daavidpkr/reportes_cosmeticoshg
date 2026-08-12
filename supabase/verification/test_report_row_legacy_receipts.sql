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

  -- The unchanged receipt-less legacy payment may move when a valid new one is
  -- inserted. This proves the comparison does not rely on array position.
  perform public.enterprise_save_report_row(
    gen_random_uuid(),test_row,test_report,'','','',null,100,'',0,
    '[7,13.50,20]'::jsonb,'[7007,null,2002]'::jsonb,
    '["Nuevo","Histórico","Existente"]'::jsonb,''
  );
  if not exists (
    select 1 from public.reportes_ventas
    where organization_id=test_org and nro_fila=test_row
      and mes_reporte=test_report
      and abonos='[7,13.50,20]'::jsonb
      and numeros_recibo=array[7007,null,2002]::bigint[]
  ) then
    raise exception 'valid payment tuple did not persist';
  end if;

  begin
    perform public.enterprise_save_report_row(
      gen_random_uuid(),test_row,test_report,'','','',null,100,'',0,
      '[7,14,20]'::jsonb,'[7007,null,2002]'::jsonb,
      '["Nuevo","Histórico modificado","Existente"]'::jsonb,''
    );
    raise exception 'modified legacy payment was accepted without a receipt';
  exception when raise_exception then
    if sqlerrm <> 'receipt number is required for new or modified payments' then
      raise;
    end if;
  end;

  begin
    perform public.enterprise_save_report_row(
      gen_random_uuid(),test_row,test_report,'','','',null,100,'',0,
      '[7,13.50,20,3]'::jsonb,'[7007,null,2002,0]'::jsonb,
      '["Nuevo","Histórico","Existente",""]'::jsonb,''
    );
    raise exception 'zero receipt was accepted';
  exception when raise_exception then
    if sqlerrm <> 'receipt numbers must be positive safe integers' then
      raise;
    end if;
  end;
end $$;

rollback;
