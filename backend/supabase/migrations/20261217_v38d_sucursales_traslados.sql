-- v3.8d · Sucursales (plan Empresa, función multisucursal): cada local es una empresa de FacturaVoz con su propio
-- stock, comprobantes y caja (como ya funciona «Varias empresas"). Aquí se añade el traslado de mercadería entre
-- locales del mismo dueño: baja el stock en el origen y sube en el destino en una sola transacción, idempotente.
-- docs/INVESTIGACION_RETAIL.md, fila 22. SOLO AÑADE una tabla y funciones.
begin;

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  from_org uuid not null references public.organizations(id) on delete cascade,
  to_org uuid not null references public.organizations(id) on delete cascade,
  from_product uuid not null references public.products(id) on delete restrict,
  to_product uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,2) not null check (quantity > 0 and quantity <= 100000),
  from_stock_after numeric(14,2) not null,
  to_stock_after numeric(14,2) not null,
  note text check (note is null or char_length(note) <= 200),
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (from_org <> to_org)
);
create index if not exists stock_transfers_from_idx on public.stock_transfers(from_org, created_at desc);
create index if not exists stock_transfers_to_idx on public.stock_transfers(to_org, created_at desc);
create index if not exists stock_transfers_from_product_idx on public.stock_transfers(from_product);
create index if not exists stock_transfers_to_product_idx on public.stock_transfers(to_product);
create index if not exists stock_transfers_user_idx on public.stock_transfers(user_id);
alter table public.stock_transfers enable row level security;
revoke all on public.stock_transfers from public, anon, authenticated;
grant select on public.stock_transfers to authenticated;
drop policy if exists stock_transfers_read on public.stock_transfers;
create policy stock_transfers_read on public.stock_transfers for select to authenticated
  using (private.is_org_member(from_org) or private.is_org_member(to_org));

create or replace function private.stock_transfer_impl(
  p_request_id uuid, p_from_org uuid, p_to_org uuid, p_from_product uuid, p_to_product uuid, p_quantity numeric, p_note text
)
returns table (transfer_id uuid, from_stock numeric, to_stock numeric, reused boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  v_prev public.stock_transfers%rowtype;
  v_from numeric(14,2);
  v_to numeric(14,2);
  v_id uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if (select auth.uid()) is null or p_from_org is null or p_to_org is null or p_from_org = p_to_org
     or not private.is_org_admin(p_from_org) or not private.is_org_admin(p_to_org) then
    raise exception 'Debes ser dueño o administrador de ambos locales' using errcode = '42501';
  end if;
  if not private.license_write_ok(p_from_org) or not private.license_write_ok(p_to_org)
     or not private.has_feature(p_from_org, 'multisucursal')
     or not private.has_feature(p_from_org, 'stock') or not private.has_feature(p_to_org, 'stock') then
    raise exception 'La licencia no permite traslados entre locales' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Falta el identificador de la solicitud' using errcode = '22023'; end if;
  select * into v_prev from public.stock_transfers t where t.request_id = p_request_id;
  if found then
    if v_prev.user_id <> (select auth.uid()) or v_prev.from_product <> p_from_product or v_prev.quantity <> p_quantity then
      raise exception 'Esta solicitud ya se usó con otros datos' using errcode = '42501';
    end if;
    return query select v_prev.id, v_prev.from_stock_after::numeric, v_prev.to_stock_after::numeric, true;
    return;
  end if;
  if p_quantity is null or p_quantity <= 0 or p_quantity > 100000 or p_quantity <> round(p_quantity, 2) then
    raise exception 'Cantidad inválida' using errcode = '22023';
  end if;
  if char_length(coalesce(v_note, '')) > 200 then raise exception 'La nota admite hasta 200 caracteres' using errcode = '22023'; end if;
  -- Bloqueo en orden fijo para no cruzarse con otro traslado inverso.
  perform 1 from public.products p where p.id in (p_from_product, p_to_product) order by p.id for update;
  select p.stock into v_from from public.products p where p.id = p_from_product and p.org_id = p_from_org and p.active and p.unit <> 'ZZ';
  if not found then raise exception 'El producto de origen no es de ese local' using errcode = '42501'; end if;
  select p.stock into v_to from public.products p where p.id = p_to_product and p.org_id = p_to_org and p.active and p.unit <> 'ZZ';
  if not found then raise exception 'El producto de destino no es de ese local' using errcode = '42501'; end if;
  if v_from is null then raise exception 'El producto de origen no controla stock' using errcode = '22023'; end if;
  if p_quantity > v_from then raise exception 'No hay stock suficiente en el origen (%)', v_from using errcode = '22023'; end if;
  update public.products set stock = v_from - p_quantity where id = p_from_product;
  update public.products set stock = coalesce(v_to, 0) + p_quantity where id = p_to_product;
  insert into public.stock_transfers(request_id, from_org, to_org, from_product, to_product, quantity, from_stock_after, to_stock_after, note, user_id)
  values (p_request_id, p_from_org, p_to_org, p_from_product, p_to_product, p_quantity, v_from - p_quantity, coalesce(v_to, 0) + p_quantity, v_note, (select auth.uid()))
  returning id into v_id;
  return query select v_id, (v_from - p_quantity)::numeric, (coalesce(v_to, 0) + p_quantity)::numeric, false;
end;
$$;
revoke all on function private.stock_transfer_impl(uuid,uuid,uuid,uuid,uuid,numeric,text) from public, anon;
grant execute on function private.stock_transfer_impl(uuid,uuid,uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.stock_transfer(
  p_request_id uuid, p_from_org uuid, p_to_org uuid, p_from_product uuid, p_to_product uuid, p_quantity numeric, p_note text default null
)
returns table (transfer_id uuid, from_stock numeric, to_stock numeric, reused boolean)
language sql security invoker set search_path = ''
as $$ select * from private.stock_transfer_impl(p_request_id, p_from_org, p_to_org, p_from_product, p_to_product, p_quantity, p_note) $$;
revoke all on function public.stock_transfer(uuid,uuid,uuid,uuid,uuid,numeric,text) from public, anon;
grant execute on function public.stock_transfer(uuid,uuid,uuid,uuid,uuid,numeric,text) to authenticated;

comment on table public.stock_transfers is 'Traslados de mercadería entre locales del mismo dueño (v3.8d, plan Empresa).';
commit;
notify pgrst, 'reload schema';
