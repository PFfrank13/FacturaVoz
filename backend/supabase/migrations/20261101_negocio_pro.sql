-- FacturaVoz · Migración 10 · "Negocio Pro"
-- Cotizaciones · Enlaces de cobro (Yape/Plin/transferencia/Mercado Pago) · Pagos reportados por el cliente ·
-- Cobranza automática · Gastos · Stock con radar de quiebre · Indicadores para el Copiloto de IA.
-- Requiere 20261027…20261031. Idempotente: se puede ejecutar varias veces.
begin;

-- El servidor (service_role) usa algunas utilidades de private desde funciones públicas.
grant usage on schema private to service_role;

-- 0) Utilidades ---------------------------------------------------------------------------------
-- Token público no adivinable (244 bits de azar, solo [0-9a-f], 64 caracteres). Sin extensiones.
create or replace function private.new_token()
returns text
language sql
volatile
set search_path = ''
as $$ select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') $$;

-- Hoy en Perú (la base de datos trabaja en UTC).
create or replace function private.today_pe()
returns date
language sql
stable
set search_path = ''
as $$ select (now() at time zone 'America/Lima')::date $$;

-- Total de una factura con el mismo redondeo que la app y SUNAT (impuesto por línea).
create or replace function private.invoice_total(p_invoice uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(round(it.quantity * it.unit_price, 2)
                      + round(round(it.quantity * it.unit_price, 2) * i.tax_rate / 100, 2)), 0)
  from public.invoices i
  join public.invoice_items it on it.invoice_id = i.id
  where i.id = p_invoice
$$;

create or replace function private.invoice_paid(p_invoice uuid)
returns numeric
language sql
stable
set search_path = ''
as $$ select coalesce(sum(p.amount), 0) from public.payments p where p.invoice_id = p_invoice $$;

-- Marca la factura como pagada cuando los cobros cubren el total (solo desde "sent").
create or replace function private.settle_invoice(p_invoice uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.invoice_paid(p_invoice) >= private.invoice_total(p_invoice) - 0.004 then
    update public.invoices set status = 'paid' where id = p_invoice and status = 'sent';
    return true;
  end if;
  return false;
end;
$$;

-- Corrección: la fecha de emisión por defecto era la de UTC (después de las 19:00 en Lima salía "mañana").
alter table public.invoices alter column issue_date set default ((now() at time zone 'America/Lima')::date);

revoke execute on function private.new_token(), private.today_pe(), private.invoice_total(uuid),
  private.invoice_paid(uuid), private.settle_invoice(uuid) from public, anon;
grant execute on function private.new_token(), private.today_pe(), private.invoice_total(uuid),
  private.invoice_paid(uuid) to authenticated, service_role;
grant execute on function private.settle_invoice(uuid) to service_role;

-- 1) COTIZACIONES -------------------------------------------------------------------------------
create table if not exists public.quotes (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  client_id      uuid references public.clients(id) on delete set null,
  number         text not null check (char_length(number) between 1 and 40),
  issue_date     date not null default ((now() at time zone 'America/Lima')::date),
  valid_until    date,
  status         text not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'rejected', 'converted')),
  tax_rate       numeric(5,2) not null check (tax_rate between 0 and 100),
  currency       text not null check (currency ~ '^[A-Z]{3}$'),
  notes          text check (notes is null or char_length(notes) <= 500),
  transcript     text check (transcript is null or char_length(transcript) <= 5000),
  public_token   text not null unique default private.new_token(),
  responded_at   timestamptz,
  responder_name text check (responder_name is null or char_length(responder_name) <= 120),
  response_note  text check (response_note is null or char_length(response_note) <= 500),
  invoice_id     uuid references public.invoices(id) on delete set null,
  created_at     timestamptz not null default now(),
  constraint quotes_valid_chk check (valid_until is null or valid_until >= issue_date)
);
create unique index if not exists quotes_org_number_key on public.quotes(org_id, number);
create index if not exists idx_quotes_org on public.quotes(org_id, created_at desc);
create index if not exists idx_quotes_user on public.quotes(user_id);
create index if not exists idx_quotes_client on public.quotes(client_id);
create index if not exists idx_quotes_invoice on public.quotes(invoice_id);

create table if not exists public.quote_items (
  id          uuid primary key default gen_random_uuid(),
  quote_id    uuid not null references public.quotes(id) on delete cascade,
  description text not null check (char_length(btrim(description)) between 1 and 200),
  quantity    numeric(12,2) not null check (quantity > 0 and quantity <= 100000),
  unit_price  numeric(12,2) not null check (unit_price >= 0 and unit_price <= 10000000),
  position    integer not null default 0
);
create index if not exists idx_quote_items_quote on public.quote_items(quote_id, position);

alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;

drop policy if exists "quotes_select" on public.quotes;
create policy "quotes_select" on public.quotes for select to authenticated
  using (private.is_org_member(org_id));
drop policy if exists "quotes_update" on public.quotes;
create policy "quotes_update" on public.quotes for update to authenticated
  using (private.is_org_member(org_id)) with check (private.is_org_member(org_id));
drop policy if exists "quotes_delete" on public.quotes;
create policy "quotes_delete" on public.quotes for delete to authenticated
  using (status in ('draft', 'rejected') and ((select auth.uid()) = user_id or private.is_org_admin(org_id)));
drop policy if exists "quote_items_select" on public.quote_items;
create policy "quote_items_select" on public.quote_items for select to authenticated
  using (exists (select 1 from public.quotes q where q.id = quote_id and private.is_org_member(q.org_id)));

-- Escritura solo vía funciones: la app puede cambiar el estado y la vigencia, nada más.
revoke all on public.quotes, public.quote_items from anon, authenticated;
grant select, delete on public.quotes to authenticated;
grant update (status, valid_until) on public.quotes to authenticated;
grant select on public.quote_items to authenticated;

create or replace function private.guard_quote_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'converted' and (new.status is distinct from old.status or new.valid_until is distinct from old.valid_until) then
    raise exception 'La cotización ya se convirtió en factura' using errcode = '42501';
  end if;
  if new.status = 'converted' and new.invoice_id is null then
    raise exception 'Usa "Convertir en factura"' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke execute on function private.guard_quote_update() from public, anon, authenticated;
drop trigger if exists trg_guard_quote_update on public.quotes;
create trigger trg_guard_quote_update before update on public.quotes
  for each row execute function private.guard_quote_update();

create or replace function private.create_quote_impl(
  p_org uuid, p_client_name text, p_client_tax_id text, p_tax_rate numeric, p_currency text,
  p_notes text, p_transcript text, p_items jsonb, p_valid_until date
)
returns table (quote_id uuid, quote_number text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_client_name, ''));
  v_tax text := nullif(btrim(coalesce(p_client_tax_id, '')), '');
  v_client uuid;
  v_next bigint;
  v_id uuid;
  v_number text;
  v_today date := private.today_pe();
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  if p_org is null or not private.is_org_member(p_org) then raise exception 'Empresa no válida' using errcode = '42501'; end if;
  if char_length(v_name) not between 1 and 120 then raise exception 'Cliente no válido' using errcode = '22023'; end if;
  if v_tax is not null and char_length(v_tax) > 30 then raise exception 'Documento del cliente no válido' using errcode = '22023'; end if;
  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then raise exception 'Impuesto no válido' using errcode = '22023'; end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then raise exception 'Moneda no válida' using errcode = '22023'; end if;
  if p_notes is not null and char_length(p_notes) > 500 then raise exception 'Notas demasiado largas' using errcode = '22023'; end if;
  if p_transcript is not null and char_length(p_transcript) > 5000 then raise exception 'Transcripción demasiado larga' using errcode = '22023'; end if;
  if p_valid_until is not null and (p_valid_until < v_today or p_valid_until > v_today + 365) then
    raise exception 'Vigencia no válida' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Líneas no válidas' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('quote-number:' || p_org::text, 0));

  select c.id into v_client from public.clients c
  where c.org_id = p_org and lower(c.name) = lower(v_name) order by c.created_at limit 1;
  if v_client is null then
    insert into public.clients (user_id, org_id, name, tax_id) values (v_uid, p_org, v_name, v_tax)
    returning id into v_client;
  elsif v_tax is not null then
    update public.clients set tax_id = v_tax where id = v_client and tax_id is null;
  end if;

  select coalesce(max((substring(q.number from '(\d+)$'))::bigint), 0) + 1 into v_next
  from public.quotes q where q.org_id = p_org and q.number ~ '\d+$';
  v_number := 'COT-' || to_char(v_today, 'YYYY') || '-' || lpad(v_next::text, 4, '0');

  insert into public.quotes (org_id, user_id, client_id, number, issue_date, valid_until, tax_rate, currency, notes, transcript)
  values (p_org, v_uid, v_client, v_number, v_today, p_valid_until, p_tax_rate, p_currency,
          nullif(btrim(coalesce(p_notes, '')), ''), p_transcript)
  returning id into v_id;

  insert into public.quote_items (quote_id, description, quantity, unit_price, position)
  select v_id, btrim(e.item ->> 'description'), (e.item ->> 'quantity')::numeric, (e.item ->> 'unit_price')::numeric, e.ord::integer
  from jsonb_array_elements(p_items) with ordinality as e(item, ord);

  return query select v_id, v_number;
end;
$$;

-- Convierte la cotización en factura (borrador) con UN toque, sin volver a digitar nada. Idempotente.
create or replace function private.convert_quote_impl(p_quote uuid, p_due_date date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  q public.quotes;
  v_client_name text;
  v_client_tax text;
  v_items jsonb;
  v_inv uuid;
  v_notes text;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select * into q from public.quotes where id = p_quote for update;
  if not found or not private.is_org_member(q.org_id) then raise exception 'Cotización no encontrada' using errcode = '42501'; end if;
  if q.status = 'converted' and q.invoice_id is not null then return q.invoice_id; end if;
  if q.status = 'rejected' then raise exception 'El cliente rechazó esta cotización' using errcode = '22023'; end if;

  select c.name, c.tax_id into v_client_name, v_client_tax from public.clients c where c.id = q.client_id;
  if v_client_name is null then v_client_name := 'Cliente'; end if;
  select jsonb_agg(jsonb_build_object('description', it.description, 'quantity', it.quantity, 'unit_price', it.unit_price)
                   order by it.position)
    into v_items from public.quote_items it where it.quote_id = q.id;
  v_notes := left(coalesce(q.notes || ' · ', '') || 'Según cotización ' || q.number, 500);

  select r.invoice_id into v_inv
  from public.create_invoice(v_client_name, v_client_tax, q.tax_rate, q.currency, v_notes, q.transcript, v_items, q.org_id) as r;

  if p_due_date is not null then
    update public.invoices set due_date = p_due_date where id = v_inv;
  end if;
  update public.quotes set status = 'converted', invoice_id = v_inv where id = q.id;
  return v_inv;
end;
$$;

revoke execute on function private.create_quote_impl(uuid, text, text, numeric, text, text, text, jsonb, date),
  private.convert_quote_impl(uuid, date) from public, anon;
grant execute on function private.create_quote_impl(uuid, text, text, numeric, text, text, text, jsonb, date),
  private.convert_quote_impl(uuid, date) to authenticated;

create or replace function public.create_quote(
  p_org uuid, p_client_name text, p_client_tax_id text, p_tax_rate numeric, p_currency text,
  p_notes text, p_transcript text, p_items jsonb, p_valid_until date default null
)
returns table (quote_id uuid, quote_number text)
language sql security invoker set search_path = ''
as $$ select * from private.create_quote_impl(p_org, p_client_name, p_client_tax_id, p_tax_rate, p_currency, p_notes, p_transcript, p_items, p_valid_until) $$;

create or replace function public.convert_quote(p_quote uuid, p_due_date date default null)
returns uuid
language sql security invoker set search_path = ''
as $$ select private.convert_quote_impl(p_quote, p_due_date) $$;

revoke execute on function public.create_quote(uuid, text, text, numeric, text, text, text, jsonb, date),
  public.convert_quote(uuid, date) from public, anon;
grant execute on function public.create_quote(uuid, text, text, numeric, text, text, text, jsonb, date),
  public.convert_quote(uuid, date) to authenticated;

-- 2) COBROS: medios de pago, enlaces de cobro, pagos reportados, Mercado Pago -------------------
alter table public.payments add column if not exists external_ref text;
create unique index if not exists payments_external_ref_key on public.payments(external_ref) where external_ref is not null;
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check
  check (method in ('efectivo', 'yape', 'plin', 'transferencia', 'tarjeta', 'mercadopago', 'otro'));
alter table public.payments drop constraint if exists payments_external_ref_chk;
alter table public.payments add constraint payments_external_ref_chk check (external_ref is null or char_length(external_ref) <= 80);

-- Medios de cobro que verá el cliente en la página de pago + configuración de cobranza automática.
create table if not exists public.org_pay_settings (
  org_id            uuid primary key references public.organizations(id) on delete cascade,
  yape_phone        text check (yape_phone is null or yape_phone ~ '^9[0-9]{8}$'),
  plin_phone        text check (plin_phone is null or plin_phone ~ '^9[0-9]{8}$'),
  bank_name         text check (bank_name is null or char_length(bank_name) <= 60),
  bank_account      text check (bank_account is null or char_length(bank_account) <= 40),
  bank_cci          text check (bank_cci is null or bank_cci ~ '^[0-9]{20}$'),
  account_holder    text check (account_holder is null or char_length(account_holder) <= 120),
  pay_note          text check (pay_note is null or char_length(pay_note) <= 300),
  mp_enabled        boolean not null default false,          -- lo pone el servidor al guardar el token
  reminders_enabled boolean not null default false,
  reminder_offsets  integer[] not null default '{-3,0,3,7,15}'
                    check (cardinality(reminder_offsets) between 1 and 8 and -30 <= all(reminder_offsets) and 90 >= all(reminder_offsets)),
  updated_at        timestamptz not null default now()
);
alter table public.org_pay_settings enable row level security;
drop policy if exists "pay_settings_select" on public.org_pay_settings;
create policy "pay_settings_select" on public.org_pay_settings for select to authenticated
  using (private.is_org_member(org_id));
drop policy if exists "pay_settings_insert" on public.org_pay_settings;
create policy "pay_settings_insert" on public.org_pay_settings for insert to authenticated
  with check (private.is_org_admin(org_id));
drop policy if exists "pay_settings_update" on public.org_pay_settings;
create policy "pay_settings_update" on public.org_pay_settings for update to authenticated
  using (private.is_org_admin(org_id)) with check (private.is_org_admin(org_id));
revoke all on public.org_pay_settings from anon, authenticated;
grant select on public.org_pay_settings to authenticated;
grant insert (org_id, yape_phone, plin_phone, bank_name, bank_account, bank_cci, account_holder, pay_note,
              reminders_enabled, reminder_offsets, updated_at) on public.org_pay_settings to authenticated;
-- (org_id incluido porque el upsert de PostgREST reescribe todas las columnas enviadas; RLS exige ser admin)
grant update (org_id, yape_phone, plin_phone, bank_name, bank_account, bank_cci, account_holder, pay_note,
              reminders_enabled, reminder_offsets, updated_at) on public.org_pay_settings to authenticated;

-- Secretos por empresa (token de Mercado Pago CIFRADO por el servidor). Nadie más que el servidor lo lee.
create table if not exists public.org_secrets (
  org_id       uuid primary key references public.organizations(id) on delete cascade,
  mp_token_enc text check (mp_token_enc is null or char_length(mp_token_enc) <= 2000),
  updated_at   timestamptz not null default now()
);
alter table public.org_secrets enable row level security;
revoke all on public.org_secrets from anon, authenticated;

-- Enlace de cobro (uno por factura). El token es la "llave" de la página pública /pagar/<token>.
create table if not exists public.pay_links (
  token      text primary key default private.new_token(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null unique references public.invoices(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_pay_links_org on public.pay_links(org_id);
create index if not exists idx_pay_links_user on public.pay_links(created_by);
alter table public.pay_links enable row level security;
drop policy if exists "pay_links_select" on public.pay_links;
create policy "pay_links_select" on public.pay_links for select to authenticated
  using (private.is_org_member(org_id));
revoke all on public.pay_links from anon, authenticated;
grant select on public.pay_links to authenticated;

create or replace function private.invoice_pay_link_impl(p_invoice uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  i public.invoices;
  v_token text;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select * into i from public.invoices where id = p_invoice;
  if not found or not private.is_org_member(i.org_id) then raise exception 'Factura no encontrada' using errcode = '42501'; end if;
  if i.status = 'draft' then
    raise exception 'Primero emite la factura (o márcala como enviada) para cobrarla' using errcode = '22023';
  end if;
  insert into public.pay_links (org_id, invoice_id, created_by) values (i.org_id, i.id, v_uid)
  on conflict (invoice_id) do nothing;
  select l.token into v_token from public.pay_links l where l.invoice_id = i.id;
  return v_token;
end;
$$;
revoke execute on function private.invoice_pay_link_impl(uuid) from public, anon;
grant execute on function private.invoice_pay_link_impl(uuid) to authenticated;
create or replace function public.invoice_pay_link(p_invoice uuid)
returns text language sql security invoker set search_path = ''
as $$ select private.invoice_pay_link_impl(p_invoice) $$;
revoke execute on function public.invoice_pay_link(uuid) from public, anon;
grant execute on function public.invoice_pay_link(uuid) to authenticated;

-- "Ya pagué": el cliente reporta su Yape/Plin/transferencia desde la página pública; el negocio lo confirma con un toque.
create table if not exists public.payment_claims (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations(id) on delete cascade,
  invoice_id     uuid not null references public.invoices(id) on delete cascade,
  amount         numeric(14,2) not null check (amount > 0 and amount <= 100000000),
  method         text not null check (method in ('yape', 'plin', 'transferencia', 'otro')),
  operation_code text check (operation_code is null or char_length(operation_code) <= 40),
  payer_name     text check (payer_name is null or char_length(payer_name) <= 120),
  note           text check (note is null or char_length(note) <= 300),
  status         text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  payment_id     uuid references public.payments(id) on delete set null,
  resolved_by    uuid references auth.users(id) on delete set null,
  resolved_at    timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists idx_claims_org on public.payment_claims(org_id, status, created_at desc);
create index if not exists idx_claims_invoice on public.payment_claims(invoice_id);
create index if not exists idx_claims_payment on public.payment_claims(payment_id);
create index if not exists idx_claims_resolver on public.payment_claims(resolved_by);
alter table public.payment_claims enable row level security;
drop policy if exists "claims_select" on public.payment_claims;
create policy "claims_select" on public.payment_claims for select to authenticated
  using (private.is_org_member(org_id));
revoke all on public.payment_claims from anon, authenticated;
grant select on public.payment_claims to authenticated;

create or replace function private.resolve_claim_impl(p_claim uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  c public.payment_claims;
  v_status text;
  v_balance numeric;
  v_amount numeric;
  v_pay uuid;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select * into c from public.payment_claims where id = p_claim for update;
  if not found or not private.is_org_member(c.org_id) then raise exception 'No encontrado' using errcode = '42501'; end if;
  if c.status <> 'pending' then return c.status; end if;
  if not p_accept then
    update public.payment_claims set status = 'rejected', resolved_by = v_uid, resolved_at = now() where id = c.id;
    return 'rejected';
  end if;
  select i.status into v_status from public.invoices i where i.id = c.invoice_id for update;
  v_balance := private.invoice_total(c.invoice_id) - private.invoice_paid(c.invoice_id);
  v_amount := least(c.amount, v_balance);
  if v_status = 'sent' and v_amount > 0.004 then
    insert into public.payments (org_id, invoice_id, user_id, amount, method, note, external_ref)
    values (c.org_id, c.invoice_id, v_uid, round(v_amount, 2), c.method,
            left('Reportado por el cliente' || coalesce(' · op. ' || c.operation_code, ''), 200), 'claim:' || c.id::text)
    on conflict do nothing
    returning id into v_pay;
    perform private.settle_invoice(c.invoice_id);
  end if;
  update public.payment_claims set status = 'confirmed', payment_id = v_pay, resolved_by = v_uid, resolved_at = now() where id = c.id;
  return 'confirmed';
end;
$$;
revoke execute on function private.resolve_claim_impl(uuid, boolean) from public, anon;
grant execute on function private.resolve_claim_impl(uuid, boolean) to authenticated;
create or replace function public.resolve_payment_claim(p_claim uuid, p_accept boolean)
returns text language sql security invoker set search_path = ''
as $$ select private.resolve_claim_impl(p_claim, p_accept) $$;
revoke execute on function public.resolve_payment_claim(uuid, boolean) from public, anon;
grant execute on function public.resolve_payment_claim(uuid, boolean) to authenticated;

-- Registro de cobro externo (webhook de Mercado Pago). Idempotente por external_ref. Solo el servidor.
create or replace function public.record_external_payment(
  p_token text, p_amount numeric, p_method text, p_external_ref text, p_note text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  l public.pay_links;
  v_status text;
  v_balance numeric;
  v_amount numeric;
begin
  select * into l from public.pay_links where token = p_token;
  if not found then return 'not_found'; end if;
  if exists (select 1 from public.payments where external_ref = p_external_ref) then return 'duplicate'; end if;
  select i.status into v_status from public.invoices i where i.id = l.invoice_id for update;
  if v_status = 'draft' then return 'draft'; end if;
  v_balance := private.invoice_total(l.invoice_id) - private.invoice_paid(l.invoice_id);
  v_amount := least(p_amount, v_balance);
  if v_amount <= 0.004 then return 'already_paid'; end if;
  insert into public.payments (org_id, invoice_id, user_id, amount, method, note, external_ref)
  values (l.org_id, l.invoice_id, l.created_by, round(v_amount, 2), p_method, left(p_note, 200), p_external_ref)
  on conflict do nothing;
  perform private.settle_invoice(l.invoice_id);
  return 'recorded';
end;
$$;
revoke execute on function public.record_external_payment(text, numeric, text, text, text) from public, anon, authenticated;
grant execute on function public.record_external_payment(text, numeric, text, text, text) to service_role;

-- 3) COBRANZA AUTOMÁTICA ------------------------------------------------------------------------
create table if not exists public.reminder_log (
  id         bigint generated always as identity primary key,
  org_id     uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  stage      integer not null,               -- días respecto al vencimiento (-3 = 3 días antes)
  channel    text not null default 'email' check (channel in ('email', 'whatsapp')),
  sent_to    text check (sent_to is null or char_length(sent_to) <= 200),
  sent_at    timestamptz not null default now()
);
create unique index if not exists reminder_log_once on public.reminder_log(invoice_id, stage, channel);
create index if not exists idx_reminder_log_org on public.reminder_log(org_id, sent_at desc);
alter table public.reminder_log enable row level security;
drop policy if exists "reminder_log_select" on public.reminder_log;
create policy "reminder_log_select" on public.reminder_log for select to authenticated
  using (private.is_org_member(org_id));
drop policy if exists "reminder_log_insert" on public.reminder_log;
-- La app registra los recordatorios por WhatsApp que el usuario envía a mano (para no repetirlos).
create policy "reminder_log_insert" on public.reminder_log for insert to authenticated
  with check (channel = 'whatsapp' and private.is_org_member(org_id)
              and exists (select 1 from public.invoices i where i.id = invoice_id and i.org_id = reminder_log.org_id));
revoke all on public.reminder_log from anon, authenticated;
grant select on public.reminder_log to authenticated;
grant insert (org_id, invoice_id, stage, channel, sent_to) on public.reminder_log to authenticated;

-- Facturas que hoy deben recibir recordatorio por correo: solo la etapa más reciente aún no enviada
-- (si activas la cobranza tarde no se manda una avalancha). Solo el servidor (cron diario).
create or replace function public.collections_candidates(p_today date, p_limit integer default 80)
returns table (
  org_id uuid, invoice_id uuid, number text, client_name text, client_email text, currency text,
  due_date date, total numeric, balance numeric, days_overdue integer, stage integer, business_name text, pay_token text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with inv as (
    select i.id, i.org_id, i.due_date, i.currency,
           coalesce(case when fd.status = 'accepted' then fd.series || '-' || lpad(fd.correlative::text, 8, '0') end, i.number) as num,
           c.name as cname, lower(btrim(c.email)) as cemail, o.name as oname, s.reminder_offsets,
           private.invoice_total(i.id) as tot, private.invoice_paid(i.id) as paid,
           (p_today - i.due_date) as days
    from public.invoices i
    join public.org_pay_settings s on s.org_id = i.org_id and s.reminders_enabled
    join public.clients c on c.id = i.client_id
    join public.organizations o on o.id = i.org_id
    left join public.fiscal_documents fd on fd.invoice_id = i.id
    where i.status = 'sent' and i.due_date is not null
      and i.due_date between p_today - 120 and p_today + 30
      and c.email is not null and c.email ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$'
      and (fd.status is null or fd.status = 'accepted')
      and not exists (select 1 from public.fiscal_notes n where n.invoice_id = i.id and n.status = 'accepted')
  )
  select inv.org_id, inv.id, inv.num, inv.cname, inv.cemail, inv.currency, inv.due_date,
         inv.tot, round(inv.tot - inv.paid, 2), inv.days, st.stage, inv.oname, l.token
  from inv
  cross join lateral (select max(o) as stage from unnest(inv.reminder_offsets) as o where o <= inv.days) st
  left join public.pay_links l on l.invoice_id = inv.id
  where st.stage is not null
    and inv.tot - inv.paid > 0.004
    and not exists (select 1 from public.reminder_log r where r.invoice_id = inv.id and r.stage = st.stage and r.channel = 'email')
  order by inv.days desc
  limit greatest(1, least(coalesce(p_limit, 80), 500))
$$;
revoke execute on function public.collections_candidates(date, integer) from public, anon, authenticated;
grant execute on function public.collections_candidates(date, integer) to service_role;

-- Crea el enlace de cobro desde el servidor (para incluirlo en el correo de recordatorio).
create or replace function public.ensure_pay_link(p_invoice uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_token text;
begin
  insert into public.pay_links (org_id, invoice_id, created_by)
  select i.org_id, i.id, i.user_id from public.invoices i where i.id = p_invoice
  on conflict (invoice_id) do nothing;
  select token into v_token from public.pay_links where invoice_id = p_invoice;
  return v_token;
end;
$$;
revoke execute on function public.ensure_pay_link(uuid) from public, anon, authenticated;
grant execute on function public.ensure_pay_link(uuid) to service_role;

-- 4) GASTOS (para medir rentabilidad y flujo de caja real) ---------------------------------------
create table if not exists public.expenses (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  spent_on        date not null default ((now() at time zone 'America/Lima')::date),
  category        text not null default 'otros' check (category in
                    ('mercaderia', 'insumos', 'servicios', 'alquiler', 'planilla', 'transporte',
                     'marketing', 'impuestos', 'equipos', 'otros')),
  supplier_name   text check (supplier_name is null or char_length(supplier_name) <= 120),
  supplier_tax_id text check (supplier_tax_id is null or char_length(supplier_tax_id) <= 20),
  doc_number      text check (doc_number is null or char_length(doc_number) <= 40),
  description     text not null check (char_length(btrim(description)) between 1 and 200),
  tax             numeric(14,2) not null default 0 check (tax >= 0 and tax <= 100000000),
  total           numeric(14,2) not null check (total > 0 and total <= 100000000),
  currency        text not null default 'PEN' check (currency ~ '^[A-Z]{3}$'),
  source          text not null default 'manual' check (source in ('manual', 'voice', 'scan')),
  created_at      timestamptz not null default now(),
  constraint expenses_tax_chk check (tax <= total)
);
create index if not exists idx_expenses_org on public.expenses(org_id, spent_on desc);
create index if not exists idx_expenses_user on public.expenses(user_id);
alter table public.expenses enable row level security;
drop policy if exists "expenses_select" on public.expenses;
create policy "expenses_select" on public.expenses for select to authenticated
  using (private.is_org_member(org_id));
drop policy if exists "expenses_insert" on public.expenses;
create policy "expenses_insert" on public.expenses for insert to authenticated
  with check ((select auth.uid()) = user_id and private.is_org_member(org_id));
drop policy if exists "expenses_update" on public.expenses;
create policy "expenses_update" on public.expenses for update to authenticated
  using ((select auth.uid()) = user_id or private.is_org_admin(org_id))
  with check (private.is_org_member(org_id));
drop policy if exists "expenses_delete" on public.expenses;
create policy "expenses_delete" on public.expenses for delete to authenticated
  using ((select auth.uid()) = user_id or private.is_org_admin(org_id));
revoke all on public.expenses from anon, authenticated;
grant select, insert, delete on public.expenses to authenticated;
grant update (spent_on, category, supplier_name, supplier_tax_id, doc_number, description, tax, total, currency)
  on public.expenses to authenticated;

-- 5) STOCK + RADAR DE QUIEBRE ---------------------------------------------------------------------
alter table public.products add column if not exists stock numeric(14,2);          -- null = no se controla
alter table public.products add column if not exists reorder_point numeric(14,2);
alter table public.products drop constraint if exists products_reorder_chk;
alter table public.products add constraint products_reorder_chk
  check ((reorder_point is null or reorder_point between 0 and 10000000) and (stock is null or stock between -10000000 and 10000000));
grant update (name, unit_price, unit, active, stock, reorder_point) on public.products to authenticated;

-- Al emitir (borrador → enviada/pagada) se descuenta el stock de los productos vendidos (por nombre).
create or replace function private.apply_stock_on_issue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'draft' and new.status <> 'draft' then
    update public.products p
       set stock = p.stock - s.qty
      from (select lower(btrim(it.description)) as k, sum(it.quantity) as qty
              from public.invoice_items it where it.invoice_id = new.id group by 1) s
     where p.org_id = new.org_id and p.stock is not null and lower(btrim(p.name)) = s.k;
  end if;
  return new;
end;
$$;
revoke execute on function private.apply_stock_on_issue() from public, anon, authenticated;
drop trigger if exists trg_invoice_stock on public.invoices;
create trigger trg_invoice_stock after update of status on public.invoices
  for each row execute function private.apply_stock_on_issue();

-- Ajuste atómico (compras, mermas, inventario inicial).
create or replace function public.stock_adjust(p_product uuid, p_delta numeric)
returns numeric
language sql
security invoker
set search_path = ''
as $$
  update public.products set stock = coalesce(stock, 0) + round(p_delta, 2)
  where id = p_product and abs(p_delta) <= 10000000
  returning stock
$$;
revoke execute on function public.stock_adjust(uuid, numeric) from public, anon;
grant execute on function public.stock_adjust(uuid, numeric) to authenticated;

-- Velocidad de venta por producto (unidades/día en los últimos p_days días) para predecir quiebres.
create or replace function public.product_velocity(p_org uuid, p_days integer default 30)
returns table (product_id uuid, name text, stock numeric, reorder_point numeric, units numeric, per_day numeric)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.name, p.stock, p.reorder_point, coalesce(s.units, 0),
         round(coalesce(s.units, 0) / greatest(least(coalesce(p_days, 30), 365), 1)::numeric, 3)
  from public.products p
  left join (
    select lower(btrim(it.description)) as k, sum(it.quantity) as units
    from public.invoice_items it
    join public.invoices i on i.id = it.invoice_id
    where i.org_id = p_org and i.status <> 'draft'
      and i.issue_date >= private.today_pe() - greatest(least(coalesce(p_days, 30), 365), 1)
    group by 1
  ) s on s.k = lower(btrim(p.name))
  where p.org_id = p_org and p.active
$$;
revoke execute on function public.product_velocity(uuid, integer) from public, anon;
grant execute on function public.product_velocity(uuid, integer) to authenticated;

-- 6) COMPORTAMIENTO DE PAGO POR CLIENTE (score de crédito, predicción de cobro) -------------------
create or replace function public.client_payment_stats(p_org uuid)
returns table (
  client_key text, client_name text, invoices integer, credit_invoices integer, settled integer,
  avg_days_to_pay numeric, avg_days_late numeric, max_days_late integer, open_balance numeric, overdue_balance numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  with d as (select private.today_pe() as today),
  t as (
    select i.id, i.issue_date, i.due_date, i.status, lower(btrim(c.name)) as k, c.name as cname,
           sum(round(it.quantity * it.unit_price, 2) + round(round(it.quantity * it.unit_price, 2) * i.tax_rate / 100, 2)) as total
    from public.invoices i
    join public.clients c on c.id = i.client_id
    join public.invoice_items it on it.invoice_id = i.id
    left join public.fiscal_documents fd on fd.invoice_id = i.id
    where i.org_id = p_org and i.status in ('sent', 'paid') and coalesce(fd.status, '') <> 'rejected'
      and i.notes is distinct from 'Importada'
      and i.issue_date >= (select today from d) - 540
    group by i.id, c.name
  ),
  pm as (
    select p.invoice_id, sum(p.amount) as paid, max(p.paid_on) as last_paid
    from public.payments p where p.org_id = p_org group by p.invoice_id
  ),
  j as (
    select t.*, coalesce(pm.paid, 0) as paid, pm.last_paid,
           (t.status = 'paid' or coalesce(pm.paid, 0) >= t.total - 0.004) as is_settled
    from t left join pm on pm.invoice_id = t.id
  )
  select j.k, min(j.cname), count(*)::integer,
         (count(*) filter (where j.due_date is not null))::integer,
         (count(*) filter (where j.is_settled and j.last_paid is not null))::integer,
         round(avg(greatest(j.last_paid - j.issue_date, 0)) filter (where j.is_settled and j.last_paid is not null), 1),
         round(avg(greatest(j.last_paid - j.due_date, 0)) filter (where j.is_settled and j.last_paid is not null and j.due_date is not null), 1),
         coalesce(max(greatest(case
                    when j.due_date is null then 0
                    when j.is_settled and j.last_paid is not null then j.last_paid - j.due_date
                    when not j.is_settled then (select today from d) - j.due_date
                    else 0 end, 0)), 0)::integer,
         round(coalesce(sum(greatest(j.total - j.paid, 0)) filter (where not j.is_settled and j.status = 'sent'), 0), 2),
         round(coalesce(sum(greatest(j.total - j.paid, 0)) filter (where not j.is_settled and j.status = 'sent'
                                                                 and j.due_date < (select today from d)), 0), 2)
  from j
  group by j.k
$$;
revoke execute on function public.client_payment_stats(uuid) from public, anon;
grant execute on function public.client_payment_stats(uuid) to authenticated;

-- 7) SNAPSHOT PARA EL COPILOTO DE IA -------------------------------------------------------------
-- Resumen agregado (sin documentos de identidad ni correos) de UNA empresa del usuario. RLS aplica.
create or replace function public.business_snapshot(p_org uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := private.today_pe();
  v_month date := date_trunc('month', private.today_pe())::date;
  v_prev date := (date_trunc('month', private.today_pe()) - interval '1 month')::date;
  v_cur text;
  v_out jsonb;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  select coalesce(o.currency, 'PEN') into v_cur from public.organizations o where o.id = p_org;

  with inv as (
    select i.id, i.client_id, i.issue_date, i.due_date, i.status,
           sum(round(it.quantity * it.unit_price, 2) + round(round(it.quantity * it.unit_price, 2) * i.tax_rate / 100, 2)) as total
    from public.invoices i
    join public.invoice_items it on it.invoice_id = i.id
    left join public.fiscal_documents fd on fd.invoice_id = i.id
    where i.org_id = p_org and i.status <> 'draft' and i.currency = v_cur and coalesce(fd.status, '') <> 'rejected'
      and (i.issue_date >= v_today - 120 or i.status = 'sent')
    group by i.id
  ),
  pay as (select p.invoice_id, sum(p.amount) as paid from public.payments p where p.org_id = p_org group by p.invoice_id),
  j as (
    select inv.*, coalesce(pay.paid, 0) as paid, c.name as cname,
           case when inv.status = 'sent' then greatest(inv.total - coalesce(pay.paid, 0), 0) else 0 end as balance
    from inv left join pay on pay.invoice_id = inv.id left join public.clients c on c.id = inv.client_id
  )
  select jsonb_build_object(
    'today', v_today,
    'currency', v_cur,
    'sales_this_month', (select jsonb_build_object('total', round(coalesce(sum(total), 0), 2), 'count', count(*)) from j where issue_date >= v_month),
    'sales_last_month', (select jsonb_build_object('total', round(coalesce(sum(total), 0), 2), 'count', count(*)) from j where issue_date >= v_prev and issue_date < v_month),
    'sales_last_month_same_day', (select round(coalesce(sum(total), 0), 2) from j
                                  where issue_date >= v_prev and issue_date <= v_prev + (v_today - v_month)),
    'receivable_total', (select round(coalesce(sum(balance), 0), 2) from j),
    'overdue_total', (select round(coalesce(sum(balance), 0), 2) from j where due_date < v_today),
    'debtors', coalesce((select jsonb_agg(x order by x.balance desc) from (
        select coalesce(cname, '—') as client, round(sum(balance), 2) as balance,
               max(greatest(v_today - due_date, 0)) as max_days_overdue, count(*) as invoices
        from j where balance > 0.004 group by coalesce(cname, '—') order by sum(balance) desc limit 10) x), '[]'::jsonb),
    'due_next_7_days', (select round(coalesce(sum(balance), 0), 2) from j where due_date between v_today and v_today + 7),
    'top_clients_90d', coalesce((select jsonb_agg(x order by x.total desc) from (
        select coalesce(cname, '—') as client, round(sum(total), 2) as total, count(*) as invoices
        from j where issue_date >= v_today - 90 group by coalesce(cname, '—') order by sum(total) desc limit 5) x), '[]'::jsonb),
    'top_products_90d', coalesce((select jsonb_agg(x order by x.amount desc) from (
        select min(btrim(it.description)) as product, round(sum(it.quantity), 2) as units,
               round(sum(round(it.quantity * it.unit_price, 2)), 2) as amount
        from public.invoice_items it join j on j.id = it.invoice_id
        where j.issue_date >= v_today - 90
        group by lower(btrim(it.description)) order by sum(round(it.quantity * it.unit_price, 2)) desc limit 8) x), '[]'::jsonb),
    'expenses_this_month', (select jsonb_build_object('total', round(coalesce(sum(e.total), 0), 2),
        'by_category', coalesce((select jsonb_object_agg(k.category, k.t) from (
            select e2.category, round(sum(e2.total), 2) as t from public.expenses e2
            where e2.org_id = p_org and e2.currency = v_cur and e2.spent_on >= v_month group by e2.category) k), '{}'::jsonb))
        from public.expenses e where e.org_id = p_org and e.currency = v_cur and e.spent_on >= v_month),
    'expenses_last_month', (select round(coalesce(sum(e.total), 0), 2) from public.expenses e
        where e.org_id = p_org and e.currency = v_cur and e.spent_on >= v_prev and e.spent_on < v_month),
    'collected_this_month', (select round(coalesce(sum(p.amount), 0), 2) from public.payments p
        join public.invoices i on i.id = p.invoice_id
        where p.org_id = p_org and i.currency = v_cur and p.paid_on >= v_month),
    'open_quotes', (select jsonb_build_object('count', count(*), 'total', round(coalesce(sum(
          (select sum(round(qi.quantity * qi.unit_price, 2) + round(round(qi.quantity * qi.unit_price, 2) * q.tax_rate / 100, 2))
             from public.quote_items qi where qi.quote_id = q.id)), 0), 2))
        from public.quotes q where q.org_id = p_org and q.status in ('draft', 'sent', 'accepted') and q.currency = v_cur),
    'stock_alerts', coalesce((select jsonb_agg(x order by x.days_left nulls last) from (
        select v.name as product, v.stock, v.per_day,
               case when v.per_day > 0 then round(greatest(v.stock, 0) / v.per_day, 1) end as days_left
        from public.product_velocity(p_org, 30) v
        where v.stock is not null and (v.stock <= coalesce(v.reorder_point, 0)
              or (v.per_day > 0 and v.stock / v.per_day <= 14))
        limit 10) x), '[]'::jsonb),
    'slow_payers', coalesce((select jsonb_agg(x order by x.avg_days_late desc) from (
        select s.client_name as client, s.avg_days_late, s.overdue_balance
        from public.client_payment_stats(p_org) s
        where coalesce(s.avg_days_late, 0) > 3 or s.overdue_balance > 0
        order by s.avg_days_late desc nulls last limit 5) x), '[]'::jsonb)
  ) into v_out;
  return v_out;
end;
$$;
revoke execute on function public.business_snapshot(uuid) from public, anon;
grant execute on function public.business_snapshot(uuid) to authenticated;

-- 8) Tiempo real -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'quotes') then
      alter publication supabase_realtime add table public.quotes;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'payment_claims') then
      alter publication supabase_realtime add table public.payment_claims;
    end if;
  end if;
end $$;

commit;
