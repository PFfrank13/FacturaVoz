-- FacturaVoz / fase 35 (2026-11-02). Requires all migrations up to 20261122.
-- Execute in STAGING and back up before applying to production.
-- Atomic, idempotent cash sale plus product-ID stock accounting.
-- No automatic matching of product descriptions: a duplicated name MUST NOT decrement two SKUs.

alter table public.invoice_items
  add column if not exists product_id uuid references public.products(id) on delete restrict;
create index if not exists idx_invoice_items_product_id on public.invoice_items(product_id)
  where product_id is not null;
grant update(product_id) on public.invoice_items to authenticated;

-- Guard against linking an invoice of org A to an SKU belonging to org B.
create or replace function private.invoice_item_product_guard()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_org uuid;
begin
  if new.product_id is null then return new; end if;
  select i.org_id into v_org from public.invoices i where i.id = new.invoice_id;
  if not exists (
    select 1 from public.products p where p.id = new.product_id and p.org_id = v_org
  ) then
    raise exception 'El producto no pertenece a la empresa de la venta' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_invoice_item_product_guard on public.invoice_items;
create trigger trg_invoice_item_product_guard
  before insert or update of product_id, invoice_id on public.invoice_items
  for each row execute function private.invoice_item_product_guard();

-- Extend the pre-existing create_invoice RPC so product_id is inserted in the SAME
-- transaction as invoice items. Manual catalog selection can preserve the exact SKU too.
-- Keep the exact original authorization and number reservation semantics.
create or replace function public.create_invoice(
  p_client_name text,
  p_client_tax_id text,
  p_tax_rate numeric,
  p_currency text,
  p_notes text,
  p_transcript text,
  p_items jsonb,
  p_org_id uuid default null
)
returns table (invoice_id uuid, invoice_number text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid := p_org_id;
  v_name text := btrim(coalesce(p_client_name, ''));
  v_tax text := nullif(btrim(coalesce(p_client_tax_id, '')), '');
  v_client uuid;
  v_next bigint;
  v_id uuid;
  v_number text;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '28000';
  end if;
  if v_org is null then
    select m.org_id into v_org from public.organization_members m
    where m.user_id = v_uid order by m.created_at limit 1;
  end if;
  if v_org is null or not private.is_org_member(v_org) then
    raise exception 'Empresa no válida' using errcode = '42501';
  end if;
  if char_length(v_name) not between 1 and 120 then
    raise exception 'Cliente no válido' using errcode = '22023';
  end if;
  if v_tax is not null and char_length(v_tax) > 30 then
    raise exception 'Documento del cliente no válido' using errcode = '22023';
  end if;
  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then
    raise exception 'Impuesto no válido' using errcode = '22023';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'Moneda no válida' using errcode = '22023';
  end if;
  if p_notes is not null and char_length(p_notes) > 500 then
    raise exception 'Notas demasiado largas' using errcode = '22023';
  end if;
  if p_transcript is not null and char_length(p_transcript) > 5000 then
    raise exception 'Transcripción demasiado larga' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Líneas no válidas' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('invoice-number:' || v_org::text, 0));

  select c.id into v_client
  from public.clients c
  where c.org_id = v_org and lower(c.name) = lower(v_name)
  order by c.created_at
  limit 1;

  if v_client is null then
    insert into public.clients (user_id, org_id, name, tax_id)
    values (v_uid, v_org, v_name, v_tax)
    returning clients.id into v_client;
  elsif v_tax is not null then
    update public.clients set tax_id = v_tax where clients.id = v_client and clients.tax_id is null;
  end if;

  select coalesce(max((substring(i.number from '(\d+)$'))::bigint), 0) + 1
  into v_next
  from public.invoices i
  where i.org_id = v_org and i.number ~ '\d+$';

  v_number := 'F-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next::text, 4, '0');

  insert into public.invoices (user_id, org_id, client_id, number, tax_rate, currency, notes, transcript)
  values (v_uid, v_org, v_client, v_number, p_tax_rate, p_currency, p_notes, p_transcript)
  returning invoices.id into v_id;

  insert into public.invoice_items (user_id, invoice_id, description, quantity, unit_price, position, product_id)
  select v_uid, v_id, btrim(e.item ->> 'description'),
         (e.item ->> 'quantity')::numeric, (e.item ->> 'unit_price')::numeric, e.ord::integer,
         nullif(e.item ->> 'product_id', '')::uuid
  from jsonb_array_elements(p_items) with ordinality as e(item, ord);

  return query select v_id, v_number;
end;
$$;

-- Replace the old name-matching deduction (which can hit multiple equal-name SKUs).
create or replace function private.apply_stock_on_issue()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record; v_available numeric; v_match_count integer; v_match_id uuid;
begin
  if old.status = 'draft' and new.status <> 'draft' then
    for r in
      select it.id, it.product_id, it.description, it.quantity as qty
      from public.invoice_items it where it.invoice_id = new.id order by it.id
    loop
      -- Migration compatibility: manually typed item names are resolved ONLY when
      -- the organization has exactly one catalog SKU with that exact name.
      if r.product_id is null then
        select count(*) into v_match_count
          from public.products p
          where p.org_id = new.org_id and p.active and lower(btrim(p.name)) = lower(btrim(r.description));
        if v_match_count > 1 then
          raise exception 'Producto ambiguo, selecciónalo por SKU: %', r.description using errcode = '22023';
        end if;
        if v_match_count = 0 then continue; end if; -- service/nonstock item
        select p.id into v_match_id from public.products p
          where p.org_id = new.org_id and p.active and lower(btrim(p.name)) = lower(btrim(r.description))
          limit 1;
        r.product_id := v_match_id;
      end if;
      select p.stock into v_available
        from public.products p where p.id = r.product_id and p.org_id = new.org_id
        for update;
      if not found then raise exception 'Producto ajeno o inexistente' using errcode = '42501'; end if;
      if v_available is not null then
        if v_available < r.qty then
          raise exception 'Stock insuficiente para producto %', r.product_id using errcode = '22023';
        end if;
        update public.products set stock = stock - r.qty
          where id = r.product_id and org_id = new.org_id;
      end if;
    end loop;
  end if;
  return new;
end $$;
revoke all on function private.apply_stock_on_issue() from public, anon, authenticated;

create table if not exists public.fast_checkout_requests (
  org_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  user_id uuid not null references auth.users(id),
  invoice_id uuid unique references public.invoices(id),
  created_at timestamptz not null default now(),
  primary key (org_id, request_id)
);
create index if not exists idx_fast_checkout_requests_org_created
  on public.fast_checkout_requests(org_id, created_at desc);
alter table public.fast_checkout_requests enable row level security;
revoke all on public.fast_checkout_requests from public, anon, authenticated;
grant select, insert, update(invoice_id) on public.fast_checkout_requests to authenticated;
drop policy if exists fast_checkout_select on public.fast_checkout_requests;
drop policy if exists fast_checkout_insert on public.fast_checkout_requests;
drop policy if exists fast_checkout_update on public.fast_checkout_requests;
create policy fast_checkout_select on public.fast_checkout_requests for select to authenticated
  using (user_id = (select auth.uid()) and private.is_org_member(org_id));
create policy fast_checkout_insert on public.fast_checkout_requests for insert to authenticated
  with check (user_id = (select auth.uid()) and private.is_org_member(org_id) and invoice_id is null);
create policy fast_checkout_update on public.fast_checkout_requests for update to authenticated
  using (user_id = (select auth.uid()) and private.is_org_member(org_id))
  with check (user_id = (select auth.uid()) and private.is_org_member(org_id)
    and (invoice_id is null or exists (
      select 1 from public.invoices i
       where i.id = invoice_id and i.org_id = org_id and i.user_id = (select auth.uid())
    )));

-- Client cannot repoint a completed idempotency key or change its owner/org.
create or replace function private.fast_checkout_request_guard()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.org_id is distinct from old.org_id or new.request_id is distinct from old.request_id
     or new.user_id is distinct from old.user_id then
    raise exception 'Identificador y propietario inmutables' using errcode = '42501';
  end if;
  if old.invoice_id is not null and new.invoice_id is distinct from old.invoice_id then
    raise exception 'Una venta confirmada no puede cambiar de factura' using errcode = '42501';
  end if;
  if new.invoice_id is not null and not exists (
    select 1 from public.invoices i where i.id = new.invoice_id and i.org_id = new.org_id
      and i.user_id = new.user_id and i.status <> 'draft'
      and exists (select 1 from public.payments p
          where p.invoice_id = i.id and p.org_id = new.org_id and p.user_id = new.user_id)
  ) then raise exception 'La factura no tiene un cobro confirmado en la misma empresa' using errcode = '42501'; end if;
  return new;
end $$;
drop trigger if exists trg_fast_checkout_request_guard on public.fast_checkout_requests;
create trigger trg_fast_checkout_request_guard before update on public.fast_checkout_requests
  for each row execute function private.fast_checkout_request_guard();

-- One PostgreSQL transaction: register invoice + lines + their IDs, issue, deduct stock and insert payment.
-- PostgreSQL automatically rolls back every statement if one fails.
-- Return the same invoice for the same (org_id, request_id), including after client timeout.
create or replace function public.fast_checkout_atomic(
  p_org_id uuid, p_request_id uuid, p_items jsonb,
  p_tax_rate numeric, p_currency text, p_method text,
  p_notes text default null
)
returns table (invoice_id uuid, charged numeric, reused boolean)
language plpgsql security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.fast_checkout_requests%rowtype;
  v_invoice uuid;
  v_amount numeric(14,2);
  r record;
begin
  if v_uid is null or p_org_id is null or not private.is_org_member(p_org_id) then
    raise exception 'Empresa o sesión no válida' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Falta identificador de venta' using errcode = '22023'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Líneas de venta no válidas' using errcode = '22023';
  end if;
  if p_method not in ('efectivo','yape','plin','tarjeta','transferencia') then
    raise exception 'Método de pago no admitido' using errcode = '22023';
  end if;
  -- All fast POS items must have an ID; descriptions are NOT an inventory key.
  if exists (
    select 1 from jsonb_array_elements(p_items) as x(item)
    where nullif(x.item->>'product_id', '') is null
  ) then raise exception 'Una línea no tiene product_id' using errcode = '22023'; end if;
  insert into public.fast_checkout_requests(org_id, request_id, user_id)
    values (p_org_id, p_request_id, v_uid)
    on conflict (org_id, request_id) do nothing;
  select * into v_row from public.fast_checkout_requests f
   where f.org_id = p_org_id and f.request_id = p_request_id for update;
  if v_row.user_id <> v_uid then
    raise exception 'Identificador de venta reservado por otro usuario' using errcode = '42501';
  end if;
  if v_row.invoice_id is not null then
    select coalesce(sum(p.amount), 0) into v_amount from public.payments p where p.invoice_id = v_row.invoice_id;
    return query select v_row.invoice_id, v_amount, true;
    return;
  end if;
  for r in select e.value as item from jsonb_array_elements(p_items) e loop
    if not exists (select 1 from public.products p where p.org_id = p_org_id and p.id = (r.item->>'product_id')::uuid and p.active) then
      raise exception 'Producto no válido para esta empresa' using errcode = '42501';
    end if;
  end loop;
  select ci.invoice_id into v_invoice from public.create_invoice(
     'Cliente final', null, p_tax_rate, p_currency, p_notes, 'Venta rápida', p_items, p_org_id
  ) ci;
  if v_invoice is null then raise exception 'No se pudo registrar la venta'; end if;
  update public.invoice_items it
    set product_id = (p_items->(it.position - 1)->>'product_id')::uuid
    where it.invoice_id = v_invoice;
  select round(coalesce(i.amt_total, 0), 2) into v_amount
    from public.invoices i where i.id = v_invoice;
  if v_amount <= 0 then raise exception 'Importe de venta no válido' using errcode = '22023'; end if;
  update public.invoices set status = 'sent' where id = v_invoice and org_id = p_org_id and status = 'draft';
  if not found then raise exception 'La venta no pudo confirmarse'; end if;
  insert into public.payments(org_id, invoice_id, user_id, amount, method)
    values(p_org_id, v_invoice, v_uid, v_amount, p_method);
  update public.fast_checkout_requests set invoice_id = v_invoice
    where org_id = p_org_id and request_id = p_request_id;
  return query select v_invoice, v_amount, false;
end $$;
revoke all on function public.fast_checkout_atomic(uuid,uuid,jsonb,numeric,text,text,text) from public,anon;
grant execute on function public.fast_checkout_atomic(uuid,uuid,jsonb,numeric,text,text,text) to authenticated;

comment on function public.fast_checkout_atomic(uuid,uuid,jsonb,numeric,text,text,text) is
 'Atomic POS sale. Must be called only in staging until integration, RLS and concurrent stock tests pass.';
