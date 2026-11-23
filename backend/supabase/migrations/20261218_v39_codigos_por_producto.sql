-- v3.9 · Varios códigos de barras por producto. El mismo producto (p. ej. «Papel Noble») llega de fábrica con
-- códigos distintos según la presentación o el lote: todos deben vender el mismo producto con su nombre y precio.
-- Un código nunca puede pertenecer a dos productos de la misma empresa (ni como código principal ni adicional).
-- SOLO AÑADE una tabla, dos guardias y una función de consulta. No cambia datos existentes.
begin;

create table if not exists public.product_barcodes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  code text not null check (code ~ '^[0-9A-Za-z\-\.]{4,40}$'),
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (org_id, code)
);
create index if not exists product_barcodes_product_idx on public.product_barcodes(product_id);
create index if not exists product_barcodes_user_idx on public.product_barcodes(user_id);
alter table public.product_barcodes enable row level security;
revoke all on public.product_barcodes from public, anon, authenticated;
grant select, insert, delete on public.product_barcodes to authenticated;
drop policy if exists product_barcodes_read on public.product_barcodes;
create policy product_barcodes_read on public.product_barcodes for select to authenticated using (private.is_org_member(org_id));
drop policy if exists product_barcodes_insert on public.product_barcodes;
create policy product_barcodes_insert on public.product_barcodes for insert to authenticated
  with check (private.can_finance(org_id) and exists (select 1 from public.products p where p.id = product_id and p.org_id = org_id));
drop policy if exists product_barcodes_delete on public.product_barcodes;
create policy product_barcodes_delete on public.product_barcodes for delete to authenticated using (private.can_finance(org_id));

-- Guardias cruzadas: un código adicional no puede ser el principal de otro producto, y al revés.
create or replace function private.product_code_guard()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_name = 'product_barcodes' then
    if exists (select 1 from public.products p where p.org_id = new.org_id and p.barcode = new.code) then
      raise exception 'Ese código de barras ya es de otro producto' using errcode = '23505';
    end if;
  elsif new.barcode is not null and exists (select 1 from public.product_barcodes b where b.org_id = new.org_id and b.code = new.barcode and b.product_id <> new.id) then
    raise exception 'Ese código de barras ya es de otro producto' using errcode = '23505';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_product_barcodes_guard on public.product_barcodes;
create trigger trg_product_barcodes_guard before insert or update on public.product_barcodes
  for each row execute function private.product_code_guard();
drop trigger if exists trg_products_code_guard on public.products;
create trigger trg_products_code_guard before insert or update of barcode on public.products
  for each row execute function private.product_code_guard();

-- ¿De quién es este código? (principal o adicional) — para avisar antes de crear un duplicado.
create or replace function public.product_code_owner(p_org uuid, p_code text)
returns table (product_id uuid, name text, kind text)
language sql stable security invoker set search_path = ''
as $$
  select p.id, p.name, 'principal' from public.products p where p.org_id = p_org and p.barcode = btrim(p_code)
  union all
  select p.id, p.name, 'adicional' from public.product_barcodes b join public.products p on p.id = b.product_id
   where b.org_id = p_org and b.code = btrim(p_code)
  limit 1
$$;
revoke all on function public.product_code_owner(uuid, text) from public, anon;
grant execute on function public.product_code_owner(uuid, text) to authenticated;

select private.install_license_guards();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'product_barcodes') then
    alter publication supabase_realtime add table public.product_barcodes;
  end if;
end $$;

comment on table public.product_barcodes is 'Códigos de barras adicionales de un producto (v3.9). Un código vende siempre el mismo producto.';
commit;
notify pgrst, 'reload schema';
