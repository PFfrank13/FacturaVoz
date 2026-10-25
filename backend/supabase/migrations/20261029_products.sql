-- Catálogo de productos y servicios por empresa (precios guardados para facturar más rápido).
-- Seguro de ejecutar varias veces. Requiere 20261027_multitenant.sql.

create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 200),
  unit_price  numeric(14,2) not null default 0 check (unit_price >= 0 and unit_price <= 10000000),
  unit        text not null default 'NIU' check (unit in ('NIU','ZZ')), -- NIU producto, ZZ servicio
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists idx_products_org on public.products(org_id);
create index if not exists idx_products_user on public.products(user_id);
-- un mismo nombre no se repite dentro de la empresa
create unique index if not exists uq_products_org_name on public.products(org_id, lower(btrim(name)));

alter table public.products enable row level security;

drop policy if exists "products_select" on public.products;
drop policy if exists "products_insert" on public.products;
drop policy if exists "products_update" on public.products;
drop policy if exists "products_delete" on public.products;

create policy "products_select" on public.products for select to authenticated
  using (private.is_org_member(org_id));
create policy "products_insert" on public.products for insert to authenticated
  with check ((select auth.uid()) = user_id and private.is_org_member(org_id));
create policy "products_update" on public.products for update to authenticated
  using (private.is_org_member(org_id))
  with check (private.is_org_member(org_id));
create policy "products_delete" on public.products for delete to authenticated
  using (private.is_org_admin(org_id));

revoke all on public.products from anon, authenticated;
grant select, insert, delete on public.products to authenticated;
-- no se permite mover un producto a otra empresa ni cambiar su autor
grant update (name, unit_price, unit, active) on public.products to authenticated;
