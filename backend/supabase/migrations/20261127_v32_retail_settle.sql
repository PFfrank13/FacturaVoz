-- Plan Básico retail: settle a previously received purchase exactly once.
-- Staging only. Requires 20261126_v32_retail_receive.sql.
-- Do NOT apply to production without E2E tenant isolation and concurrency tests.
begin;

-- Costs and supplier data are sensitive: ordinary organization members should
-- not read them merely by knowing org_id. The owner/admin authorizes receipts.
drop policy if exists retail_receipts_read on public.retail_receipts;
create policy retail_receipts_read on public.retail_receipts
  for select to authenticated using (private.is_org_admin(org_id));
drop policy if exists retail_receipt_items_read on public.retail_receipt_items;
create policy retail_receipt_items_read on public.retail_receipt_items
  for select to authenticated using (private.is_org_admin(org_id));
drop policy if exists retail_inventory_events_read on public.retail_inventory_events;
create policy retail_inventory_events_read on public.retail_inventory_events
  for select to authenticated using (private.is_org_admin(org_id));

-- A settlement is immutable and uniquely tied to an already received delivery.
-- Repeat requests must return the ORIGINAL event and never pay twice.
create table if not exists public.retail_purchase_settlements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid not null,
  receipt_id uuid not null references public.retail_receipts(id) on delete restrict,
  user_id uuid not null references auth.users(id),
  method text not null check (method in ('efectivo','yape','plin','tarjeta','transferencia')),
  evidence text not null default '' check (char_length(evidence) <= 200),
  paid_cents bigint not null check (paid_cents > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  expense_id uuid not null references public.expenses(id) on delete restrict,
  cash_move_id uuid unique references public.cash_movements(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (org_id, request_id),
  unique (receipt_id)
);
create index if not exists retail_purchase_settlements_org_idx
  on public.retail_purchase_settlements(org_id, created_at desc);
alter table public.retail_purchase_settlements enable row level security;
revoke all on public.retail_purchase_settlements from public, anon, authenticated;
grant select on public.retail_purchase_settlements to authenticated;
drop policy if exists retail_purchase_settlements_read on public.retail_purchase_settlements;
create policy retail_purchase_settlements_read on public.retail_purchase_settlements
  for select to authenticated using (private.is_org_admin(org_id));

create or replace function private.retail_settle_impl(
  p_org uuid, p_receipt uuid, p_request_id uuid, p_method text,
  p_evidence text default ''
)
returns table (settlement_id uuid, paid_cents bigint, reused boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_receipt public.retail_receipts%rowtype;
  v_previous public.retail_purchase_settlements%rowtype;
  v_expense uuid;
  v_cash_move uuid;
  v_id uuid;
  v_evidence text := btrim(coalesce(p_evidence,''));
begin
  if v_uid is null or p_org is null or p_receipt is null
     or p_request_id is null or not private.is_org_admin(p_org) then
    raise exception 'No autorizado para pagar compras de esta empresa'
      using errcode = '42501';
  end if;
  if not private.license_write_ok(p_org) or not private.has_feature(p_org,'stock') then
    raise exception 'Tu licencia no permite gestionar compras' using errcode = '42501';
  end if;
  if p_method not in ('efectivo','yape','plin','tarjeta','transferencia')
    or char_length(v_evidence) > 200 then
    raise exception 'Método de pago o referencia inválida' using errcode = '22023';
  end if;
  if p_method = 'efectivo' and not private.has_feature(p_org,'caja') then
    raise exception 'Tu licencia no permite registrar una salida de caja' using errcode = '42501';
  end if;

  -- Serializes different request IDs that attempt to pay the same receipt.
  select * into v_receipt from public.retail_receipts r
    where r.org_id = p_org and r.id = p_receipt for update;
  if not found then
    raise exception 'Compra no encontrada para esta empresa' using errcode = '42501';
  end if;

  select * into v_previous from public.retail_purchase_settlements s
    where s.org_id = p_org and s.request_id = p_request_id for update;
  if found then
    if v_previous.receipt_id <> p_receipt or v_previous.user_id <> v_uid
       or v_previous.method <> p_method
       or v_previous.evidence <> v_evidence then
      raise exception 'Solicitud de pago ya usada con otra operación' using errcode = '42501';
    end if;
    return query select v_previous.id, v_previous.paid_cents, true;
    return;
  end if;

  if v_receipt.payment_method <> 'pendiente' or v_receipt.expense_id is not null then
    raise exception 'La compra ya tiene un pago registrado' using errcode = '23505';
  end if;
  if v_receipt.total_cents <= 0 then
    raise exception 'El recibo aún no está confirmado' using errcode = '22023';
  end if;

  insert into public.expenses(
    org_id, user_id, spent_on, category, supplier_name, doc_number,
    description, tax, total, currency, source
  ) values (
    p_org, v_uid, private.today_pe(), 'mercaderia',
    v_receipt.supplier_name, v_receipt.document_ref,
    left('Pago compra ' || v_receipt.supplier_name, 200),
    0, v_receipt.total_cents::numeric / 100, v_receipt.currency, 'manual'
  ) returning id into v_expense;

  if p_method = 'efectivo' then
    insert into public.cash_movements(org_id, user_id, day, kind, amount, method, note)
      values (
        p_org, v_uid, private.today_pe(), 'egreso',
        v_receipt.total_cents::numeric / 100, 'efectivo',
        left('Pago compra ' || v_receipt.supplier_name || ' · ' || v_evidence, 200)
      ) returning id into v_cash_move;
  end if;

  insert into public.retail_purchase_settlements(
    org_id, request_id, receipt_id, user_id, method, evidence,
    paid_cents, currency, expense_id, cash_move_id
  ) values (
    p_org, p_request_id, p_receipt, v_uid, p_method, v_evidence,
    v_receipt.total_cents, v_receipt.currency, v_expense, v_cash_move
  ) returning id into v_id;

  update public.retail_receipts
    set payment_method = p_method, expense_id = v_expense
    where org_id = p_org and id = p_receipt;
  -- Intentionally does not adjust stock again.

  return query select v_id, v_receipt.total_cents, false;
end;
$$;

revoke all on function private.retail_settle_impl(uuid,uuid,uuid,text,text)
  from public, anon, authenticated;
grant execute on function private.retail_settle_impl(uuid,uuid,uuid,text,text)
  to authenticated;

create or replace function public.retail_settle(
  p_org uuid, p_receipt uuid, p_request_id uuid, p_method text,
  p_evidence text default ''
)
returns table (settlement_id uuid, paid_cents bigint, reused boolean)
language sql security invoker set search_path = ''
as $$
  select * from private.retail_settle_impl(
    p_org, p_receipt, p_request_id, p_method, p_evidence
  );
$$;
revoke all on function public.retail_settle(uuid,uuid,uuid,text,text)
  from public, anon;
grant execute on function public.retail_settle(uuid,uuid,uuid,text,text)
  to authenticated;

comment on function public.retail_settle(uuid,uuid,uuid,text,text) is
  'Full settlement of one previously received retail purchase; idempotent and atomic. Manual transfer confirmation, NOT bank verified. Staging only.';
commit;
notify pgrst, 'reload schema';
