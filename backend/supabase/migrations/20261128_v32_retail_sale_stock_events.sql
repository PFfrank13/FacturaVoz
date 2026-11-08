-- Plan Básico: do not block a sale solely because stock is zero.
-- Applies only to FUTURE issued invoices. No historical rows are rewritten.
-- Staging only, after 20261123 and 20261127.
begin;

create table if not exists public.retail_sale_stock_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  invoice_item_id uuid not null unique references public.invoice_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_delta numeric(14,2) not null check (quantity_delta < 0),
  stock_before numeric(14,2) not null,
  stock_after numeric(14,2) not null,
  created_at timestamptz not null default now(),
  check (stock_after = stock_before + quantity_delta)
);
create index if not exists retail_sale_stock_events_org_product_idx
  on public.retail_sale_stock_events(org_id, product_id, created_at desc);
alter table public.retail_sale_stock_events enable row level security;
revoke all on public.retail_sale_stock_events from public,anon,authenticated;
grant select on public.retail_sale_stock_events to authenticated;
drop policy if exists retail_sale_stock_events_read on public.retail_sale_stock_events;
create policy retail_sale_stock_events_read on public.retail_sale_stock_events
  for select to authenticated using (private.is_org_admin(org_id));

-- Replaces the earlier quantity guard. An unavailable SKU is a warning in
-- the UI/report, not a reason to lose a paid sale. Deficit stock remains
-- explicitly negative and may be corrected by a separate audited adjustment.
create or replace function private.apply_stock_on_issue()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_product uuid;
  v_count integer;
  v_before numeric(14,2);
  v_after numeric(14,2);
begin
  if old.status = 'draft' and new.status <> 'draft' then
    for r in
      select it.id as item_id, it.product_id, it.description, it.quantity
        from public.invoice_items it
        where it.invoice_id = new.id
        -- Stable ordering avoids locks inversions when tills sell same SKUs.
        order by it.product_id nulls last, it.id
    loop
      if r.quantity <= 0 or r.quantity > 100000 then
        raise exception 'Cantidad no válida en una línea de venta' using errcode='22023';
      end if;
      v_product := r.product_id;
      if v_product is null then
        select count(*), min(p.id) into v_count, v_product
          from public.products p
          where p.org_id = new.org_id and p.active
            and lower(btrim(p.name)) = lower(btrim(r.description));
        if v_count > 1 then
          raise exception 'Nombre ambiguo; selecciona el SKU: %', r.description using errcode='22023';
        end if;
        if v_count = 0 then continue; end if;
      end if;
      if exists(
        select 1 from public.retail_sale_stock_events e
        where e.invoice_item_id = r.item_id
      ) then
        raise exception 'La salida de inventario de esta línea ya existe'
          using errcode = '23505';
      end if;
      select p.stock into v_before from public.products p
        where p.org_id = new.org_id and p.id = v_product for update;
      if not found then
        raise exception 'Producto ajeno o inexistente' using errcode='42501';
      end if;
      -- A null stock means this SKU is not stock controlled.
      if v_before is null then continue; end if;
      v_after := v_before - r.quantity;
      if v_after < -10000000 or v_after > 10000000 then
        raise exception 'Stock fuera de límites técnicos' using errcode='22023';
      end if;
      update public.products set stock = v_after
        where id = v_product and org_id = new.org_id;
      insert into public.retail_sale_stock_events(
        org_id, invoice_id, invoice_item_id, product_id,
        quantity_delta, stock_before, stock_after
      ) values (
        new.org_id, new.id, r.item_id, v_product,
        -r.quantity, v_before, v_after
      );
    end loop;
  end if;
  return new;
end $$;
revoke all on function private.apply_stock_on_issue() from public,anon,authenticated;

-- A single read-only timeline combining only NEW recorded incoming and
-- outgoing events. Do NOT call this a complete historical kardex.
create or replace view public.retail_stock_flow
with (security_invoker = true) as
  select i.org_id, i.product_id, i.created_at, 'compra'::text as source,
    i.receipt_id as reference_id, i.quantity_delta,
    i.stock_before, i.stock_after
  from public.retail_inventory_events i
  union all
  select s.org_id, s.product_id, s.created_at, 'venta'::text as source,
    s.invoice_id as reference_id, s.quantity_delta,
    s.stock_before, s.stock_after
  from public.retail_sale_stock_events s;
revoke all on public.retail_stock_flow from public,anon;
grant select on public.retail_stock_flow to authenticated;

comment on view public.retail_stock_flow is
  'New retail receipt/sale stock events only; historical adjustments, voids and returns not backfilled. Admin-only via invoker RLS.';

commit;
notify pgrst, 'reload schema';
