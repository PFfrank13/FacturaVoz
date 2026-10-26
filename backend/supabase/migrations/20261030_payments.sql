-- Cobros: fecha de vencimiento por factura y pagos (parciales o totales) con saldo pendiente.
-- Seguro de ejecutar varias veces. Requiere 20261027_multitenant.sql.

alter table public.invoices add column if not exists due_date date;
alter table public.invoices drop constraint if exists invoices_due_date_chk;
alter table public.invoices add constraint invoices_due_date_chk check (due_date is null or due_date >= issue_date);

create table if not exists public.payments (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  invoice_id  uuid not null references public.invoices(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  amount      numeric(14,2) not null check (amount > 0 and amount <= 100000000),
  paid_on     date not null default ((now() at time zone 'America/Lima')::date),
  method      text not null default 'efectivo' check (method in ('efectivo','yape','plin','transferencia','tarjeta','otro')),
  note        text check (note is null or char_length(note) <= 200),
  created_at  timestamptz not null default now()
);

create index if not exists idx_payments_invoice on public.payments(invoice_id);
create index if not exists idx_payments_org on public.payments(org_id);
create index if not exists idx_payments_user on public.payments(user_id);

alter table public.payments enable row level security;

drop policy if exists "payments_select" on public.payments;
drop policy if exists "payments_insert" on public.payments;
drop policy if exists "payments_delete" on public.payments;

create policy "payments_select" on public.payments for select to authenticated
  using (private.is_org_member(org_id));

-- Solo se cobra una factura ya emitida (no borrador) y de la misma empresa que el pago.
create policy "payments_insert" on public.payments for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and private.is_org_member(org_id)
    and exists (
      select 1 from public.invoices i
      where i.id = invoice_id and i.org_id = payments.org_id and i.status <> 'draft'
    )
  );

-- Un pago solo se anula (por un administrador) mientras la factura no esté marcada como pagada.
create policy "payments_delete" on public.payments for delete to authenticated
  using (
    private.is_org_admin(org_id)
    and exists (select 1 from public.invoices i where i.id = invoice_id and i.status = 'sent')
  );

revoke all on public.payments from anon, authenticated;
grant select, insert, delete on public.payments to authenticated;
-- los pagos no se editan: se anulan y se vuelven a registrar
