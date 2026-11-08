-- FacturaVoz Basic retail: purchases -> stock -> expenses/cash (staging only).
-- Depends on 20261125 and the historical modules 20261101/20261109/20261111.
-- No updates to licenses, enforcement flags, existing inventory or historical data.
begin;

create table if not exists public.retail_receipts (
  id uuid not null default gen_random_uuid() unique,
  org_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  user_id uuid not null references auth.users(id),
  supplier_name text not null check (char_length(btrim(supplier_name)) between 1 and 120),
  document_ref text check (document_ref is null or char_length(document_ref) <= 40),
  payment_method text not null check (payment_method in
    ('pendiente', 'efectivo', 'yape', 'plin', 'tarjeta', 'transferencia')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_cents bigint not null default 0 check (total_cents between 0 and 10000000000),
  payload_hash text not null,
  expense_id uuid unique references public.expenses(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (org_id, request_id)
);
create index if not exists retail_receipts_org_created_idx
  on public.retail_receipts(org_id, created_at desc);
alter table public.retail_receipts enable row level security;
revoke all on public.retail_receipts from public, anon, authenticated;
grant select on public.retail_receipts to authenticated;
drop policy if exists retail_receipts_read on public.retail_receipts;
create policy retail_receipts_read on public.retail_receipts for select to authenticated
  using (private.is_org_member(org_id));

create table if not exists public.retail_receipt_items (
  receipt_id uuid not null references public.retail_receipts(id) on delete restrict,
  org_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,2) not null check (quantity > 0 and quantity <= 100000),
  unit_cost_cents bigint not null check (unit_cost_cents between 0 and 1000000000),
  line_total_cents bigint not null check (line_total_cents >= 0),
  stock_before numeric(14,2) not null,
  stock_after numeric(14,2) not null,
  primary key (receipt_id, product_id)
);
create index if not exists retail_receipt_items_org_idx on public.retail_receipt_items(org_id);
alter table public.retail_receipt_items enable row level security;
revoke all on public.retail_receipt_items from public, anon, authenticated;
grant select on public.retail_receipt_items to authenticated;
drop policy if exists retail_receipt_items_read on public.retail_receipt_items;
create policy retail_receipt_items_read on public.retail_receipt_items for select to authenticated
  using (private.is_org_member(org_id));

-- Append-only movements for receipts introduced with this migration.
-- Historical stock and sales are not retroactively represented in this ledger.
create table if not exists public.retail_inventory_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  product_id uuid not null references public.products(id) on delete restrict,
  receipt_id uuid not null references public.retail_receipts(id) on delete restrict,
  quantity_delta numeric(14,2) not null check (quantity_delta > 0),
  stock_before numeric(14,2) not null,
  stock_after numeric(14,2) not null,
  created_at timestamptz not null default now(),
  unique (receipt_id, product_id)
);
create index if not exists retail_inventory_events_org_product_idx
  on public.retail_inventory_events(org_id, product_id, created_at desc);
alter table public.retail_inventory_events enable row level security;
revoke all on public.retail_inventory_events from public, anon, authenticated;
grant select on public.retail_inventory_events to authenticated;
drop policy if exists retail_inventory_events_read on public.retail_inventory_events;
create policy retail_inventory_events_read on public.retail_inventory_events for select to authenticated
  using (private.is_org_member(org_id));

-- Keep elevated privileges outside exposed schemas. Explicitly authorizes JWT user,
-- org owner/admin, valid Hub stock rights and live write access before every mutation.
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
     where p.org_id = p_org and p.id = r.product_id and p.active and p.unit = 'NIU'
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
               left('Compra ' || v_supplier || ' · ' || coalesce(v_reference,''),200));
    end if;
  end if;

  update public.retail_receipts
    set total_cents = v_total, expense_id = v_expense
    where org_id = p_org and request_id = p_request_id;

  return query select v_receipt_id, v_total, false;
end;
$$;

revoke all on function private.retail_receive_impl(uuid,uuid,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function private.retail_receive_impl(uuid,uuid,text,text,text,jsonb)
  to authenticated;

create or replace function public.retail_receive(
  p_org uuid, p_request_id uuid, p_supplier text, p_reference text,
  p_payment_method text, p_items jsonb
)
returns table (receipt_id uuid, total_cents bigint, reused boolean)
language sql security invoker set search_path = ''
as $$
  select * from private.retail_receive_impl(
    p_org, p_request_id, p_supplier, p_reference, p_payment_method, p_items
  );
$$;
revoke all on function public.retail_receive(uuid,uuid,text,text,text,jsonb)
  from public, anon;
grant execute on function public.retail_receive(uuid,uuid,text,text,text,jsonb)
  to authenticated;
comment on function public.retail_receive(uuid,uuid,text,text,text,jsonb) is
  'Staging-first atomic purchase receipt, stock event, paid expense and cash payout. Never use as a surrogate for SUNAT validation.';

commit;
notify pgrst, 'reload schema';
