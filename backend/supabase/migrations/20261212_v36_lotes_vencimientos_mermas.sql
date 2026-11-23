-- v3.6 · Lotes, vencimientos y mermas (docs/INVESTIGACION_RETAIL.md, filas 2, 3 y 4).
-- Aprobada por el propietario el 23/11/2026. SOLO AÑADE: tablas y funciones nuevas, y la recepción de
-- compras acepta también productos por kilo (KGM). No borra ni reescribe datos existentes.
-- Modelo FEFO derivado: lo que queda de cada lote se calcula del stock actual asignándolo primero a los
-- lotes que vencen más tarde (se asume que se vende primero lo que vence antes). Así las ventas, que ya
-- descuentan stock, no necesitan cambios.
begin;

-- 1) Lotes con fecha de vencimiento ---------------------------------------------------------------
create table if not exists public.product_lots (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  receipt_id uuid references public.retail_receipts(id) on delete set null,
  lot_code text check (lot_code is null or char_length(btrim(lot_code)) between 1 and 40),
  expires_on date not null check (expires_on between date '2000-01-01' and date '2100-12-31'),
  quantity numeric(14,2) not null check (quantity > 0 and quantity <= 100000),
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists product_lots_org_exp_idx on public.product_lots(org_id, expires_on);
create index if not exists product_lots_product_idx on public.product_lots(product_id);
create index if not exists product_lots_receipt_idx on public.product_lots(receipt_id);
create index if not exists product_lots_user_idx on public.product_lots(user_id);
alter table public.product_lots enable row level security;
revoke all on public.product_lots from public, anon, authenticated;
grant select on public.product_lots to authenticated;
drop policy if exists product_lots_read on public.product_lots;
create policy product_lots_read on public.product_lots for select to authenticated
  using (private.is_org_member(org_id));

-- 2) Mermas con motivo ------------------------------------------------------------------------------
create table if not exists public.stock_losses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  product_id uuid not null references public.products(id) on delete restrict,
  lot_id uuid references public.product_lots(id) on delete set null,
  quantity numeric(14,2) not null check (quantity > 0 and quantity <= 100000),
  reason text not null check (reason in ('vencido','danado','robo','consumo','canje','otro')),
  note text check (note is null or char_length(note) <= 200),
  unit_cost numeric(14,4),
  stock_before numeric(14,2) not null,
  stock_after numeric(14,2) not null,
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (org_id, request_id)
);
create index if not exists stock_losses_org_created_idx on public.stock_losses(org_id, created_at desc);
create index if not exists stock_losses_product_idx on public.stock_losses(product_id);
create index if not exists stock_losses_lot_idx on public.stock_losses(lot_id);
create index if not exists stock_losses_user_idx on public.stock_losses(user_id);
alter table public.stock_losses enable row level security;
revoke all on public.stock_losses from public, anon, authenticated;
grant select on public.stock_losses to authenticated;
drop policy if exists stock_losses_read on public.stock_losses;
create policy stock_losses_read on public.stock_losses for select to authenticated
  using (private.is_org_member(org_id));

-- Quién puede registrar: dueño, administrador o finanzas (el mismo permiso products_edit), con licencia
-- de escritura y la función de inventario. Las funciones privilegiadas viven en el schema private.
create or replace function private.lots_guard(p_org uuid)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null or p_org is null or not private.can_finance(p_org) then
    raise exception 'Solo el dueño, un administrador o finanzas pueden registrar lotes y mermas'
      using errcode = '42501';
  end if;
  if not private.license_write_ok(p_org) or not private.has_feature(p_org, 'stock') then
    raise exception 'La licencia vigente no permite gestionar inventario' using errcode = '42501';
  end if;
end;
$$;

-- Fechas de vencimiento de una compra ya recibida. Reemplaza las de esa compra (idempotente).
-- p_lots: [{product_id, expires_on 'YYYY-MM-DD', quantity, lot_code?}]
create or replace function private.retail_set_lots_impl(p_org uuid, p_receipt uuid, p_lots jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_count integer := 0;
begin
  perform private.lots_guard(p_org);
  if not exists (select 1 from public.retail_receipts r where r.id = p_receipt and r.org_id = p_org) then
    raise exception 'Compra ajena o inexistente' using errcode = '42501';
  end if;
  if p_lots is null or jsonb_typeof(p_lots) <> 'array' or jsonb_array_length(p_lots) > 100 then
    raise exception 'Lista de lotes inválida' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_lots) e(x)
    where jsonb_typeof(e.x) <> 'object'
       or coalesce(e.x->>'product_id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or coalesce(e.x->>'expires_on','') !~ '^\d{4}-\d{2}-\d{2}$'
       or jsonb_typeof(e.x->'quantity') <> 'number'
       or (e.x->>'quantity')::numeric <= 0
       or (e.x->>'quantity')::numeric <> round((e.x->>'quantity')::numeric, 2)
       or char_length(coalesce(e.x->>'lot_code','')) > 40
  ) then
    raise exception 'Producto, fecha o cantidad de lote inválida' using errcode = '22023';
  end if;
  -- Cada producto debe estar en la compra y sus lotes no pueden sumar más de lo recibido.
  if exists (
    select 1 from (
      select (e.x->>'product_id')::uuid pid, sum((e.x->>'quantity')::numeric) q
      from jsonb_array_elements(p_lots) e(x) group by 1
    ) l
    left join public.retail_receipt_items i on i.receipt_id = p_receipt and i.product_id = l.pid
    where i.product_id is null or l.q > i.quantity
  ) then
    raise exception 'Los lotes deben ser de productos de esta compra y no superar lo recibido' using errcode = '22023';
  end if;
  delete from public.product_lots where org_id = p_org and receipt_id = p_receipt;
  insert into public.product_lots(org_id, product_id, receipt_id, lot_code, expires_on, quantity, user_id)
  select p_org, (e.x->>'product_id')::uuid, p_receipt, nullif(btrim(e.x->>'lot_code'), ''),
         (e.x->>'expires_on')::date, (e.x->>'quantity')::numeric(14,2), (select auth.uid())
  from jsonb_array_elements(p_lots) e(x);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Lote suelto: mercadería que ya estaba en el anaquel (sin compra registrada).
create or replace function private.product_lot_add_impl(p_org uuid, p_product uuid, p_expires date, p_quantity numeric, p_code text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  perform private.lots_guard(p_org);
  if not exists (select 1 from public.products p where p.id = p_product and p.org_id = p_org and p.active) then
    raise exception 'Producto ajeno o inactivo' using errcode = '42501';
  end if;
  if p_expires is null or p_quantity is null or p_quantity <= 0 or p_quantity > 100000 or p_quantity <> round(p_quantity, 2)
     or char_length(coalesce(p_code,'')) > 40 then
    raise exception 'Fecha o cantidad inválida' using errcode = '22023';
  end if;
  insert into public.product_lots(org_id, product_id, lot_code, expires_on, quantity, user_id)
  values (p_org, p_product, nullif(btrim(coalesce(p_code,'')), ''), p_expires, p_quantity, (select auth.uid()))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function private.product_lot_remove_impl(p_org uuid, p_lot uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  perform private.lots_guard(p_org);
  delete from public.product_lots where id = p_lot and org_id = p_org;
  return found;
end;
$$;

-- Merma: descuenta stock y deja constancia de quién, cuánto, por qué y a qué costo. Idempotente por request_id.
create or replace function private.record_loss_impl(
  p_org uuid, p_request_id uuid, p_product uuid, p_quantity numeric, p_reason text, p_lot uuid, p_note text
)
returns table (loss_id uuid, stock_after numeric, reused boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  v_prev public.stock_losses%rowtype;
  v_before numeric(14,2);
  v_cost numeric;
  v_note text := nullif(btrim(coalesce(p_note,'')), '');
  v_id uuid;
begin
  perform private.lots_guard(p_org);
  if p_request_id is null then raise exception 'Falta el identificador de la solicitud' using errcode = '22023'; end if;
  select * into v_prev from public.stock_losses s where s.org_id = p_org and s.request_id = p_request_id;
  if found then
    if v_prev.product_id <> p_product or v_prev.quantity <> p_quantity or v_prev.user_id <> (select auth.uid()) then
      raise exception 'Esta solicitud ya se usó con otros datos' using errcode = '42501';
    end if;
    return query select v_prev.id, v_prev.stock_after::numeric, true;
    return;
  end if;
  if p_reason is null or p_reason not in ('vencido','danado','robo','consumo','canje','otro') then
    raise exception 'Motivo inválido' using errcode = '22023';
  end if;
  if p_reason = 'otro' and v_note is null then
    raise exception 'Escribe el motivo de la merma' using errcode = '22023';
  end if;
  if char_length(coalesce(v_note,'')) > 200 then raise exception 'La nota admite hasta 200 caracteres' using errcode = '22023'; end if;
  if p_quantity is null or p_quantity <= 0 or p_quantity > 100000 or p_quantity <> round(p_quantity, 2) then
    raise exception 'Cantidad inválida' using errcode = '22023';
  end if;
  if p_lot is not null and not exists (
    select 1 from public.product_lots l where l.id = p_lot and l.org_id = p_org and l.product_id = p_product
  ) then
    raise exception 'El lote no corresponde a este producto' using errcode = '22023';
  end if;
  select p.stock, p.unit_cost into v_before, v_cost from public.products p
   where p.id = p_product and p.org_id = p_org and p.active for update;
  if not found then raise exception 'Producto ajeno o inactivo' using errcode = '42501'; end if;
  if v_before is null then raise exception 'Este producto no controla stock' using errcode = '22023'; end if;
  if p_quantity > v_before then
    raise exception 'La merma supera el stock actual (%)', v_before using errcode = '22023';
  end if;
  update public.products set stock = v_before - p_quantity where id = p_product and org_id = p_org;
  insert into public.stock_losses(org_id, request_id, product_id, lot_id, quantity, reason, note, unit_cost,
                                  stock_before, stock_after, user_id)
  values (p_org, p_request_id, p_product, p_lot, p_quantity, p_reason, v_note, v_cost,
          v_before, v_before - p_quantity, (select auth.uid()))
  returning id into v_id;
  return query select v_id, (v_before - p_quantity)::numeric, false;
end;
$$;

revoke all on function private.lots_guard(uuid), private.retail_set_lots_impl(uuid,uuid,jsonb),
  private.product_lot_add_impl(uuid,uuid,date,numeric,text), private.product_lot_remove_impl(uuid,uuid),
  private.record_loss_impl(uuid,uuid,uuid,numeric,text,uuid,text) from public, anon;
grant execute on function private.lots_guard(uuid), private.retail_set_lots_impl(uuid,uuid,jsonb),
  private.product_lot_add_impl(uuid,uuid,date,numeric,text), private.product_lot_remove_impl(uuid,uuid),
  private.record_loss_impl(uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;

create or replace function public.retail_set_lots(p_org uuid, p_receipt uuid, p_lots jsonb)
returns integer language sql security invoker set search_path = ''
as $$ select private.retail_set_lots_impl(p_org, p_receipt, p_lots) $$;
create or replace function public.product_lot_add(p_org uuid, p_product uuid, p_expires date, p_quantity numeric, p_code text default null)
returns uuid language sql security invoker set search_path = ''
as $$ select private.product_lot_add_impl(p_org, p_product, p_expires, p_quantity, p_code) $$;
create or replace function public.product_lot_remove(p_org uuid, p_lot uuid)
returns boolean language sql security invoker set search_path = ''
as $$ select private.product_lot_remove_impl(p_org, p_lot) $$;
create or replace function public.record_loss(
  p_org uuid, p_request_id uuid, p_product uuid, p_quantity numeric, p_reason text, p_lot uuid default null, p_note text default null
)
returns table (loss_id uuid, stock_after numeric, reused boolean)
language sql security invoker set search_path = ''
as $$ select * from private.record_loss_impl(p_org, p_request_id, p_product, p_quantity, p_reason, p_lot, p_note) $$;

-- Estado de los lotes: lo que queda de cada uno y los días para vencer. Primero se restan las mermas
-- registradas contra el lote; luego el stock actual se reparte desde el lote que vence más tarde (FEFO):
-- si se vendió, se asume que salió lo que vencía antes.
create or replace function public.lot_status(p_org uuid)
returns table (lot_id uuid, product_id uuid, product_name text, unit text, lot_code text, expires_on date,
               quantity numeric, remaining numeric, days_left integer, unit_cost numeric, unit_price numeric)
language sql stable security invoker set search_path = ''
as $$
  with lots as (
    -- Lo que queda de cada lote antes de ventas: su cantidad menos las mermas registradas contra él.
    select l.*, greatest(l.quantity - coalesce((select sum(s.quantity) from public.stock_losses s
                                                where s.lot_id = l.id), 0), 0) as net
    from public.product_lots l
    where l.org_id = p_org and private.is_org_member(p_org)
  )
  select l.id, l.product_id, p.name, p.unit, l.lot_code, l.expires_on, l.quantity,
         greatest(least(l.net,
           coalesce(p.stock, 0) - coalesce(sum(l.net) over (
             partition by l.product_id order by l.expires_on desc, l.created_at desc, l.id desc
             rows between unbounded preceding and 1 preceding), 0)), 0)::numeric(14,2),
         (l.expires_on - private.today_pe())::integer,
         p.unit_cost, p.unit_price
  from lots l
  join public.products p on p.id = l.product_id and p.org_id = l.org_id
  where p.active
$$;

revoke all on function public.retail_set_lots(uuid,uuid,jsonb), public.product_lot_add(uuid,uuid,date,numeric,text),
  public.product_lot_remove(uuid,uuid), public.record_loss(uuid,uuid,uuid,numeric,text,uuid,text),
  public.lot_status(uuid) from public, anon;
grant execute on function public.retail_set_lots(uuid,uuid,jsonb), public.product_lot_add(uuid,uuid,date,numeric,text),
  public.product_lot_remove(uuid,uuid), public.record_loss(uuid,uuid,uuid,numeric,text,uuid,text),
  public.lot_status(uuid) to authenticated;

-- 3) Compras de productos por kilo: la recepción acepta NIU y KGM (antes solo NIU). Mismo cuerpo y firma.
create or replace function private.retail_receive_impl(
  p_org uuid, p_request_id uuid, p_supplier text, p_reference text,
  p_payment_method text, p_items jsonb
)
returns table (receipt_id uuid, total_cents bigint, reused boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_currency text;
  v_existing public.retail_receipts%rowtype;
  v_receipt_id uuid;
  v_hash text;
  v_total bigint := 0;
  v_line_total bigint;
  v_before numeric(14,2);
  v_after numeric(14,2);
  v_expense uuid;
  v_cash_move uuid;
  v_supplier text := btrim(coalesce(p_supplier,''));
  v_reference text := nullif(btrim(coalesce(p_reference,'')),'');
  r record;
begin
  if v_uid is null or p_org is null or p_request_id is null
     or not private.is_org_admin(p_org) then
    raise exception 'Solo el dueño o administrador puede recibir compras de esta empresa'
      using errcode = '42501';
  end if;
  if not private.license_write_ok(p_org) or not private.has_feature(p_org,'stock') then
    raise exception 'La licencia vigente no permite recibir inventario' using errcode = '42501';
  end if;
  if char_length(v_supplier) not between 1 and 120 or char_length(coalesce(v_reference,'')) > 40 then
    raise exception 'Proveedor o comprobante inválido' using errcode = '22023';
  end if;
  if p_payment_method not in ('pendiente','efectivo','yape','plin','tarjeta','transferencia') then
    raise exception 'Medio de pago inválido' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'La compra debe tener entre 1 y 50 líneas' using errcode = '22023';
  end if;

  -- Validate every numeric value and SKU before attempting any data mutation.
  if exists (
    select 1 from jsonb_array_elements(p_items) as e(item)
    where jsonb_typeof(e.item) <> 'object'
       or jsonb_typeof(e.item->'product_id') <> 'string'
       or (e.item->>'product_id') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or jsonb_typeof(e.item->'quantity') <> 'number'
       or jsonb_typeof(e.item->'unit_cost_cents') <> 'number'
       or (e.item->>'quantity')::numeric <= 0
       or (e.item->>'quantity')::numeric > 100000
       or (e.item->>'quantity')::numeric <> round((e.item->>'quantity')::numeric,2)
       or (e.item->>'unit_cost_cents')::numeric < 0
       or (e.item->>'unit_cost_cents')::numeric > 1000000000
       or (e.item->>'unit_cost_cents')::numeric <>
           trunc((e.item->>'unit_cost_cents')::numeric)
  ) then
    raise exception 'Producto, cantidad o costo inválido' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) as e(item)
    group by (e.item->>'product_id') having count(*) > 1
  ) then
    raise exception 'El mismo SKU figura dos veces en la compra' using errcode = '22023';
  end if;

  select o.currency into v_currency from public.organizations o where o.id = p_org;
  if v_currency is null then
    raise exception 'Empresa o moneda no válida' using errcode = '42501';
  end if;
  v_hash := md5(v_supplier || '|' || coalesce(v_reference,'') || '|' ||
                 p_payment_method || '|' || p_items::text);

  insert into public.retail_receipts(
      org_id, request_id, user_id, supplier_name, document_ref,
      payment_method, currency, payload_hash
    )
    values (p_org, p_request_id, v_uid, v_supplier, v_reference,
      p_payment_method, v_currency, v_hash)
    on conflict (org_id, request_id) do nothing;

  select * into v_existing from public.retail_receipts rr
    where rr.org_id = p_org and rr.request_id = p_request_id for update;
  if not found then raise exception 'No se pudo reservar la compra'; end if;
  if v_existing.user_id <> v_uid or v_existing.payload_hash <> v_hash then
    raise exception 'Esta solicitud pertenece a otro usuario o tiene otra información'
      using errcode = '42501';
  end if;
  if v_existing.total_cents > 0 then
    return query select v_existing.id, v_existing.total_cents, true;
    return;
  end if;

  v_receipt_id := v_existing.id;
  for r in
    select (e.item->>'product_id')::uuid as product_id,
      (e.item->>'quantity')::numeric(14,2) as qty,
      (e.item->>'unit_cost_cents')::bigint as unit_cents
      from jsonb_array_elements(p_items) as e(item)
      order by (e.item->>'product_id')::uuid
  loop
    select p.stock into v_before from public.products p
     where p.org_id = p_org and p.id = r.product_id and p.active and p.unit in ('NIU','KGM')
     for update;
    if not found then raise exception 'Producto ajeno, inactivo o servicio: %',
      r.product_id using errcode = '42501'; end if;
    v_before := coalesce(v_before,0);
    v_after := v_before + r.qty;
    if v_after > 10000000 then
      raise exception 'El stock supera el máximo admitido' using errcode = '22023';
    end if;
    v_line_total := round(r.qty * r.unit_cents)::bigint;
    v_total := v_total + v_line_total;
    if v_total > 10000000000 then
      raise exception 'Total de compra excede el máximo' using errcode = '22023';
    end if;
    update public.products set stock = v_after,
      unit_cost = r.unit_cents::numeric / 100
      where org_id = p_org and id = r.product_id;
    insert into public.retail_receipt_items(
      receipt_id, org_id, product_id, quantity, unit_cost_cents, line_total_cents,
      stock_before, stock_after
    ) values (
      v_receipt_id, p_org, r.product_id, r.qty, r.unit_cents, v_line_total,
      v_before, v_after
    );
    insert into public.retail_inventory_events(
      org_id, user_id, product_id, receipt_id, quantity_delta, stock_before, stock_after
    ) values (p_org, v_uid, r.product_id, v_receipt_id, r.qty, v_before, v_after);
  end loop;
  if v_total <= 0 then
    raise exception 'El total debe ser mayor que cero' using errcode = '22023';
  end if;

  if p_payment_method <> 'pendiente' then
    -- Purchase expense recorded ONCE, in the SAME transaction as inventory.
    insert into public.expenses(
      org_id, user_id, spent_on, category, supplier_name,
      doc_number, description, tax, total, currency, source
    ) values (
      p_org, v_uid, private.today_pe(), 'mercaderia', v_supplier,
      v_reference, left('Compra de mercadería ' || v_supplier,200),
      0, v_total::numeric / 100, v_currency, 'manual'
    ) returning id into v_expense;
    if p_payment_method = 'efectivo' then
      if not private.has_feature(p_org,'caja') then
        raise exception 'La licencia no permite registrar la salida de caja' using errcode = '42501';
      end if;
      insert into public.cash_movements(org_id, user_id, day, kind, amount, method, note)
        values(p_org, v_uid, private.today_pe(), 'egreso',
               v_total::numeric / 100, 'efectivo',
               left('Compra ' || v_supplier || ' · ' || coalesce(v_reference,''),200))
        returning id into v_cash_move;
    end if;
  end if;

  update public.retail_receipts
    set total_cents = v_total, expense_id = v_expense,
        cash_move_id = v_cash_move
    where org_id = p_org and request_id = p_request_id;

  return query select v_receipt_id, v_total, false;
end;
$$;
-- 4) Tiempo real: la web y el móvil se refrescan solos al registrar un lote o una merma.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'product_lots') then
      alter publication supabase_realtime add table public.product_lots;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'stock_losses') then
      alter publication supabase_realtime add table public.stock_losses;
    end if;
  end if;
end $$;

comment on table public.product_lots is 'Lotes con vencimiento (v3.6). Lo que queda se deriva del stock: lot_status().';
comment on table public.stock_losses is 'Mermas con motivo, costo y responsable (v3.6). Solo se insertan con record_loss().';

commit;
notify pgrst, 'reload schema';
