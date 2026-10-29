-- FacturaVoz · Migración 17 · Tienda en línea al extremo + productos con foto y código de barras (Fase 4)
-- Productos: código de barras (único por empresa), foto (Storage privado org-media), categoría, descripción,
-- precio por mayor, área de preparación (cocina/barra) y destacados. Tienda: color, modo tienda o carta (mesas),
-- recojo/delivery y pedido mínimo. Los pedidos siguen llegando como cotización "Pedido web" (ahora con mesa,
-- forma de entrega y estado de cocina para las comandas). Idempotente y aditiva. Ejecutar después de 20261107.
begin;

alter table public.products
  add column if not exists barcode text,
  add column if not exists image_path text,
  add column if not exists category text,
  add column if not exists description text,
  add column if not exists wholesale_price numeric(12,2),
  add column if not exists wholesale_min_qty numeric(12,2),
  add column if not exists prep_area text,
  add column if not exists featured boolean not null default false,
  add column if not exists sort integer not null default 0;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'products_store_chk') then
    alter table public.products add constraint products_store_chk check (
      (barcode is null or barcode ~ '^[0-9A-Za-z\-\.]{4,40}$')
      and (image_path is null or char_length(image_path) <= 300)
      and (category is null or char_length(category) <= 60)
      and (description is null or char_length(description) <= 600)
      and (wholesale_price is null or wholesale_price between 0 and 10000000)
      and (wholesale_min_qty is null or wholesale_min_qty between 1 and 100000)
      and (prep_area is null or prep_area in ('cocina', 'barra', 'parrilla', 'postres', 'otro')));
  end if;
end $$;
create unique index if not exists products_org_barcode_key on public.products(org_id, barcode) where barcode is not null;
create index if not exists idx_products_org_category on public.products(org_id, category);
grant update (name, unit_price, unit, active, stock, reorder_point, unit_cost, in_store, barcode, image_path, category,
              description, wholesale_price, wholesale_min_qty, prep_area, featured, sort)
  on public.products to authenticated;

-- Tienda
alter table public.org_store
  add column if not exists theme_color text,
  add column if not exists mode text not null default 'tienda',
  add column if not exists about text,
  add column if not exists pickup boolean not null default true,
  add column if not exists delivery boolean not null default false,
  add column if not exists delivery_note text,
  add column if not exists min_order numeric(12,2),
  add column if not exists show_stock boolean not null default false;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'org_store_v2_chk') then
    alter table public.org_store add constraint org_store_v2_chk check (
      (theme_color is null or theme_color ~ '^#[0-9A-Fa-f]{6}$')
      and mode in ('tienda', 'carta')
      and (about is null or char_length(about) <= 400)
      and (delivery_note is null or char_length(delivery_note) <= 200)
      and (min_order is null or min_order between 0 and 100000));
  end if;
end $$;
grant insert (org_id, slug, enabled, headline, whatsapp, updated_at, theme_color, mode, about, pickup, delivery, delivery_note, min_order, show_stock)
  on public.org_store to authenticated;
grant update (org_id, slug, enabled, headline, whatsapp, updated_at, theme_color, mode, about, pickup, delivery, delivery_note, min_order, show_stock)
  on public.org_store to authenticated;

-- Pedido web con mesa / forma de entrega / estado de cocina
alter table public.quotes
  add column if not exists table_label text,
  add column if not exists fulfillment text,
  add column if not exists delivery_address text,
  add column if not exists kitchen_status text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'quotes_order_chk') then
    alter table public.quotes add constraint quotes_order_chk check (
      (table_label is null or table_label ~ '^[0-9A-Za-z \-]{1,12}$')
      and (fulfillment is null or fulfillment in ('recojo', 'delivery', 'mesa'))
      and (delivery_address is null or char_length(delivery_address) <= 200)
      and (kitchen_status is null or kitchen_status in ('nuevo', 'preparando', 'listo', 'entregado')));
  end if;
end $$;
grant update (status, valid_until, kitchen_status) on public.quotes to authenticated;
create index if not exists idx_quotes_kitchen on public.quotes(org_id, created_at desc) where kitchen_status in ('nuevo', 'preparando', 'listo');

create or replace function public.store_place_order2(
  p_slug text, p_name text, p_phone text, p_note text, p_items jsonb,
  p_table text default null, p_fulfillment text default null, p_address text default null
)
returns table (quote_id uuid, quote_number text, org_id uuid, public_token text, total numeric, currency text, business text, whatsapp text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  r record;
  v_table text := nullif(left(btrim(coalesce(p_table, '')), 12), '');
  v_ful text := case when v_table is not null then 'mesa' when p_fulfillment in ('recojo', 'delivery') then p_fulfillment else 'recojo' end;
  v_addr text := nullif(left(btrim(coalesce(p_address, '')), 200), '');
  s public.org_store;
  v_total numeric;
begin
  select * into s from public.org_store st where st.slug = lower(btrim(coalesce(p_slug, ''))) and st.enabled;
  if not found then raise exception 'Tienda no disponible' using errcode = 'P0002'; end if;
  if v_table is not null and v_table !~ '^[0-9A-Za-z \-]{1,12}$' then raise exception 'Mesa no válida' using errcode = '22023'; end if;
  if v_ful = 'delivery' and (not s.delivery or v_addr is null) then raise exception 'Escribe la dirección de entrega' using errcode = '22023'; end if;

  select * into r from public.store_place_order(p_slug, p_name, p_phone,
    concat_ws(' · ', case when v_table is not null then 'Mesa ' || v_table end,
                     case when v_ful = 'delivery' then 'Delivery: ' || v_addr when v_ful = 'recojo' then 'Recoge en tienda' end,
                     nullif(btrim(coalesce(p_note, '')), '')),
    p_items);
  v_total := r.total;
  if s.min_order is not null and v_ful <> 'mesa' and v_total < s.min_order then
    raise exception 'El pedido mínimo es % %', s.min_order, r.currency using errcode = '22023';
  end if;
  update public.quotes set table_label = v_table, fulfillment = v_ful, delivery_address = v_addr, kitchen_status = 'nuevo'
   where id = r.quote_id;
  return query select r.quote_id, r.quote_number, r.org_id, r.public_token, r.total, r.currency, r.business, r.whatsapp;
end;
$$;
revoke execute on function public.store_place_order2(text, text, text, text, jsonb, text, text, text) from public, anon, authenticated;
grant execute on function public.store_place_order2(text, text, text, text, jsonb, text, text, text) to service_role;

-- Tiempo real para comandas
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'quotes') then
    alter publication supabase_realtime add table public.quotes;
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
