-- FacturaVoz · Migración 18 · Módulos revolucionarios (Fase 8, parte 1: dinero y control)
--   2  Libreta de fiados              → credit_ledger + credit_balances()
--   3  Cierre del día en un toque      → cash_movements + day_closings + day_summary()
--   5  Dueño a distancia y antifraude  → audit_log (encadenada, solo inserción) + owner_alerts + PIN de administrador
--   6  Papelera y deshacer (30 días)   → trash + restore_trash() (todas las eliminaciones pasan por aquí)
--   9  Puntaje de pago                 → (ya existe client_payment_stats; se usa para el límite de crédito)
--  10  Listas de precios y promociones → promotions + coupons (precio por mayor está en products)
--  11  Fidelización                    → loyalty_ledger (+ puntos automáticos al cobrar) + loyalty_balances()
--  15  Conciliación bancaria básica    → bank_lines
--  17  Comisiones y metas por vendedor → seller_ranking()
--  18  Avisos de pago Yape/Plin        → payment_notices
--  19  Multimoneda                     → fx_rates + invoices.exchange_rate
-- Idempotente y aditiva. Ejecutar después de 20261108.
begin;

-- ═════════════ 2) FIADOS ═════════════
create table if not exists public.credit_ledger (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  kind text not null check (kind in ('cargo', 'abono')),
  amount numeric(14,2) not null check (amount > 0 and amount <= 10000000),
  description text check (description is null or char_length(description) <= 200),
  due_date date,
  method text check (method is null or method in ('efectivo', 'yape', 'plin', 'transferencia', 'tarjeta', 'otro')),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_credit_ledger_client on public.credit_ledger(client_id, created_at);
create index if not exists idx_credit_ledger_org on public.credit_ledger(org_id, created_at desc);
create index if not exists idx_credit_ledger_user on public.credit_ledger(user_id);

create or replace function public.credit_balances(p_org uuid)
returns table (client_id uuid, client_name text, phone text, balance numeric, charges numeric, payments numeric,
               last_move timestamptz, oldest_due date, credit_limit numeric)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.name, c.phone,
         coalesce(sum(case when l.kind = 'cargo' then l.amount else -l.amount end), 0),
         coalesce(sum(l.amount) filter (where l.kind = 'cargo'), 0),
         coalesce(sum(l.amount) filter (where l.kind = 'abono'), 0),
         max(l.created_at),
         min(l.due_date) filter (where l.kind = 'cargo'),
         c.credit_limit
  from public.credit_ledger l join public.clients c on c.id = l.client_id
  where l.org_id = p_org
  group by c.id
  order by 4 desc;
$$;

-- ═════════════ 3) CAJA Y CIERRE DEL DÍA ═════════════
create table if not exists public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  day date not null default ((now() at time zone 'America/Lima')::date),
  kind text not null check (kind in ('apertura', 'ingreso', 'egreso')),
  amount numeric(14,2) not null check (amount >= 0 and amount <= 10000000),
  method text not null default 'efectivo' check (method in ('efectivo', 'yape', 'plin', 'transferencia', 'tarjeta', 'otro')),
  note text check (note is null or char_length(note) <= 200),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_cash_movements_org_day on public.cash_movements(org_id, day);
create index if not exists idx_cash_movements_user on public.cash_movements(user_id);

create table if not exists public.day_closings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  day date not null,
  summary jsonb not null check (jsonb_typeof(summary) = 'object' and pg_column_size(summary) < 20000),
  expected_cash numeric(14,2) not null default 0,
  counted_cash numeric(14,2),
  difference numeric(14,2) generated always as (coalesce(counted_cash, expected_cash) - expected_cash) stored,
  note text check (note is null or char_length(note) <= 300),
  closed_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (org_id, day)
);
create index if not exists idx_day_closings_closed_by on public.day_closings(closed_by);

-- Resumen del día: ventas emitidas, cobros por medio de pago, fiados, movimientos de caja y (si puede verlos) gastos.
create or replace function public.day_summary(p_org uuid, p_day date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_cur text;
  v_sales jsonb;
  v_pay jsonb;
  v_cash_in numeric;
  v_open numeric;
  v_in numeric;
  v_out numeric;
  v_fiado_c numeric;
  v_fiado_a numeric;
  v_fiado_cash numeric;
  v_exp numeric;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  select coalesce(o.currency, 'PEN') into v_cur from public.organizations o where o.id = p_org;
  v_sales := public.sales_summary(p_org, p_day, p_day + 1, v_cur);
  select coalesce(jsonb_object_agg(method, total), '{}'::jsonb) into v_pay
    from (select p.method, sum(p.amount) as total from public.payments p where p.org_id = p_org and p.paid_on = p_day group by p.method) x;
  select coalesce(sum(p.amount), 0) into v_cash_in from public.payments p where p.org_id = p_org and p.paid_on = p_day and p.method = 'efectivo';
  select coalesce(sum(amount) filter (where kind = 'apertura'), 0),
         coalesce(sum(amount) filter (where kind = 'ingreso' and method = 'efectivo'), 0),
         coalesce(sum(amount) filter (where kind = 'egreso' and method = 'efectivo'), 0)
    into v_open, v_in, v_out
    from public.cash_movements where org_id = p_org and day = p_day;
  select coalesce(sum(amount) filter (where kind = 'cargo'), 0), coalesce(sum(amount) filter (where kind = 'abono'), 0),
         coalesce(sum(amount) filter (where kind = 'abono' and coalesce(method, 'efectivo') = 'efectivo'), 0)
    into v_fiado_c, v_fiado_a, v_fiado_cash
    from public.credit_ledger where org_id = p_org and (created_at at time zone 'America/Lima')::date = p_day;
  select case when private.can_finance(p_org) then coalesce(sum(total), 0) end into v_exp
    from public.expenses where org_id = p_org and spent_on = p_day and currency = v_cur;
  return jsonb_build_object(
    'day', p_day, 'currency', v_cur,
    'sales', v_sales,
    'payments_by_method', v_pay,
    'cash_opening', v_open, 'cash_sales', v_cash_in, 'cash_in', v_in, 'cash_out', v_out,
    'fiado_charged', v_fiado_c, 'fiado_paid', v_fiado_a,
    'expected_cash', v_open + v_cash_in + v_in + v_fiado_cash - v_out,
    'expenses', v_exp);
end;
$$;

-- ═════════════ 5) BITÁCORA INALTERABLE + ALERTAS AL DUEÑO + PIN ═════════════
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid,
  action text not null,
  entity text,
  entity_id text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  prev_hash text,
  hash text not null
);
create index if not exists idx_audit_log_org on public.audit_log(org_id, id desc);

create table if not exists public.owner_alerts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null,
  severity text not null default 'warn' check (severity in ('info', 'warn', 'bad')),
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists idx_owner_alerts_org on public.owner_alerts(org_id, created_at desc);

-- Registra un evento en la bitácora encadenada (cada fila guarda el hash de la anterior: si alguien la altera, se nota).
create or replace function private.audit(p_org uuid, p_action text, p_entity text, p_entity_id text, p_data jsonb, p_user uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text;
  v_user uuid := coalesce(p_user, (select auth.uid()));
  v_at timestamptz := clock_timestamp();
  v_data jsonb := coalesce(p_data, '{}'::jsonb);
begin
  if p_org is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('audit:' || p_org::text, 0));
  select a.hash into v_prev from public.audit_log a where a.org_id = p_org order by a.id desc limit 1;
  insert into public.audit_log (org_id, user_id, action, entity, entity_id, data, created_at, prev_hash, hash)
  values (p_org, v_user, p_action, p_entity, p_entity_id, v_data, v_at, v_prev,
          encode(sha256(convert_to(concat_ws('|', coalesce(v_prev, ''), p_org::text, coalesce(v_user::text, ''), p_action,
                                             coalesce(p_entity, ''), coalesce(p_entity_id, ''), v_data::text, v_at::text), 'UTF8')), 'hex'));
end;
$$;

create or replace function private.alert(p_org uuid, p_kind text, p_severity text, p_title text, p_body text, p_data jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.owner_alerts (org_id, kind, severity, title, body, data)
  values (p_org, p_kind, p_severity, left(p_title, 140), left(p_body, 500), coalesce(p_data, '{}'::jsonb));
$$;

-- Verifica que la bitácora no fue alterada. Devuelve el id de la primera fila rota, o null si todo está bien.
create or replace function public.audit_verify(p_org uuid)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r record;
  v_prev text := null;
begin
  if not private.is_org_admin(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  for r in select * from public.audit_log where org_id = p_org order by id loop
    if r.prev_hash is distinct from v_prev or r.hash <> encode(sha256(convert_to(concat_ws('|', coalesce(r.prev_hash, ''), r.org_id::text,
         coalesce(r.user_id::text, ''), r.action, coalesce(r.entity, ''), coalesce(r.entity_id, ''), r.data::text, r.created_at::text), 'UTF8')), 'hex') then
      return r.id;
    end if;
    v_prev := r.hash;
  end loop;
  return null;
end;
$$;

-- PIN de administrador para acciones críticas (anular, borrar cobros). Se guarda solo el hash con sal.
create table if not exists public.org_security (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  pin_hash text,
  pin_salt text,
  failed integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
create table if not exists public.pin_grants (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  primary key (org_id, user_id)
);
create index if not exists idx_pin_grants_user on public.pin_grants(user_id);

create or replace function private.set_admin_pin_impl(p_org uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_salt text := replace(gen_random_uuid()::text, '-', '');
begin
  if not private.is_org_admin(p_org) then raise exception 'Solo el propietario o un administrador' using errcode = '42501'; end if;
  if p_pin is null then
    insert into public.org_security (org_id, pin_hash, pin_salt) values (p_org, null, null)
    on conflict (org_id) do update set pin_hash = null, pin_salt = null, failed = 0, locked_until = null, updated_at = now();
    perform private.audit(p_org, 'pin.desactivado', 'org', p_org::text, '{}'::jsonb);
    return;
  end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'El PIN debe tener de 4 a 8 dígitos' using errcode = '22023'; end if;
  insert into public.org_security (org_id, pin_hash, pin_salt) values (p_org, encode(sha256(convert_to(v_salt || ':' || p_pin, 'UTF8')), 'hex'), v_salt)
  on conflict (org_id) do update set pin_hash = excluded.pin_hash, pin_salt = excluded.pin_salt, failed = 0, locked_until = null, updated_at = now();
  perform private.audit(p_org, 'pin.cambiado', 'org', p_org::text, '{}'::jsonb);
end;
$$;

-- Verifica el PIN y concede 5 minutos para acciones críticas. 5 intentos fallidos bloquean 15 minutos.
create or replace function private.verify_admin_pin_impl(p_org uuid, p_pin text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare s public.org_security;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  select * into s from public.org_security where org_id = p_org for update;
  if not found or s.pin_hash is null then return true; end if;
  if s.locked_until is not null and s.locked_until > now() then
    raise exception 'Demasiados intentos. Espera unos minutos.' using errcode = 'P0001';
  end if;
  if encode(sha256(convert_to(s.pin_salt || ':' || coalesce(p_pin, ''), 'UTF8')), 'hex') = s.pin_hash then
    update public.org_security set failed = 0, locked_until = null where org_id = p_org;
    insert into public.pin_grants (org_id, user_id, expires_at) values (p_org, (select auth.uid()), now() + interval '5 minutes')
    on conflict (org_id, user_id) do update set expires_at = excluded.expires_at;
    return true;
  end if;
  update public.org_security set failed = failed + 1,
    locked_until = case when failed + 1 >= 5 then now() + interval '15 minutes' end where org_id = p_org;
  perform private.audit(p_org, 'pin.fallido', 'org', p_org::text, '{}'::jsonb);
  if s.failed + 1 >= 3 then
    perform private.alert(p_org, 'pin_fallido', 'bad', 'Intentos fallidos de PIN', 'Alguien del equipo falló el PIN de administrador varias veces.', '{}'::jsonb);
  end if;
  return false;
end;
$$;

-- ¿Puede hacer una acción crítica ahora? (sin PIN configurado, o es admin, o validó el PIN hace < 5 min)
create or replace function private.pin_ok(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_org_admin(p_org)
      or not exists (select 1 from public.org_security s where s.org_id = p_org and s.pin_hash is not null)
      or exists (select 1 from public.pin_grants g where g.org_id = p_org and g.user_id = (select auth.uid()) and g.expires_at > now());
$$;

create or replace function private.pin_status_impl(p_org uuid)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('enabled', exists (select 1 from public.org_security s where s.org_id = p_org and s.pin_hash is not null),
                            'ok', private.pin_ok(p_org))
  where private.is_org_member(p_org);
$$;

-- ═════════════ 6) PAPELERA (30 días) ═════════════
create table if not exists public.trash (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  table_name text not null,
  row_id uuid not null,
  label text,
  data jsonb not null,
  deleted_by uuid,
  deleted_at timestamptz not null default now(),
  restored_at timestamptz
);
create index if not exists idx_trash_org on public.trash(org_id, deleted_at desc);
create index if not exists idx_trash_row on public.trash(row_id);

-- Antes de borrar: copia la fila (y sus líneas) a la papelera, y deja huella en la bitácora.
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

do $$
declare t text;
begin
  foreach t in array array['clients', 'products', 'quotes', 'expenses', 'payments', 'jobs', 'invoices', 'credit_ledger', 'client_notes', 'client_assets', 'cash_movements'] loop
    execute format('create or replace trigger %I before delete on public.%I for each row execute function private.to_trash()', t || '_to_trash', t);
  end loop;
end $$;

create or replace function private.restore_trash_impl(p_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.trash;
  v_allowed text[] := array['clients', 'products', 'quotes', 'expenses', 'payments', 'jobs', 'invoices', 'credit_ledger', 'client_notes', 'client_assets', 'cash_movements'];
  v_item jsonb;
begin
  select * into t from public.trash where id = p_id for update;
  if not found or t.restored_at is not null then raise exception 'No está en la papelera' using errcode = 'P0002'; end if;
  if not (private.is_org_admin(t.org_id) or (t.deleted_by = (select auth.uid()) and private.is_org_member(t.org_id))) then
    raise exception 'Solo quien lo borró o un administrador puede recuperarlo' using errcode = '42501';
  end if;
  if t.deleted_at < now() - interval '30 days' then raise exception 'Pasaron más de 30 días' using errcode = 'P0001'; end if;
  if not (t.table_name = any(v_allowed)) then raise exception 'Tipo no recuperable' using errcode = '22023'; end if;
  if t.table_name = 'expenses' and not private.can_finance(t.org_id) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  begin
    execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)', t.table_name, t.table_name) using (t.data - '_items');
  exception when unique_violation then
    raise exception 'Ya existe un elemento con ese número o nombre' using errcode = '23505';
  when foreign_key_violation then
    raise exception 'Primero recupera el elemento al que pertenecía (por ejemplo, la factura)' using errcode = '23503';
  end;
  if t.table_name = 'invoices' then
    for v_item in select * from jsonb_array_elements(coalesce(t.data -> '_items', '[]'::jsonb)) loop
      insert into public.invoice_items select * from jsonb_populate_record(null::public.invoice_items, v_item) on conflict do nothing;
    end loop;
  elsif t.table_name = 'quotes' then
    for v_item in select * from jsonb_array_elements(coalesce(t.data -> '_items', '[]'::jsonb)) loop
      insert into public.quote_items select * from jsonb_populate_record(null::public.quote_items, v_item) on conflict do nothing;
    end loop;
  end if;
  update public.trash set restored_at = now() where id = p_id;
  perform private.audit(t.org_id, t.table_name || '.recuperado', t.table_name, t.row_id::text, jsonb_build_object('label', t.label));
  return t.table_name;
end;
$$;

-- ═════════════ 10) PROMOCIONES Y CUPONES ═════════════
create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  kind text not null check (kind in ('porcentaje', 'monto', 'volumen', 'combo')),
  value numeric(12,2) not null check (value > 0 and value <= 10000000),
  product_ids uuid[] not null default '{}',
  min_qty numeric(12,2) check (min_qty is null or min_qty between 1 and 100000),
  starts_on date,
  ends_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on),
  check (kind <> 'porcentaje' or value <= 100)
);
create index if not exists idx_promotions_org on public.promotions(org_id);

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9\-]{3,20}$'),
  kind text not null check (kind in ('porcentaje', 'monto')),
  value numeric(12,2) not null check (value > 0 and value <= 10000000),
  max_uses integer check (max_uses is null or max_uses between 1 and 1000000),
  uses integer not null default 0,
  expires_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (kind <> 'porcentaje' or value <= 100)
);
create unique index if not exists coupons_org_code_key on public.coupons(org_id, code);

create or replace function private.use_coupon_impl(p_org uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare c public.coupons;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  select * into c from public.coupons where org_id = p_org and code = upper(btrim(coalesce(p_code, ''))) for update;
  if not found or not c.active then raise exception 'Cupón no válido' using errcode = 'P0002'; end if;
  if c.expires_on is not null and c.expires_on < (now() at time zone 'America/Lima')::date then raise exception 'Cupón vencido' using errcode = 'P0001'; end if;
  if c.max_uses is not null and c.uses >= c.max_uses then raise exception 'Cupón agotado' using errcode = 'P0001'; end if;
  update public.coupons set uses = uses + 1 where id = c.id;
  return jsonb_build_object('kind', c.kind, 'value', c.value, 'code', c.code);
end;
$$;

-- ═════════════ 11) FIDELIZACIÓN ═════════════
create table if not exists public.loyalty_ledger (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  points integer not null check (points <> 0 and points between -1000000 and 1000000),
  reason text check (reason is null or char_length(reason) <= 120),
  invoice_id uuid references public.invoices(id) on delete set null,
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_loyalty_client on public.loyalty_ledger(client_id);
create index if not exists idx_loyalty_org on public.loyalty_ledger(org_id);
create index if not exists idx_loyalty_invoice on public.loyalty_ledger(invoice_id);
create index if not exists idx_loyalty_user on public.loyalty_ledger(user_id);

-- Puntos automáticos al registrar un cobro (si el negocio activó la fidelización).
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
create or replace trigger payments_loyalty after insert on public.payments for each row execute function private.loyalty_on_payment();

create or replace function public.loyalty_balances(p_org uuid)
returns table (client_id uuid, client_name text, phone text, points bigint)
language sql stable security invoker set search_path = ''
as $$
  select c.id, c.name, c.phone, sum(l.points)
  from public.loyalty_ledger l join public.clients c on c.id = l.client_id
  where l.org_id = p_org group by c.id having sum(l.points) <> 0 order by 4 desc;
$$;

-- ═════════════ 15) CONCILIACIÓN BANCARIA ═════════════
create table if not exists public.bank_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  line_date date not null,
  description text not null default '' check (char_length(description) <= 300),
  amount numeric(14,2) not null check (amount <> 0 and abs(amount) <= 1000000000),
  reference text check (reference is null or char_length(reference) <= 80),
  fingerprint text not null,
  status text not null default 'pendiente' check (status in ('pendiente', 'conciliado', 'ignorado')),
  payment_id uuid references public.payments(id) on delete set null,
  invoice_id uuid references public.invoices(id) on delete set null,
  batch text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists bank_lines_org_fp_key on public.bank_lines(org_id, fingerprint);
create index if not exists idx_bank_lines_org on public.bank_lines(org_id, line_date desc);
create index if not exists idx_bank_lines_payment on public.bank_lines(payment_id);
create index if not exists idx_bank_lines_invoice on public.bank_lines(invoice_id);
create index if not exists idx_bank_lines_created_by on public.bank_lines(created_by);

-- ═════════════ 17) COMISIONES Y METAS POR VENDEDOR ═════════════
create or replace function private.seller_ranking_impl(p_org uuid, p_from date, p_to date)
returns table (user_id uuid, name text, sales_count bigint, sales_total numeric, commission_pct numeric, commission numeric, goal numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_all boolean := private.can_finance(p_org);
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  return query
    with s as (
      select i.user_id as uid, count(*) as n,
             sum((select coalesce(sum(round(round(it.quantity, 2) * round(it.unit_price, 2), 2)), 0) from public.invoice_items it where it.invoice_id = i.id)) as total
      from public.invoices i
      left join public.fiscal_documents fd on fd.invoice_id = i.id
      where i.org_id = p_org and i.issue_date >= p_from and i.issue_date < p_to and i.status in ('sent', 'paid')
        and coalesce(fd.status, '') <> 'rejected' and not private.invoice_voided(i.id)
      group by i.user_id)
    select m.user_id, coalesce(m.display_name, split_part(u.email::text, '@', 1)), coalesce(s.n, 0), coalesce(s.total, 0),
           m.commission_pct, round(coalesce(s.total, 0) * coalesce(m.commission_pct, 0) / 100, 2), m.sales_goal
    from public.organization_members m
    join auth.users u on u.id = m.user_id
    left join s on s.uid = m.user_id
    where m.org_id = p_org and (v_all or m.user_id = (select auth.uid()))
    order by 4 desc;
end;
$$;

-- ═════════════ 18) AVISOS DE PAGO (Yape/Plin) ═════════════
create table if not exists public.payment_notices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  app text not null check (app in ('yape', 'plin', 'banco', 'otro')),
  amount numeric(14,2) not null check (amount > 0 and amount <= 10000000),
  payer text check (payer is null or char_length(payer) <= 120),
  operation_code text check (operation_code is null or char_length(operation_code) <= 40),
  raw_text text check (raw_text is null or char_length(raw_text) <= 500),
  received_at timestamptz not null default now(),
  status text not null default 'nuevo' check (status in ('nuevo', 'aplicado', 'descartado')),
  invoice_id uuid references public.invoices(id) on delete set null,
  payment_id uuid references public.payments(id) on delete set null,
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists payment_notices_op_key on public.payment_notices(org_id, app, operation_code) where operation_code is not null;
create index if not exists idx_payment_notices_org on public.payment_notices(org_id, created_at desc);
create index if not exists idx_payment_notices_invoice on public.payment_notices(invoice_id);
create index if not exists idx_payment_notices_payment on public.payment_notices(payment_id);
create index if not exists idx_payment_notices_user on public.payment_notices(user_id);

-- ═════════════ 19) MULTIMONEDA ═════════════
create table if not exists public.fx_rates (
  day date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  buy numeric(10,4) check (buy is null or buy > 0),
  sell numeric(10,4) check (sell is null or sell > 0),
  source text not null default 'sunat',
  fetched_at timestamptz not null default now(),
  primary key (day, currency)
);
alter table public.invoices add column if not exists exchange_rate numeric(10,4);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'invoices_fx_chk') then
    alter table public.invoices add constraint invoices_fx_chk check (exchange_rate is null or exchange_rate between 0.0001 and 100000);
  end if;
end $$;

-- ═════════════ RLS de todo lo anterior ═════════════
alter table public.credit_ledger enable row level security;
alter table public.cash_movements enable row level security;
alter table public.day_closings enable row level security;
alter table public.audit_log enable row level security;
alter table public.owner_alerts enable row level security;
alter table public.org_security enable row level security;
alter table public.pin_grants enable row level security;
alter table public.trash enable row level security;
alter table public.promotions enable row level security;
alter table public.coupons enable row level security;
alter table public.loyalty_ledger enable row level security;
alter table public.bank_lines enable row level security;
alter table public.payment_notices enable row level security;
alter table public.fx_rates enable row level security;

do $$
declare r record;
begin
  for r in
    select * from (values
      ('credit_ledger', 'credit_ledger_select', 'select', 'private.is_org_member(org_id) and not private.is_tech(org_id)', null),
      ('credit_ledger', 'credit_ledger_insert', 'insert', null, 'private.is_org_member(org_id) and not private.is_tech(org_id) and user_id = (select auth.uid())'),
      ('credit_ledger', 'credit_ledger_delete', 'delete', 'private.is_org_admin(org_id) or (user_id = (select auth.uid()) and created_at > now() - interval ''1 day'')', null),
      ('cash_movements', 'cash_movements_select', 'select', 'private.is_org_member(org_id) and not private.is_tech(org_id)', null),
      ('cash_movements', 'cash_movements_insert', 'insert', null, 'private.is_org_member(org_id) and not private.is_tech(org_id) and user_id = (select auth.uid())'),
      ('cash_movements', 'cash_movements_delete', 'delete', 'private.is_org_admin(org_id)', null),
      ('day_closings', 'day_closings_select', 'select', 'private.can_finance(org_id) or closed_by = (select auth.uid())', null),
      ('day_closings', 'day_closings_insert', 'insert', null, 'private.is_org_member(org_id) and not private.is_tech(org_id) and closed_by = (select auth.uid())'),
      ('day_closings', 'day_closings_update', 'update', 'private.can_finance(org_id) or closed_by = (select auth.uid())', 'private.is_org_member(org_id)'),
      ('audit_log', 'audit_log_select', 'select', 'private.is_org_admin(org_id)', null),
      ('owner_alerts', 'owner_alerts_select', 'select', 'private.is_org_admin(org_id)', null),
      ('owner_alerts', 'owner_alerts_update', 'update', 'private.is_org_admin(org_id)', 'private.is_org_admin(org_id)'),
      ('trash', 'trash_select', 'select', 'private.is_org_admin(org_id) or (deleted_by = (select auth.uid()) and private.is_org_member(org_id))', null),
      ('promotions', 'promotions_select', 'select', 'private.is_org_member(org_id)', null),
      ('promotions', 'promotions_write', 'all', 'private.can_finance(org_id)', 'private.can_finance(org_id)'),
      ('coupons', 'coupons_select', 'select', 'private.is_org_member(org_id)', null),
      ('coupons', 'coupons_write', 'all', 'private.can_finance(org_id)', 'private.can_finance(org_id)'),
      ('loyalty_ledger', 'loyalty_select', 'select', 'private.is_org_member(org_id) and not private.is_tech(org_id)', null),
      ('loyalty_ledger', 'loyalty_insert', 'insert', null, 'private.is_org_member(org_id) and not private.is_tech(org_id)'),
      ('bank_lines', 'bank_lines_all', 'all', 'private.can_finance(org_id)', 'private.can_finance(org_id)'),
      ('payment_notices', 'payment_notices_all', 'all', 'private.is_org_member(org_id) and not private.is_tech(org_id)', 'private.is_org_member(org_id) and not private.is_tech(org_id)'),
      ('fx_rates', 'fx_rates_select', 'select', 'true', null)
    ) as t(tbl, pol, cmd, use_expr, check_expr)
  loop
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = r.tbl and policyname = r.pol) then
      execute format('create policy %I on public.%I for %s to authenticated %s %s', r.pol, r.tbl, r.cmd,
        case when r.use_expr is null then '' else 'using (' || r.use_expr || ')' end,
        case when r.check_expr is null then '' else 'with check (' || r.check_expr || ')' end);
    end if;
  end loop;
end $$;

-- Pago borrado: exige PIN (si la empresa lo configuró) — se suma a la política existente.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'payments' and policyname = 'pin_payments_delete') then
    create policy "pin_payments_delete" on public.payments as restrictive for delete to authenticated using (private.pin_ok(org_id));
  end if;
end $$;

revoke all on public.credit_ledger, public.cash_movements, public.day_closings, public.audit_log, public.owner_alerts,
  public.org_security, public.pin_grants, public.trash, public.promotions, public.coupons, public.loyalty_ledger,
  public.bank_lines, public.payment_notices, public.fx_rates from anon, authenticated;
grant select, insert, delete on public.credit_ledger, public.cash_movements to authenticated;
grant select, insert on public.day_closings to authenticated;
grant update (org_id, day, summary, expected_cash, counted_cash, note, closed_by) on public.day_closings to authenticated;
grant select on public.audit_log, public.trash, public.fx_rates to authenticated;
grant select on public.owner_alerts to authenticated;
grant update (read_at) on public.owner_alerts to authenticated;
grant select, insert, update, delete on public.promotions, public.coupons, public.bank_lines, public.payment_notices to authenticated;
grant select, insert on public.loyalty_ledger to authenticated;
-- org_security y pin_grants: sin acceso directo (solo funciones)
grant select, insert, update, delete on public.credit_ledger, public.cash_movements, public.day_closings, public.audit_log,
  public.owner_alerts, public.org_security, public.pin_grants, public.trash, public.promotions, public.coupons,
  public.loyalty_ledger, public.bank_lines, public.payment_notices, public.fx_rates to service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;

-- ═════════════ Disparadores de antifraude y bitácora ═════════════
create or replace function private.watch_invoices()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    perform private.audit(new.org_id, 'factura.estado', 'invoices', new.id::text, jsonb_build_object('de', old.status, 'a', new.status, 'numero', new.number));
  end if;
  return new;
end;
$$;
create or replace trigger invoices_watch after update on public.invoices for each row execute function private.watch_invoices();

create or replace function private.watch_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.audit(new.org_id, 'cobro.registrado', 'payments', new.id::text, jsonb_build_object('monto', new.amount, 'medio', new.method, 'factura', new.invoice_id), new.user_id);
  return new;
end;
$$;
create or replace trigger payments_watch after insert on public.payments for each row execute function private.watch_payments();

-- Anulación (nota de crédito): siempre se avisa al dueño.
create or replace function private.watch_notes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.audit(new.org_id, 'comprobante.anulado', 'fiscal_notes', new.invoice_id::text,
    jsonb_build_object('serie', new.series, 'numero', new.correlative, 'motivo', new.reason_text), new.user_id);
  perform private.alert(new.org_id, 'anulacion', 'bad', 'Se anuló un comprobante',
    'Nota de crédito ' || new.series || '-' || lpad(new.correlative::text, 8, '0') || coalesce(' · ' || new.reason_text, ''),
    jsonb_build_object('invoice_id', new.invoice_id));
  return new;
end;
$$;
create or replace trigger fiscal_notes_watch after insert on public.fiscal_notes for each row execute function private.watch_notes();

-- Descuento alto: precio de una línea 20 % (o más) por debajo del precio de catálogo, hecho por alguien que no es admin.
create or replace function private.watch_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_user uuid;
  v_price numeric;
begin
  -- Procesos automáticos (recurrentes, importación) no cuentan: solo ventas hechas por una persona del equipo.
  if (select auth.uid()) is null then return new; end if;
  select i.org_id, i.user_id into v_org, v_user from public.invoices i where i.id = new.invoice_id;
  if v_org is null or private.is_org_admin(v_org) then return new; end if;
  select p.unit_price into v_price from public.products p
   where p.org_id = v_org and lower(btrim(p.name)) = lower(btrim(new.description)) and p.unit_price > 0 limit 1;
  if v_price is not null and new.unit_price < v_price * 0.8 then
    perform private.alert(v_org, 'descuento_alto', 'warn', 'Descuento alto en una venta',
      new.description || ': ' || new.unit_price || ' (precio de lista ' || v_price || ')', jsonb_build_object('invoice_id', new.invoice_id, 'user_id', v_user));
    perform private.audit(v_org, 'venta.descuento_alto', 'invoices', new.invoice_id::text,
      jsonb_build_object('item', new.description, 'precio', new.unit_price, 'lista', v_price), v_user);
  end if;
  return new;
end;
$$;
create or replace trigger invoice_items_watch after insert on public.invoice_items for each row execute function private.watch_items();

-- Descuadre de caja al cerrar el día (más de S/ 1 de diferencia)
create or replace function private.watch_closing()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.audit(new.org_id, 'caja.cierre', 'day_closings', new.day::text,
    jsonb_build_object('esperado', new.expected_cash, 'contado', new.counted_cash, 'diferencia', new.difference), new.closed_by);
  if new.counted_cash is not null and abs(new.difference) > 1 then
    perform private.alert(new.org_id, 'descuadre_caja', 'bad', 'Descuadre de caja',
      'Cierre del ' || to_char(new.day, 'DD/MM') || ': esperado ' || new.expected_cash || ', contado ' || new.counted_cash || ' (diferencia ' || new.difference || ').',
      jsonb_build_object('day', new.day));
  end if;
  return new;
end;
$$;
create or replace trigger day_closings_watch after insert or update on public.day_closings for each row execute function private.watch_closing();

-- Cambios en el equipo
create or replace function private.watch_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  if tg_op = 'DELETE' and not exists (select 1 from public.organizations o where o.id = old.org_id) then return old; end if;
  perform private.audit((v ->> 'org_id')::uuid, 'equipo.' || lower(tg_op), 'organization_members', v ->> 'user_id',
    jsonb_build_object('rol', v ->> 'role', 'rol_operativo', v ->> 'staff_role'));
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
create or replace trigger organization_members_watch after insert or update or delete on public.organization_members for each row execute function private.watch_members();

-- ═════════════ Funciones públicas (envoltorios INVOKER) ═════════════
revoke execute on function private.audit(uuid, text, text, text, jsonb, uuid), private.alert(uuid, text, text, text, text, jsonb),
  private.set_admin_pin_impl(uuid, text), private.verify_admin_pin_impl(uuid, text), private.pin_ok(uuid), private.pin_status_impl(uuid),
  private.restore_trash_impl(uuid), private.use_coupon_impl(uuid, text), private.seller_ranking_impl(uuid, date, date) from public, anon;
grant execute on function private.set_admin_pin_impl(uuid, text), private.verify_admin_pin_impl(uuid, text), private.pin_ok(uuid),
  private.pin_status_impl(uuid), private.restore_trash_impl(uuid), private.use_coupon_impl(uuid, text),
  private.seller_ranking_impl(uuid, date, date) to authenticated;
grant execute on function private.audit(uuid, text, text, text, jsonb, uuid), private.alert(uuid, text, text, text, text, jsonb), private.pin_ok(uuid) to service_role;

create or replace function public.set_admin_pin(p_org uuid, p_pin text)
returns void language sql security invoker set search_path = '' as $$ select private.set_admin_pin_impl(p_org, p_pin) $$;
create or replace function public.verify_admin_pin(p_org uuid, p_pin text)
returns boolean language sql security invoker set search_path = '' as $$ select private.verify_admin_pin_impl(p_org, p_pin) $$;
create or replace function public.pin_status(p_org uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$ select private.pin_status_impl(p_org) $$;
create or replace function public.restore_trash(p_id uuid)
returns text language sql security invoker set search_path = '' as $$ select private.restore_trash_impl(p_id) $$;
create or replace function public.use_coupon(p_org uuid, p_code text)
returns jsonb language sql security invoker set search_path = '' as $$ select private.use_coupon_impl(p_org, p_code) $$;
create or replace function public.seller_ranking(p_org uuid, p_from date, p_to date)
returns table (user_id uuid, name text, sales_count bigint, sales_total numeric, commission_pct numeric, commission numeric, goal numeric)
language sql stable security invoker set search_path = '' as $$ select * from private.seller_ranking_impl(p_org, p_from, p_to) $$;

revoke execute on function public.set_admin_pin(uuid, text), public.verify_admin_pin(uuid, text), public.pin_status(uuid),
  public.restore_trash(uuid), public.use_coupon(uuid, text), public.seller_ranking(uuid, date, date),
  public.credit_balances(uuid), public.day_summary(uuid, date), public.loyalty_balances(uuid), public.audit_verify(uuid) from public, anon;
grant execute on function public.set_admin_pin(uuid, text), public.verify_admin_pin(uuid, text), public.pin_status(uuid),
  public.restore_trash(uuid), public.use_coupon(uuid, text), public.seller_ranking(uuid, date, date),
  public.credit_balances(uuid), public.day_summary(uuid, date), public.loyalty_balances(uuid), public.audit_verify(uuid) to authenticated;

-- ═════════════ Tiempo real + limpieza automática de la papelera ═════════════
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['owner_alerts', 'credit_ledger', 'cash_movements', 'payment_notices'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

create or replace function private.purge_trash()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  delete from public.trash where deleted_at < now() - interval '30 days';
  get diagnostics v_n = row_count;
  delete from public.pin_grants where expires_at < now() - interval '1 day';
  return v_n;
end;
$$;
revoke execute on function private.purge_trash() from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'facturavoz-purge-trash';
    perform cron.schedule('facturavoz-purge-trash', '30 8 * * *', 'select private.purge_trash()');
  end if;
exception when others then
  raise notice 'No se pudo programar la limpieza de la papelera: %', sqlerrm;
end $$;

commit;

notify pgrst, 'reload schema';
