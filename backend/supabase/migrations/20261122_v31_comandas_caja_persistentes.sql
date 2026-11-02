-- FacturaVoz v3.1 / Fase 33+ · Pedidos de caja persistentes en Comandas.
-- Ejecutar UNA SOLA VEZ, después de 20261121_v31_tiempo_real_2.sql.
-- Conserva los pedidos QR: utiliza quotes/quote_items y el flujo existente de cocina.
-- Operación transaccional, controlada por empresa/rubro y segura ante reintentos.
begin;

alter table public.quotes add column if not exists pos_request_id uuid;
create unique index if not exists quotes_org_pos_request_uidx
  on public.quotes (org_id, pos_request_id) where pos_request_id is not null;

alter table public.quote_items add column if not exists kitchen_note text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'quote_items_kitchen_note_length') then
    alter table public.quote_items add constraint quote_items_kitchen_note_length
      check (kitchen_note is null or char_length(kitchen_note) <= 200);
  end if;
end $$;

create or replace function public.create_pos_kitchen_order(
  p_org uuid, p_request_id uuid, p_table text,
  p_tax_rate numeric, p_currency text, p_items jsonb
)
returns table (quote_id uuid, quote_number text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_quote_id uuid;
  v_quote_number text;
  v_table text := nullif(btrim(coalesce(p_table, '')), '');
  v_business_type text;
  v_today date := private.today_pe();
  v_next bigint;
begin
  if (select auth.uid()) is null then
    raise exception 'Inicia sesión para registrar el pedido' using errcode = '28000';
  end if;
  if p_org is null or not private.is_org_member(p_org) then
    raise exception 'La empresa no es válida para este usuario' using errcode = '42501';
  end if;
  select s.business_type into v_business_type from public.org_settings s where s.org_id = p_org;
  if v_business_type is distinct from 'restaurante' then
    raise exception 'Las comandas de cocina solo están disponibles para restaurantes' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'Falta el identificador del pedido' using errcode = '22023';
  end if;
  if v_table is not null and v_table !~ '^[0-9A-Za-z \-]{1,12}$' then
    raise exception 'Mesa no válida (máximo 12 letras/números)' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Agrega entre 1 y 50 productos' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) as line(item)
    where jsonb_typeof(line.item) <> 'object'
       or char_length(btrim(coalesce(line.item->>'note', ''))) > 200
       or char_length(btrim(coalesce(line.item->>'description', ''))) not between 1 and 200
  ) then
    raise exception 'Descripción o nota inválida (máximo 200 caracteres)' using errcode = '22023';
  end if;

  -- Serializar el mismo intento para evitar pedidos repetidos por red lenta / doble toque.
  perform pg_advisory_xact_lock(hashtextextended('fv:pos:' || p_org::text || ':' || p_request_id::text, 0));
  select q.id, q.number into v_quote_id, v_quote_number
  from public.quotes q where q.org_id = p_org and q.pos_request_id = p_request_id;
  if found then
    return query select v_quote_id, v_quote_number;
    return;
  end if;

  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then
    raise exception 'Impuesto no válido' using errcode = '22023';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'Moneda no válida' using errcode = '22023';
  end if;

  -- El mismo candado de numeración de create_quote_impl evita conflictos
  -- con cotizaciones normales y pedidos de QR de esta empresa.
  perform pg_advisory_xact_lock(hashtextextended('quote-number:' || p_org::text, 0));
  select coalesce(max((substring(q.number from '(\d+)$'))::bigint), 0) + 1
    into v_next from public.quotes q
   where q.org_id = p_org and q.number ~ '\d+$';
  v_quote_number := 'COT-' || to_char(v_today, 'YYYY') || '-' || lpad(v_next::text, 4, '0');

  -- Un pedido de caja no debe crear un cliente ficticio en el CRM.
  insert into public.quotes (
    org_id, user_id, number, issue_date, tax_rate, currency, notes,
    transcript, table_label, fulfillment, kitchen_status, pos_request_id
  ) values (
    p_org, (select auth.uid()), v_quote_number, v_today, p_tax_rate, p_currency,
    'Pedido tomado desde caja', 'Pedido de restaurante', v_table,
    case when v_table is null then 'recojo' else 'mesa' end,
    'nuevo', p_request_id
  ) returning id into v_quote_id;

  insert into public.quote_items (quote_id, description, quantity, unit_price, position, kitchen_note)
  select v_quote_id, btrim(it.item ->> 'description'),
         (it.item ->> 'quantity')::numeric, (it.item ->> 'unit_price')::numeric,
         it.ord::integer, nullif(btrim(it.item ->> 'note'), '')
  from jsonb_array_elements(p_items) with ordinality as it(item, ord);

  return query select v_quote_id, v_quote_number;
end;
$$;

revoke all on function public.create_pos_kitchen_order(uuid, uuid, text, numeric, text, jsonb) from public, anon;
grant execute on function public.create_pos_kitchen_order(uuid, uuid, text, numeric, text, jsonb) to authenticated;

-- Asociar la venta final al pedido, manteniendo sus estados de cocina hasta 'entregado'.
create or replace function public.link_pos_kitchen_invoice(p_quote uuid, p_invoice uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_order public.quotes;
  v_invoice_org uuid;
begin
  if (select auth.uid()) is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select * into v_order from public.quotes where id = p_quote for update;
  if not found or v_order.pos_request_id is null or not private.is_org_member(v_order.org_id) then
    raise exception 'Pedido de caja no disponible' using errcode = '42501';
  end if;
  select i.org_id into v_invoice_org from public.invoices i where i.id = p_invoice;
  if v_invoice_org is distinct from v_order.org_id then
    raise exception 'La venta no corresponde a la empresa del pedido' using errcode = '42501';
  end if;
  if v_order.invoice_id = p_invoice then return; end if;
  if v_order.invoice_id is not null then
    raise exception 'El pedido ya está vinculado a otra venta' using errcode = '23505';
  end if;
  update public.quotes set invoice_id = p_invoice, status = 'converted' where id = p_quote;
end;
$$;
revoke all on function public.link_pos_kitchen_invoice(uuid, uuid) from public, anon;
grant execute on function public.link_pos_kitchen_invoice(uuid, uuid) to authenticated;

commit;
notify pgrst, 'reload schema';
