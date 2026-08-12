begin;

do $$
declare
  sample public.reportes_ventas%rowtype;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='reportes_ventas'
      and column_name='numeros_recibo' and udt_name='_int8'
  ) then raise exception 'numeros_recibo bigint[] is missing'; end if;

  if exists (
    select 1 from public.reportes_ventas
    where cardinality(numeros_recibo)<>jsonb_array_length(abonos)
       or not public.valid_receipt_numbers(numeros_recibo)
  ) then raise exception 'receipt arrays are invalid or misaligned'; end if;

  select * into sample from public.reportes_ventas limit 1;
  if found and jsonb_array_length(sample.abonos)>0
     and cardinality(sample.numeros_recibo)<>jsonb_array_length(sample.abonos) then
    raise exception 'historical row was not aligned';
  end if;

  if public.valid_receipt_numbers(array[0]::bigint[])
     or public.valid_receipt_numbers(array[-25]::bigint[])
     or public.valid_receipt_numbers(array[9007199254740992]::bigint[]) then
    raise exception 'invalid receipt accepted';
  end if;
  if not public.valid_receipt_numbers(array[4587,9007199254740991]::bigint[])
     or not public.valid_receipt_numbers(array[null,4588]::bigint[]) then
    raise exception 'valid or historical receipt rejected';
  end if;
end $$;

rollback;
