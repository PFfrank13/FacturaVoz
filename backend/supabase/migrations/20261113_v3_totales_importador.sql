-- FacturaVoz v3 · A1 + A2 + A3
--   A2: totales guardados en cada comprobante (base, IGV, total) y UNA sola regla de "ventas" para toda la app:
--       misma moneda · anuladas fuera · notas de crédito RESTAN · borradores y rechazados por SUNAT fuera.
--   A1: importador relacional de libros Excel (clientes, comprobantes, detalle, catálogo) idempotente y con "deshacer".
--   A3: índices para que Inicio, Reportes y listas respondan rápido con decenas de miles de comprobantes.
-- Aditiva e idempotente: no borra tablas ni columnas. Requiere las migraciones hasta 20261112.
begin;

-- ───────────────────────── 1) Columnas nuevas en comprobantes ─────────────────────────
alter table public.invoices add column if not exists doc_kind text;                 -- factura · boleta · nota_credito · nota_venta (null = se decide al emitir)
alter table public.invoices add column if not exists voided_at timestamptz;         -- anulado (no cuenta como venta)
alter table public.invoices add column if not exists void_reason text;
alter table public.invoices add column if not exists related_invoice_id uuid references public.invoices(id) on delete set null; -- NC → comprobante que modifica
alter table public.invoices add column if not exists import_job_id uuid;            -- importación que lo creó (para "deshacer")
alter table public.invoices add column if not exists import_key text;               -- tipo|serie-número (no se importa dos veces)
alter table public.invoices add column if not exists amt_discount numeric(14,2) not null default 0;
alter table public.invoices add column if not exists amt_base numeric(14,2) not null default 0;
alter table public.invoices add column if not exists amt_tax numeric(14,2) not null default 0;
alter table public.invoices add column if not exists amt_total numeric(14,2) not null default 0;
alter table public.invoices add column if not exists totals_locked boolean not null default false; -- true = montos tal como venían del archivo

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'invoices_v3_chk') then
    alter table public.invoices add constraint invoices_v3_chk check (
      (doc_kind is null or doc_kind in ('factura', 'boleta', 'nota_credito', 'nota_venta'))
      and (void_reason is null or char_length(void_reason) <= 200)
      and (import_key is null or char_length(import_key) <= 90)
      and amt_discount >= 0 and amt_base >= 0 and amt_tax >= 0 and amt_total >= 0);
  end if;
end $$;

create index if not exists idx_invoices_related on public.invoices(related_invoice_id) where related_invoice_id is not null;
create index if not exists idx_invoices_import_job on public.invoices(import_job_id) where import_job_id is not null;
create unique index if not exists uq_invoices_org_import_key on public.invoices(org_id, import_key) where import_key is not null;
-- A3: el índice que usan TODOS los totales (empresa + fecha + moneda) y las listas paginadas.
create index if not exists idx_invoices_org_issue on public.invoices(org_id, issue_date desc, currency) include (status, amt_total, amt_base, amt_tax, doc_kind, voided_at);
create index if not exists idx_invoices_org_open on public.invoices(org_id, due_date) where status = 'sent' and voided_at is null;
create index if not exists idx_payments_org_paid_on on public.payments(org_id, paid_on desc);
create index if not exists idx_clients_org_tax on public.clients(org_id, tax_id) where tax_id is not null;
create index if not exists idx_items_invoice_pos on public.invoice_items(invoice_id, position);

alter table public.products add column if not exists sku text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'products_sku_chk') then
    alter table public.products add constraint products_sku_chk check (sku is null or char_length(sku) between 1 and 40);
  end if;
end $$;
create unique index if not exists uq_products_org_sku on public.products(org_id, sku) where sku is not null;
grant update (sku) on public.products to authenticated;

-- ───────────────────────── 2) Totales guardados (se mantienen solos) ─────────────────────────
-- Misma fórmula de siempre: base = Σ redondeo(cantidad × precio); IGV = Σ redondeo(línea × tasa).
create or replace function private.recalc_invoice(p_invoice uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text := coalesce(current_setting('facturavoz.internal', true), 'off');
begin
  perform set_config('facturavoz.internal', 'on', true);
  update public.invoices i
     set amt_base = coalesce(s.base, 0), amt_tax = coalesce(s.tax, 0), amt_total = coalesce(s.base, 0) + coalesce(s.tax, 0)
    from (select sum(round(round(it.quantity, 2) * round(it.unit_price, 2), 2)) as base,
                 sum(round(round(round(it.quantity, 2) * round(it.unit_price, 2), 2) * i2.tax_rate / 100, 2)) as tax
            from public.invoices i2 left join public.invoice_items it on it.invoice_id = i2.id
           where i2.id = p_invoice) s
   where i.id = p_invoice and not i.totals_locked
     and (i.amt_base, i.amt_tax, i.amt_total) is distinct from (coalesce(s.base, 0), coalesce(s.tax, 0), coalesce(s.base, 0) + coalesce(s.tax, 0));
  perform set_config('facturavoz.internal', v_prev, true);  -- se devuelve el valor anterior (puede estar dentro del importador)
end;
$$;

create or replace function private.items_recalc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then perform private.recalc_invoice(old.invoice_id); end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.invoice_id is distinct from old.invoice_id) then
    perform private.recalc_invoice(new.invoice_id);
  end if;
  return null;
end;
$$;
drop trigger if exists trg_items_recalc on public.invoice_items;
create trigger trg_items_recalc after insert or update or delete on public.invoice_items
  for each row execute function private.items_recalc();

-- Campos que solo escribe el servidor (importador, anulación, totales). El cliente no los puede falsear.
create or replace function private.guard_invoice_v3()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_setting('facturavoz.internal', true) = 'on' then return new; end if;
  if tg_op = 'INSERT' then
    new.amt_discount := 0; new.amt_base := 0; new.amt_tax := 0; new.amt_total := 0; new.totals_locked := false;
    new.voided_at := null; new.void_reason := null; new.import_job_id := null; new.import_key := null; new.related_invoice_id := null;
    if new.doc_kind = 'nota_credito' then new.doc_kind := null; end if;
  else
    new.amt_discount := old.amt_discount; new.amt_base := old.amt_base; new.amt_tax := old.amt_tax; new.amt_total := old.amt_total;
    new.totals_locked := old.totals_locked; new.voided_at := old.voided_at; new.void_reason := old.void_reason;
    new.import_job_id := old.import_job_id; new.import_key := old.import_key; new.related_invoice_id := old.related_invoice_id;
    if old.status <> 'draft' then new.doc_kind := old.doc_kind; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists guard_invoice_v3 on public.invoices;
create trigger guard_invoice_v3 before insert or update on public.invoices
  for each row execute function private.guard_invoice_v3();

-- La tasa de un borrador puede cambiar: recalcular.
create or replace function private.invoice_rate_recalc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.tax_rate is distinct from old.tax_rate then perform private.recalc_invoice(new.id); end if;
  return null;
end;
$$;
drop trigger if exists trg_invoice_rate_recalc on public.invoices;
create trigger trg_invoice_rate_recalc after update of tax_rate on public.invoices
  for each row execute function private.invoice_rate_recalc();

-- Una nota de crédito electrónica aceptada por SUNAT anula el comprobante (también para los totales).
create or replace function private.note_marks_void()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text := coalesce(current_setting('facturavoz.internal', true), 'off');
begin
  if new.status = 'accepted' then
    perform set_config('facturavoz.internal', 'on', true);
    update public.invoices set voided_at = coalesce(voided_at, now()), void_reason = coalesce(void_reason, left(new.reason_text, 200))
     where id = new.invoice_id and voided_at is null;
    perform set_config('facturavoz.internal', v_prev, true);
  end if;
  return null;
end;
$$;
drop trigger if exists trg_note_marks_void on public.fiscal_notes;
create trigger trg_note_marks_void after insert or update of status on public.fiscal_notes
  for each row execute function private.note_marks_void();

revoke execute on function private.recalc_invoice(uuid), private.items_recalc(), private.guard_invoice_v3(),
  private.invoice_rate_recalc(), private.note_marks_void() from public, anon, authenticated;

-- Relleno inicial (una vez): totales de todos los comprobantes existentes y anulados por nota aceptada.
do $$
begin
  perform set_config('facturavoz.internal', 'on', true);
  perform set_config('facturavoz.bypass_license', 'on', true);
  update public.invoices i
     set amt_base = s.base, amt_tax = s.tax, amt_total = s.base + s.tax
    from (select i2.id,
                 coalesce(sum(round(round(it.quantity, 2) * round(it.unit_price, 2), 2)), 0) as base,
                 coalesce(sum(round(round(round(it.quantity, 2) * round(it.unit_price, 2), 2) * i2.tax_rate / 100, 2)), 0) as tax
            from public.invoices i2 left join public.invoice_items it on it.invoice_id = i2.id
           where not i2.totals_locked
           group by i2.id) s
   where i.id = s.id and (i.amt_base, i.amt_tax, i.amt_total) is distinct from (s.base, s.tax, s.base + s.tax);
  update public.invoices i set voided_at = n.updated_at, void_reason = left(n.reason_text, 200)
    from public.fiscal_notes n
   where n.invoice_id = i.id and n.status = 'accepted' and i.voided_at is null;
  perform set_config('facturavoz.internal', 'off', true);
  perform set_config('facturavoz.bypass_license', 'off', true);
end $$;

-- Total de un comprobante (lo usan cobros, webhooks y estado "pagada"): respeta los montos importados.
create or replace function private.invoice_total(p_invoice uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case when i.totals_locked then i.amt_total
              else coalesce((select sum(round(it.quantity * it.unit_price, 2) + round(round(it.quantity * it.unit_price, 2) * i.tax_rate / 100, 2))
                               from public.invoice_items it where it.invoice_id = i.id), 0) end
  from public.invoices i where i.id = p_invoice
$$;

-- ───────────────────────── 3) LA regla de ventas (una sola para toda la app) ─────────────────────────
-- Cuenta como venta: emitido o pagado · no anulado · no rechazado por SUNAT. Nota de crédito = negativo.
-- SECURITY INVOKER: respeta RLS (un técnico solo suma lo suyo).
create or replace function private.sale_rows(p_org uuid, p_from date, p_to date, p_currency text)
returns table (id uuid, client_id uuid, issue_date date, due_date date, status text, kind text,
               base numeric, tax numeric, total numeric, user_id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select i.id, i.client_id, i.issue_date, i.due_date, i.status, coalesce(i.doc_kind, 'venta'),
         case when i.doc_kind = 'nota_credito' then -i.amt_base else i.amt_base end,
         case when i.doc_kind = 'nota_credito' then -i.amt_tax else i.amt_tax end,
         case when i.doc_kind = 'nota_credito' then -i.amt_total else i.amt_total end,
         i.user_id
  from public.invoices i
  left join public.fiscal_documents fd on fd.invoice_id = i.id
  where i.org_id = p_org
    and (p_from is null or i.issue_date >= p_from)
    and (p_to is null or i.issue_date < p_to)
    and (p_currency is null or i.currency = p_currency)
    and i.status in ('sent', 'paid')
    and i.voided_at is null
    and coalesce(fd.status, '') <> 'rejected'
$$;
revoke execute on function private.sale_rows(uuid, date, date, text) from public, anon;
grant execute on function private.sale_rows(uuid, date, date, text) to authenticated, service_role;

-- Resumen de ventas [p_from, p_to) — mismas claves de antes + notas de crédito y anulados.
create or replace function public.sales_summary(p_org uuid, p_from date, p_to date, p_currency text default 'PEN')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with s as (select * from private.sale_rows(p_org, p_from, p_to, p_currency)),
  other as (
    select i.status, i.amt_total, i.voided_at, coalesce(fd.status, '') as fiscal
    from public.invoices i left join public.fiscal_documents fd on fd.invoice_id = i.id
    where i.org_id = p_org and i.issue_date >= p_from and i.issue_date < p_to and i.currency = p_currency
      and (i.status = 'draft' or i.voided_at is not null or fd.status = 'rejected')
  )
  select jsonb_build_object(
    'currency', p_currency,
    'sales_count', (select count(*) from s where kind <> 'nota_credito'),
    'sales_base', (select coalesce(sum(base), 0) from s),
    'sales_tax', (select coalesce(sum(tax), 0) from s),
    'sales_total', (select coalesce(sum(total), 0) from s),
    'gross_total', (select coalesce(sum(total), 0) from s where kind <> 'nota_credito'),
    'credit_notes_count', (select count(*) from s where kind = 'nota_credito'),
    'credit_notes_total', (select coalesce(-sum(total), 0) from s where kind = 'nota_credito'),
    'voided_count', (select count(*) from other where voided_at is not null),
    'drafts_count', (select count(*) from other where status = 'draft'),
    'drafts_total', (select coalesce(sum(amt_total), 0) from other where status = 'draft'),
    'rejected_count', (select count(*) from other where fiscal = 'rejected'),
    'rule', 'emitidos y pagados, sin anulados ni rechazados, menos notas de crédito, en ' || p_currency
  );
$$;
revoke execute on function public.sales_summary(uuid, date, date, text) from public, anon;
grant execute on function public.sales_summary(uuid, date, date, text) to authenticated, service_role;

-- Ventas por día o por mes (gráficos y reportes) con la MISMA regla.
create or replace function public.sales_series(p_org uuid, p_from date, p_to date, p_currency text default 'PEN', p_bucket text default 'day')
returns table (bucket date, total numeric, base numeric, tax numeric, docs integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select date_trunc(case when p_bucket = 'month' then 'month' else 'day' end, s.issue_date)::date,
         round(sum(s.total), 2), round(sum(s.base), 2), round(sum(s.tax), 2), (count(*) filter (where s.kind <> 'nota_credito'))::integer
  from private.sale_rows(p_org, p_from, p_to, p_currency) s
  group by 1 order by 1
$$;
revoke execute on function public.sales_series(uuid, date, date, text, text) from public, anon;
grant execute on function public.sales_series(uuid, date, date, text, text) to authenticated;

-- Lista paginada (A3): nunca bajar todo. Cursor = (issue_date, id) del último elemento.
create or replace function public.invoice_page(p_org uuid, p_limit integer default 50, p_before_date date default null,
                                               p_before_id uuid default null, p_search text default null, p_status text default null)
returns table (id uuid, number text, issue_date date, due_date date, status text, doc_kind text, currency text,
               total numeric, paid numeric, voided boolean, imported boolean, client_id uuid, client_name text, fiscal_status text)
language sql
stable
security invoker
set search_path = ''
as $$
  select i.id, i.number, i.issue_date, i.due_date, i.status, i.doc_kind, i.currency, i.amt_total,
         coalesce((select sum(p.amount) from public.payments p where p.invoice_id = i.id), 0),
         i.voided_at is not null, i.import_job_id is not null, i.client_id, c.name, fd.status
  from public.invoices i
  left join public.clients c on c.id = i.client_id
  left join public.fiscal_documents fd on fd.invoice_id = i.id
  where i.org_id = p_org
    and (p_before_date is null or (i.issue_date, i.id) < (p_before_date, p_before_id))
    and (p_status is null or (p_status = 'voided' and i.voided_at is not null) or (p_status <> 'voided' and i.status = p_status and i.voided_at is null))
    and (p_search is null or i.number ilike '%' || p_search || '%' or c.name ilike '%' || p_search || '%')
  order by i.issue_date desc, i.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200)
$$;
revoke execute on function public.invoice_page(uuid, integer, date, uuid, text, text) from public, anon;
grant execute on function public.invoice_page(uuid, integer, date, uuid, text, text) to authenticated;

-- ───────────────────────── 4) Importador relacional (libro Excel) ─────────────────────────
create table if not exists public.wb_imports (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  file_name    text check (file_name is null or char_length(file_name) <= 200),
  status       text not null default 'uploading' check (status in ('uploading', 'done', 'undone', 'failed')),
  expected     jsonb not null default '{}'::jsonb check (pg_column_size(expected) < 20000),
  warnings     jsonb not null default '[]'::jsonb check (pg_column_size(warnings) < 60000),
  result       jsonb,
  created_at   timestamptz not null default now(),
  finished_at  timestamptz,
  undone_at    timestamptz
);
create index if not exists idx_wb_imports_org on public.wb_imports(org_id, created_at desc);
create index if not exists idx_wb_imports_user on public.wb_imports(user_id);
alter table public.wb_imports enable row level security;
drop policy if exists "wb_imports_select" on public.wb_imports;
create policy "wb_imports_select" on public.wb_imports for select to authenticated
  using (private.can_finance(org_id));
revoke all on public.wb_imports from anon, authenticated;
grant select on public.wb_imports to authenticated;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'invoices_import_job_fk') then
    alter table public.invoices add constraint invoices_import_job_fk foreign key (import_job_id) references public.wb_imports(id) on delete set null;
  end if;
end $$;

-- Relación id del archivo → registro creado (o encontrado). Solo la usan las funciones del importador.
create table if not exists public.wb_import_map (
  job_id    uuid not null references public.wb_imports(id) on delete cascade,
  kind      text not null check (kind in ('client', 'product', 'invoice')),
  ext       text not null check (char_length(ext) <= 200),
  target_id uuid not null,
  created   boolean not null,
  primary key (job_id, kind, ext)
);
create index if not exists idx_wb_import_map_target on public.wb_import_map(target_id);
alter table public.wb_import_map enable row level security;
revoke all on public.wb_import_map from anon, authenticated;

-- Durante una importación o un "deshacer" no se generan puntos, alertas, webhooks ni papelera por cada fila
-- (se registra UNA entrada en la bitácora con el resumen).
create or replace function private.loyalty_on_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rate numeric;
  v_client uuid;
  v_points integer;
begin
  if current_setting('facturavoz.importing', true) = 'on' then return new; end if;
  select s.loyalty_rate into v_rate from public.org_settings s where s.org_id = new.org_id;
  if coalesce(v_rate, 0) <= 0 then return new; end if;
  -- Un cobro recuperado de la papelera no vuelve a sumar puntos
  if exists (select 1 from public.trash t where t.row_id = new.id and t.table_name = 'payments') then return new; end if;
  select i.client_id into v_client from public.invoices i where i.id = new.invoice_id;
  v_points := floor(new.amount * v_rate);
  if v_client is null or v_points <= 0 then return new; end if;
  insert into public.loyalty_ledger (org_id, client_id, points, reason, invoice_id, user_id)
  values (new.org_id, v_client, v_points, 'Compra', new.invoice_id, new.user_id);
  return new;
end;
$$;

create or replace function private.watch_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('facturavoz.importing', true) = 'on' then return new; end if;
  perform private.audit(new.org_id, 'cobro.registrado', 'payments', new.id::text, jsonb_build_object('monto', new.amount, 'medio', new.method, 'factura', new.invoice_id), new.user_id);
  return new;
end;
$$;

create or replace function private.webhook_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('facturavoz.importing', true) = 'on' then return new; end if;
  if not exists (select 1 from public.org_webhooks w where w.org_id = new.org_id and w.active) then return new; end if;
  if tg_table_name = 'invoices' then
    if tg_op = 'INSERT' then
      perform private.enqueue_webhook(new.org_id, 'invoice.created', jsonb_build_object('id', new.id, 'number', new.number, 'status', new.status, 'issue_date', new.issue_date, 'currency', new.currency));
    elsif new.status is distinct from old.status then
      perform private.enqueue_webhook(new.org_id, case when new.status = 'paid' then 'invoice.paid' else 'invoice.updated' end,
        jsonb_build_object('id', new.id, 'number', new.number, 'status', new.status, 'total', private.invoice_total(new.id)));
    end if;
  elsif tg_table_name = 'payments' then
    perform private.enqueue_webhook(new.org_id, 'payment.created', jsonb_build_object('id', new.id, 'invoice_id', new.invoice_id, 'amount', new.amount, 'method', new.method, 'paid_on', new.paid_on));
  elsif tg_table_name = 'quotes' and tg_op = 'INSERT' and new.source = 'store' then
    perform private.enqueue_webhook(new.org_id, 'order.created', jsonb_build_object('id', new.id, 'number', new.number, 'phone', new.contact_phone));
  end if;
  return new;
end;
$$;

create or replace function private.to_trash()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := to_jsonb(old);
  v_org uuid := (to_jsonb(old) ->> 'org_id')::uuid;
  v_label text;
begin
  -- "Deshacer importación": se borra solo lo que creó la importación, sin llenar la papelera.
  if current_setting('facturavoz.importing', true) = 'on' then return old; end if;
  if tg_table_name = 'invoices' then
    v_data := v_data || jsonb_build_object('_items', (select coalesce(jsonb_agg(to_jsonb(it)), '[]'::jsonb) from public.invoice_items it where it.invoice_id = old.id));
  elsif tg_table_name = 'quotes' then
    v_data := v_data || jsonb_build_object('_items', (select coalesce(jsonb_agg(to_jsonb(it)), '[]'::jsonb) from public.quote_items it where it.quote_id = old.id));
  end if;
  v_label := coalesce(v_data ->> 'name', v_data ->> 'number', v_data ->> 'title', v_data ->> 'description', v_data ->> 'body', tg_table_name);
  if v_org is null and tg_table_name = 'payments' then v_org := (v_data ->> 'org_id')::uuid; end if;
  -- Si se borra la empresa entera (cascada) no se guarda nada.
  if v_org is null or not exists (select 1 from public.organizations o where o.id = v_org) then return old; end if;
  insert into public.trash (org_id, table_name, row_id, label, data, deleted_by)
  values (v_org, tg_table_name, (v_data ->> 'id')::uuid, left(v_label, 140), v_data, (select auth.uid()));
  perform private.audit(v_org, tg_table_name || '.eliminado', tg_table_name, v_data ->> 'id',
                        jsonb_build_object('label', left(v_label, 140), 'amount', coalesce(v_data -> 'amount', v_data -> 'total')));
  if tg_table_name = 'payments' and (select auth.uid()) is not null and not private.is_org_admin(v_org) then
    perform private.alert(v_org, 'cobro_eliminado', 'bad', 'Se eliminó un cobro',
      'Se borró un cobro de ' || coalesce(v_data ->> 'amount', '?') || '. Puedes recuperarlo desde la papelera.', jsonb_build_object('payment_id', v_data ->> 'id'));
  end if;
  return old;
end;
$$;

-- Validación común: el trabajo existe, es de la empresa y el usuario puede importar.
create or replace function private.wb_job(p_job uuid, p_need_status text default 'uploading')
returns public.wb_imports
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.wb_imports;
begin
  select * into j from public.wb_imports where id = p_job for update;
  if not found or not private.can_finance(j.org_id) then raise exception 'Importación no encontrada' using errcode = '42501'; end if;
  if p_need_status is not null and j.status <> p_need_status then raise exception 'Esta importación ya terminó' using errcode = '22023'; end if;
  return j;
end;
$$;

create or replace function private.wb_import_begin_impl(p_org uuid, p_file text, p_expected jsonb, p_warnings jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null or not private.can_finance(p_org) then
    raise exception 'Solo el dueño, un administrador o finanzas pueden importar' using errcode = '42501';
  end if;
  if not private.license_write_ok(p_org) then
    raise exception 'Tu licencia no permite cambios ahora' using errcode = '42501', hint = 'license';
  end if;
  if (select count(*) from public.wb_imports w where w.org_id = p_org and w.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Demasiadas importaciones en una hora. Espera un poco.' using errcode = '54000';
  end if;
  insert into public.wb_imports (org_id, user_id, file_name, expected, warnings)
  values (p_org, v_uid, left(p_file, 200), coalesce(p_expected, '{}'::jsonb),
          case when jsonb_typeof(p_warnings) = 'array' then p_warnings else '[]'::jsonb end)
  returning id into v_id;
  return v_id;
end;
$$;

-- Clientes (máx. 1000 por llamada). Se busca primero por documento, luego por nombre (entre los sin documento).
create or replace function private.wb_import_clients_impl(p_job uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.wb_imports := private.wb_job(p_job);
  r jsonb;
  v_id uuid;
  v_created integer := 0;
  v_found integer := 0;
  v_name text; v_doc text; v_type text;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 1000 then raise exception 'Bloque no válido' using errcode = '22023'; end if;
  perform set_config('facturavoz.importing', 'on', true);
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when coalesce(r ->> 'ref', '') = '' or exists (select 1 from public.wb_import_map m where m.job_id = p_job and m.kind = 'client' and m.ext = left(r ->> 'ref', 200));
    v_name := left(coalesce(nullif(btrim(r ->> 'name'), ''), 'Cliente sin nombre'), 120);
    v_doc := nullif(btrim(r ->> 'doc'), '');
    v_type := case when v_doc is null then '0' when r ->> 'doc_type' in ('1', '4', '6', '7') then r ->> 'doc_type' else '0' end;
    v_id := null;
    if v_doc is not null then
      select c.id into v_id from public.clients c where c.org_id = j.org_id and c.tax_id = v_doc order by c.created_at limit 1;
    end if;
    if v_id is null then
      -- Sin documento coincidente: mismo nombre y también sin documento, y que NO lo haya creado esta misma importación
      -- (dos clientes distintos del archivo nunca se juntan en uno).
      select c.id into v_id from public.clients c
       where c.org_id = j.org_id and lower(btrim(c.name)) = lower(v_name) and c.tax_id is null
         and not exists (select 1 from public.wb_import_map m where m.job_id = p_job and m.target_id = c.id)
       order by c.created_at limit 1;
    end if;
    if v_id is null then
      insert into public.clients (user_id, org_id, name, tax_id, doc_type, address, district, phone, email, source)
      values (j.user_id, j.org_id, v_name, left(v_doc, 30), v_type, left(nullif(btrim(r ->> 'address'), ''), 300),
              left(nullif(btrim(r ->> 'district'), ''), 80), left(nullif(btrim(r ->> 'phone'), ''), 30),
              left(nullif(btrim(r ->> 'email'), ''), 200), 'otro')
      returning id into v_id;
      v_created := v_created + 1;
      insert into public.wb_import_map values (p_job, 'client', left(r ->> 'ref', 200), v_id, true);
    else
      v_found := v_found + 1;
      insert into public.wb_import_map values (p_job, 'client', left(r ->> 'ref', 200), v_id, false);
    end if;
  end loop;
  perform set_config('facturavoz.importing', 'off', true);
  return jsonb_build_object('created', v_created, 'existing', v_found);
end;
$$;

-- Productos (máx. 500). Por código (sku) o por nombre. El precio del archivo incluye IGV: se guarda sin IGV.
create or replace function private.wb_import_products_impl(p_job uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.wb_imports := private.wb_job(p_job);
  r jsonb;
  v_id uuid;
  v_rate numeric;
  v_created integer := 0;
  v_found integer := 0;
  v_price numeric;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'Bloque no válido' using errcode = '22023'; end if;
  select coalesce(o.default_tax_rate, 18) into v_rate from public.organizations o where o.id = j.org_id;
  perform set_config('facturavoz.importing', 'on', true);
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when coalesce(r ->> 'code', '') = '' or coalesce(btrim(r ->> 'name'), '') = ''
      or exists (select 1 from public.wb_import_map m where m.job_id = p_job and m.kind = 'product' and m.ext = left(r ->> 'code', 200));
    select p.id into v_id from public.products p where p.org_id = j.org_id and p.sku = left(r ->> 'code', 40);
    if v_id is null then
      select p.id into v_id from public.products p where p.org_id = j.org_id and lower(btrim(p.name)) = lower(btrim(left(r ->> 'name', 200)));
      if v_id is not null then
        update public.products set sku = left(r ->> 'code', 40) where id = v_id and sku is null;
      end if;
    end if;
    if v_id is null then
      v_price := greatest(coalesce((r ->> 'price')::numeric, 0), 0);
      if coalesce((r ->> 'taxed')::boolean, true) then v_price := round(v_price / (1 + v_rate / 100), 2); end if;
      insert into public.products (org_id, user_id, name, unit_price, unit, sku, category)
      values (j.org_id, j.user_id, left(btrim(r ->> 'name'), 200), least(v_price, 10000000),
              case when r ->> 'unit' = 'ZZ' then 'ZZ' else 'NIU' end, left(r ->> 'code', 40), left(nullif(btrim(r ->> 'category'), ''), 60))
      returning id into v_id;
      v_created := v_created + 1;
      insert into public.wb_import_map values (p_job, 'product', left(r ->> 'code', 200), v_id, true);
    else
      v_found := v_found + 1;
      insert into public.wb_import_map values (p_job, 'product', left(r ->> 'code', 200), v_id, false);
    end if;
  end loop;
  perform set_config('facturavoz.importing', 'off', true);
  return jsonb_build_object('created', v_created, 'existing', v_found);
end;
$$;

-- Comprobantes con sus líneas y cobros (máx. 300 por llamada). Idempotente: tipo|número ya importado → se omite.
create or replace function private.wb_import_docs_impl(p_job uuid, p_docs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.wb_imports := private.wb_job(p_job);
  d jsonb;
  l jsonb;
  v_id uuid;
  v_client uuid;
  v_key text;
  v_rate numeric;
  v_base numeric; v_tax numeric; v_total numeric; v_paid numeric;
  v_kind text;
  v_pos integer;
  v_lbase numeric;
  v_qty numeric;
  v_method text;
  v_done integer := 0;
  v_dup integer := 0;
begin
  if jsonb_typeof(p_docs) <> 'array' or jsonb_array_length(p_docs) > 300 then raise exception 'Bloque no válido' using errcode = '22023'; end if;
  perform set_config('facturavoz.importing', 'on', true);
  perform set_config('facturavoz.internal', 'on', true);
  for d in select * from jsonb_array_elements(p_docs) loop
    v_kind := d ->> 'kind';
    continue when v_kind not in ('factura', 'boleta', 'nota_credito', 'nota_venta') or coalesce(d ->> 'number', '') = ''
      or (d ->> 'issue') !~ '^\d{4}-\d{2}-\d{2}$';
    v_key := left(v_kind || '|' || (d ->> 'number'), 90);
    if exists (select 1 from public.invoices i where i.org_id = j.org_id and (i.import_key = v_key or i.number = left(d ->> 'number', 60))) then
      v_dup := v_dup + 1;
      continue;
    end if;
    select m.target_id into v_client from public.wb_import_map m where m.job_id = p_job and m.kind = 'client' and m.ext = left(d ->> 'client_ref', 200);
    v_total := round(abs(coalesce((d ->> 'total')::numeric, 0)), 2);
    v_base := round(abs(coalesce((d ->> 'base')::numeric, v_total)), 2);
    v_tax := round(abs(coalesce((d ->> 'tax')::numeric, 0)), 2);
    v_rate := case when v_base > 0 and v_tax > 0 then least(round(v_tax / v_base * 100, 2), 100) else 0 end;
    if v_rate between 17.5 and 18.5 then v_rate := 18; elsif v_rate between 9.5 and 10.5 then v_rate := 10; end if;
    v_paid := round(least(greatest(coalesce((d ->> 'paid')::numeric, 0), 0), v_total), 2);

    insert into public.invoices (user_id, org_id, client_id, number, issue_date, due_date, tax_rate, status, currency, notes,
                                 doc_kind, voided_at, void_reason, import_job_id, import_key, amt_discount, amt_base, amt_tax, amt_total, totals_locked)
    values (j.user_id, j.org_id, v_client, left(d ->> 'number', 60), (d ->> 'issue')::date,
            case when (d ->> 'due') ~ '^\d{4}-\d{2}-\d{2}$' and (d ->> 'due')::date >= (d ->> 'issue')::date then (d ->> 'due')::date end,
            v_rate,
            case when v_kind = 'nota_credito' or coalesce((d ->> 'voided')::boolean, false) or v_paid >= v_total - 0.004 then 'paid' else 'sent' end,
            case when upper(coalesce(d ->> 'currency', 'PEN')) ~ '^[A-Z]{3}$' then upper(coalesce(d ->> 'currency', 'PEN')) else 'PEN' end,
            'Importada', v_kind,
            case when coalesce((d ->> 'voided')::boolean, false) then now() end,
            case when coalesce((d ->> 'voided')::boolean, false) then 'Anulada en el sistema anterior' end,
            p_job, v_key, round(abs(coalesce((d ->> 'discount')::numeric, 0)), 2), v_base, v_tax, v_total, true)
    returning id into v_id;

    v_pos := 0;
    for l in select * from jsonb_array_elements(coalesce(d -> 'lines', '[]'::jsonb)) loop
      v_qty := greatest(round(abs(coalesce((l ->> 'qty')::numeric, 1)), 2), 0.01);
      v_lbase := round(abs(coalesce((l ->> 'total')::numeric, 0)) / (1 + v_rate / 100), 2);
      insert into public.invoice_items (user_id, invoice_id, description, quantity, unit_price, position)
      values (j.user_id, v_id, left(coalesce(nullif(btrim(l ->> 'description'), ''), 'Ítem importado'), 500), least(v_qty, 9999999999),
              round(v_lbase / v_qty, 2), v_pos);
      v_pos := v_pos + 1;
    end loop;

    -- El cobro: lo que el archivo dice que se pagó. La fecha real del pago no viene en el archivo: se usa la de emisión.
    if v_kind <> 'nota_credito' and not coalesce((d ->> 'voided')::boolean, false) and v_paid > 0 then
      v_method := lower(coalesce(d ->> 'method', ''));
      v_method := case when v_method like '%efectivo%' then 'efectivo' when v_method like '%yape%' then 'yape' when v_method like '%plin%' then 'plin'
                       when v_method like '%transfer%' or v_method like '%deposito%' or v_method like '%depósito%' then 'transferencia'
                       when v_method like '%tarjeta%' or v_method like '%pos%' then 'tarjeta' else 'otro' end;
      insert into public.payments (org_id, invoice_id, user_id, amount, paid_on, method, note)
      values (j.org_id, v_id, j.user_id, v_paid, (d ->> 'issue')::date, v_method, 'Importado (fecha de pago no informada)');
    end if;
    insert into public.wb_import_map values (p_job, 'invoice', v_key, v_id, true) on conflict do nothing;
    v_done := v_done + 1;
  end loop;

  -- Notas de crédito → comprobante que modifican (si está en la empresa)
  update public.invoices nc set related_invoice_id = o.id
    from jsonb_array_elements(p_docs) x(d), public.invoices o
   where x.d ->> 'kind' = 'nota_credito' and coalesce(x.d ->> 'related_number', '') <> ''
     and nc.org_id = j.org_id and nc.import_key = left('nota_credito|' || (x.d ->> 'number'), 90) and nc.related_invoice_id is null
     and o.org_id = j.org_id and o.number = x.d ->> 'related_number';
  perform set_config('facturavoz.internal', 'off', true);
  perform set_config('facturavoz.importing', 'off', true);
  return jsonb_build_object('imported', v_done, 'duplicates', v_dup);
end;
$$;

-- Fin: cuenta lo que quedó EN LA BASE y lo compara con lo esperado (vista previa).
create or replace function private.wb_import_finish_impl(p_job uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.wb_imports := private.wb_job(p_job);
  v_res jsonb;
begin
  select jsonb_build_object(
    'clients_created', (select count(*) from public.wb_import_map m where m.job_id = p_job and m.kind = 'client' and m.created),
    'clients_existing', (select count(*) from public.wb_import_map m where m.job_id = p_job and m.kind = 'client' and not m.created),
    'products_created', (select count(*) from public.wb_import_map m where m.job_id = p_job and m.kind = 'product' and m.created),
    'products_existing', (select count(*) from public.wb_import_map m where m.job_id = p_job and m.kind = 'product' and not m.created),
    'documents', (select count(*) from public.invoices i where i.import_job_id = p_job),
    'facturas', (select count(*) from public.invoices i where i.import_job_id = p_job and i.doc_kind = 'factura'),
    'boletas', (select count(*) from public.invoices i where i.import_job_id = p_job and i.doc_kind = 'boleta'),
    'credit_notes', (select count(*) from public.invoices i where i.import_job_id = p_job and i.doc_kind = 'nota_credito'),
    'voided', (select count(*) from public.invoices i where i.import_job_id = p_job and i.voided_at is not null),
    'lines', (select count(*) from public.invoice_items it join public.invoices i on i.id = it.invoice_id where i.import_job_id = p_job),
    'net', coalesce((select jsonb_object_agg(x.currency, x.t) from (
        select i.currency, round(sum(case when i.doc_kind = 'nota_credito' then -i.amt_total else i.amt_total end), 2) as t
        from public.invoices i where i.import_job_id = p_job and i.voided_at is null group by i.currency) x), '{}'::jsonb),
    'collected', coalesce((select jsonb_object_agg(x.currency, x.t) from (
        select i.currency, round(sum(p.amount), 2) as t
        from public.payments p join public.invoices i on i.id = p.invoice_id where i.import_job_id = p_job group by i.currency) x), '{}'::jsonb)
  ) into v_res;
  update public.wb_imports set status = 'done', result = v_res, finished_at = now() where id = p_job;
  perform private.audit(j.org_id, 'importacion.libro', 'wb_imports', p_job::text,
    jsonb_build_object('archivo', j.file_name, 'comprobantes', v_res -> 'documents', 'clientes', v_res -> 'clients_created'));
  return v_res;
end;
$$;

-- Deshacer: borra SOLO lo que esta importación creó (comprobantes, sus líneas y cobros; clientes y productos nuevos
-- que no se usen en otra parte). Lo que ya existía antes no se toca.
create or replace function private.wb_import_undo_impl(p_job uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.wb_imports;
  v_inv integer;
  v_cli integer;
  v_prod integer;
begin
  select * into j from public.wb_imports where id = p_job for update;
  if not found or not private.is_org_admin(j.org_id) then raise exception 'Solo el dueño o un administrador puede deshacer una importación' using errcode = '42501'; end if;
  if j.status = 'undone' then return jsonb_build_object('already', true); end if;
  perform set_config('facturavoz.importing', 'on', true);
  perform set_config('facturavoz.internal', 'on', true);
  update public.invoices set related_invoice_id = null where related_invoice_id in (select id from public.invoices where import_job_id = p_job);
  delete from public.invoices i where i.import_job_id = p_job and i.org_id = j.org_id;
  get diagnostics v_inv = row_count;
  delete from public.clients c
   using public.wb_import_map m
   where m.job_id = p_job and m.kind = 'client' and m.created and c.id = m.target_id and c.org_id = j.org_id
     and not exists (select 1 from public.invoices i where i.client_id = c.id)
     and not exists (select 1 from public.quotes q where q.client_id = c.id);
  get diagnostics v_cli = row_count;
  delete from public.products p
   using public.wb_import_map m
   where m.job_id = p_job and m.kind = 'product' and m.created and p.id = m.target_id and p.org_id = j.org_id;
  get diagnostics v_prod = row_count;
  perform set_config('facturavoz.internal', 'off', true);
  perform set_config('facturavoz.importing', 'off', true);
  update public.wb_imports set status = 'undone', undone_at = now() where id = p_job;
  perform private.audit(j.org_id, 'importacion.deshecha', 'wb_imports', p_job::text,
    jsonb_build_object('comprobantes', v_inv, 'clientes', v_cli, 'productos', v_prod));
  return jsonb_build_object('invoices', v_inv, 'clients', v_cli, 'products', v_prod);
end;
$$;

-- Envoltorios públicos (SECURITY INVOKER) que llama la app
create or replace function public.wb_import_begin(p_org uuid, p_file text, p_expected jsonb, p_warnings jsonb default '[]'::jsonb)
returns uuid language sql security invoker set search_path = '' as $$ select private.wb_import_begin_impl(p_org, p_file, p_expected, p_warnings) $$;
create or replace function public.wb_import_clients(p_job uuid, p_rows jsonb)
returns jsonb language sql security invoker set search_path = '' as $$ select private.wb_import_clients_impl(p_job, p_rows) $$;
create or replace function public.wb_import_products(p_job uuid, p_rows jsonb)
returns jsonb language sql security invoker set search_path = '' as $$ select private.wb_import_products_impl(p_job, p_rows) $$;
create or replace function public.wb_import_docs(p_job uuid, p_docs jsonb)
returns jsonb language sql security invoker set search_path = '' as $$ select private.wb_import_docs_impl(p_job, p_docs) $$;
create or replace function public.wb_import_finish(p_job uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.wb_import_finish_impl(p_job) $$;
create or replace function public.wb_import_undo(p_job uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.wb_import_undo_impl(p_job) $$;

revoke execute on function private.wb_job(uuid, text), private.wb_import_begin_impl(uuid, text, jsonb, jsonb),
  private.wb_import_clients_impl(uuid, jsonb), private.wb_import_products_impl(uuid, jsonb), private.wb_import_docs_impl(uuid, jsonb),
  private.wb_import_finish_impl(uuid), private.wb_import_undo_impl(uuid) from public, anon;
grant execute on function private.wb_job(uuid, text), private.wb_import_begin_impl(uuid, text, jsonb, jsonb),
  private.wb_import_clients_impl(uuid, jsonb), private.wb_import_products_impl(uuid, jsonb), private.wb_import_docs_impl(uuid, jsonb),
  private.wb_import_finish_impl(uuid), private.wb_import_undo_impl(uuid) to authenticated;
revoke execute on function public.wb_import_begin(uuid, text, jsonb, jsonb), public.wb_import_clients(uuid, jsonb),
  public.wb_import_products(uuid, jsonb), public.wb_import_docs(uuid, jsonb), public.wb_import_finish(uuid), public.wb_import_undo(uuid) from public, anon;
grant execute on function public.wb_import_begin(uuid, text, jsonb, jsonb), public.wb_import_clients(uuid, jsonb),
  public.wb_import_products(uuid, jsonb), public.wb_import_docs(uuid, jsonb), public.wb_import_finish(uuid), public.wb_import_undo(uuid) to authenticated;

-- El Copiloto usa la MISMA regla de ventas
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
    -- MISMA regla que Inicio y Reportes (private.sale_rows): anuladas fuera, notas de crédito restan.
    select s.id, s.client_id, s.issue_date, s.due_date, s.status, s.total
    from private.sale_rows(p_org, null, null, v_cur) s
    where s.issue_date >= v_today - 120 or (s.status = 'sent' and s.total > 0)
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
        where j.issue_date >= v_today - 90 and j.total > 0
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
        where p.org_id = p_org and i.currency = v_cur and p.paid_on >= v_month and i.voided_at is null),
    'credit_notes_this_month', (select round(coalesce(-sum(total), 0), 2) from j where issue_date >= v_month and total < 0),
    'sales_rule', 'ventas = emitidos y pagados en ' || v_cur || ', sin anulados ni rechazados por SUNAT, menos notas de crédito',
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

commit;

notify pgrst, 'reload schema';
