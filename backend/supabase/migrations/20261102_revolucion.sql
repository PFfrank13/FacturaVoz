-- FacturaVoz · Migración 11 · "Revolución"
-- Tienda en línea con pedidos · Facturación recurrente automática · Radar de clientes (Clientes 360)
-- · Meta mensual · Costo por producto (margen y precio sugerido).
-- Requiere 20261101_negocio_pro.sql. Idempotente: se puede ejecutar varias veces.
begin;

-- 1) META MENSUAL Y COSTO DE PRODUCTOS ----------------------------------------------------------
alter table public.organizations add column if not exists monthly_goal numeric(14,2);
alter table public.organizations drop constraint if exists organizations_goal_chk;
alter table public.organizations add constraint organizations_goal_chk check (monthly_goal is null or monthly_goal between 0 and 1000000000);
-- La política orgs_update ya exige ser propietario o administrador.
grant update (monthly_goal) on public.organizations to authenticated;

alter table public.products add column if not exists unit_cost numeric(14,2);
alter table public.products add column if not exists in_store boolean not null default true;
alter table public.products drop constraint if exists products_cost_chk;
alter table public.products add constraint products_cost_chk check (unit_cost is null or unit_cost between 0 and 10000000);
grant update (name, unit_price, unit, active, stock, reorder_point, unit_cost, in_store) on public.products to authenticated;

-- 2) TIENDA EN LÍNEA ----------------------------------------------------------------------------
-- Catálogo público /tienda/<slug>: el cliente arma su pedido y llega como cotización "Pedido web".
create table if not exists public.org_store (
  org_id     uuid primary key references public.organizations(id) on delete cascade,
  slug       text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  enabled    boolean not null default false,
  headline   text check (headline is null or char_length(headline) <= 140),
  whatsapp   text check (whatsapp is null or whatsapp ~ '^9[0-9]{8}$'),
  updated_at timestamptz not null default now()
);
alter table public.org_store enable row level security;
drop policy if exists "store_select" on public.org_store;
create policy "store_select" on public.org_store for select to authenticated using (private.is_org_member(org_id));
drop policy if exists "store_insert" on public.org_store;
create policy "store_insert" on public.org_store for insert to authenticated with check (private.is_org_admin(org_id));
drop policy if exists "store_update" on public.org_store;
create policy "store_update" on public.org_store for update to authenticated
  using (private.is_org_admin(org_id)) with check (private.is_org_admin(org_id));
revoke all on public.org_store from anon, authenticated;
grant select on public.org_store to authenticated;
grant insert (org_id, slug, enabled, headline, whatsapp, updated_at) on public.org_store to authenticated;
grant update (org_id, slug, enabled, headline, whatsapp, updated_at) on public.org_store to authenticated;

alter table public.quotes add column if not exists source text not null default 'app';
alter table public.quotes drop constraint if exists quotes_source_chk;
alter table public.quotes add constraint quotes_source_chk check (source in ('app', 'store'));
alter table public.quotes add column if not exists contact_phone text;
alter table public.quotes drop constraint if exists quotes_phone_chk;
alter table public.quotes add constraint quotes_phone_chk check (contact_phone is null or contact_phone ~ '^9[0-9]{8}$');
create index if not exists idx_quotes_store_recent on public.quotes(org_id, created_at desc) where source = 'store';

-- Pedido desde la tienda pública. Los PRECIOS salen de la base de datos (nunca del navegador).
-- Antispam: 30 pedidos/hora por tienda y 3 por celular. Solo el servidor (service_role).
create or replace function public.store_place_order(p_slug text, p_name text, p_phone text, p_note text, p_items jsonb)
returns table (quote_id uuid, quote_number text, org_id uuid, public_token text, total numeric, currency text, business text, whatsapp text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  s public.org_store;
  v_owner uuid;
  v_cur text;
  v_rate numeric;
  v_biz text;
  v_name text := left(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 120);
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 300), '');
  v_items jsonb;
  v_n integer;
  v_client uuid;
  v_next bigint;
  v_id uuid;
  v_number text;
  v_token text;
  v_today date := private.today_pe();
begin
  select * into s from public.org_store st where st.slug = lower(btrim(coalesce(p_slug, ''))) and st.enabled;
  if not found then raise exception 'Tienda no disponible' using errcode = 'P0002'; end if;
  if char_length(v_name) < 2 then raise exception 'Escribe tu nombre' using errcode = '22023'; end if;
  if p_phone is null or p_phone !~ '^9[0-9]{8}$' then raise exception 'Escribe un celular válido (9 dígitos)' using errcode = '22023'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 30 then
    raise exception 'Pedido vacío' using errcode = '22023';
  end if;

  select count(*) into v_n from public.quotes q
   where q.org_id = s.org_id and q.source = 'store' and q.created_at > now() - interval '1 hour';
  if v_n >= 30 then raise exception 'La tienda recibió muchos pedidos. Intenta en unos minutos.' using errcode = 'P0001'; end if;
  select count(*) into v_n from public.quotes q
   where q.org_id = s.org_id and q.source = 'store' and q.contact_phone = p_phone and q.created_at > now() - interval '1 hour';
  if v_n >= 3 then raise exception 'Ya enviaste varios pedidos. El negocio te contactará pronto.' using errcode = 'P0001'; end if;

  select jsonb_agg(jsonb_build_object('description', p.name, 'quantity', x.qty, 'unit_price', p.unit_price) order by x.ord)
    into v_items
  from (
    select e.ord,
           case when (e.item ->> 'product_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                then (e.item ->> 'product_id')::uuid end as pid,
           case when (e.item ->> 'qty') ~ '^[0-9]{1,4}(\.[0-9]{1,2})?$'
                then least(greatest((e.item ->> 'qty')::numeric, 0.01), 1000) end as qty
    from jsonb_array_elements(p_items) with ordinality as e(item, ord)
  ) x
  join public.products p on p.id = x.pid
  where x.qty is not null and p.org_id = s.org_id and p.active and p.in_store;
  if v_items is null then raise exception 'Los productos ya no están disponibles' using errcode = '22023'; end if;

  select m.user_id into v_owner from public.organization_members m
   where m.org_id = s.org_id and m.role = 'owner' order by m.created_at limit 1;
  select coalesce(o.currency, 'PEN'), coalesce(o.default_tax_rate, 18), coalesce(nullif(o.trade_name, ''), o.name)
    into v_cur, v_rate, v_biz from public.organizations o where o.id = s.org_id;

  perform pg_advisory_xact_lock(hashtextextended('quote-number:' || s.org_id::text, 0));

  select c.id into v_client from public.clients c
   where c.org_id = s.org_id and lower(c.name) = lower(v_name) order by c.created_at limit 1;
  if v_client is null then
    insert into public.clients (user_id, org_id, name) values (v_owner, s.org_id, v_name) returning id into v_client;
  end if;

  select coalesce(max((substring(q.number from '(\d+)$'))::bigint), 0) + 1 into v_next
  from public.quotes q where q.org_id = s.org_id and q.number ~ '\d+$';
  v_number := 'COT-' || to_char(v_today, 'YYYY') || '-' || lpad(v_next::text, 4, '0');

  insert into public.quotes (org_id, user_id, client_id, number, issue_date, valid_until, status, tax_rate, currency, notes, source, contact_phone)
  values (s.org_id, v_owner, v_client, v_number, v_today, v_today + 7, 'sent', v_rate, v_cur,
          left('Pedido desde tu tienda en línea · cel. ' || p_phone || coalesce(' · ' || v_note, ''), 500), 'store', p_phone)
  returning id, quotes.public_token into v_id, v_token;

  insert into public.quote_items (quote_id, description, quantity, unit_price, position)
  select v_id, e.item ->> 'description', (e.item ->> 'quantity')::numeric, (e.item ->> 'unit_price')::numeric, e.ord::integer
  from jsonb_array_elements(v_items) with ordinality as e(item, ord);

  return query
    select v_id, v_number, s.org_id, v_token,
           (select coalesce(sum(round(qi.quantity * qi.unit_price, 2) + round(round(qi.quantity * qi.unit_price, 2) * v_rate / 100, 2)), 0)
              from public.quote_items qi where qi.quote_id = v_id),
           v_cur, v_biz, s.whatsapp;
end;
$$;
revoke execute on function public.store_place_order(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.store_place_order(text, text, text, text, jsonb) to service_role;

-- 3) FACTURACIÓN RECURRENTE ---------------------------------------------------------------------
-- Plantillas (alquileres, mantenimientos, mensualidades): cada mes se crea la factura en borrador sola.
create table if not exists public.recurring_invoices (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  client_name     text not null check (char_length(btrim(client_name)) between 1 and 120),
  client_tax_id   text check (client_tax_id is null or char_length(client_tax_id) <= 30),
  items           jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 50),
  tax_rate        numeric(5,2) not null check (tax_rate between 0 and 100),
  currency        text not null check (currency ~ '^[A-Z]{3}$'),
  notes           text check (notes is null or char_length(notes) <= 400),
  day_of_month    integer not null check (day_of_month between 1 and 28),
  due_days        integer not null default 0 check (due_days between 0 and 90),
  next_run        date not null,
  active          boolean not null default true,
  runs            integer not null default 0,
  last_invoice_id uuid references public.invoices(id) on delete set null,
  last_error      text check (last_error is null or char_length(last_error) <= 300),
  created_at      timestamptz not null default now()
);
create index if not exists idx_recurring_org on public.recurring_invoices(org_id);
create index if not exists idx_recurring_user on public.recurring_invoices(user_id);
create index if not exists idx_recurring_due on public.recurring_invoices(next_run) where active;
create index if not exists idx_recurring_last_invoice on public.recurring_invoices(last_invoice_id);
alter table public.recurring_invoices enable row level security;
drop policy if exists "recurring_select" on public.recurring_invoices;
create policy "recurring_select" on public.recurring_invoices for select to authenticated using (private.is_org_member(org_id));
drop policy if exists "recurring_insert" on public.recurring_invoices;
create policy "recurring_insert" on public.recurring_invoices for insert to authenticated
  with check ((select auth.uid()) = user_id and private.is_org_member(org_id));
drop policy if exists "recurring_update" on public.recurring_invoices;
create policy "recurring_update" on public.recurring_invoices for update to authenticated
  using ((select auth.uid()) = user_id or private.is_org_admin(org_id)) with check (private.is_org_member(org_id));
drop policy if exists "recurring_delete" on public.recurring_invoices;
create policy "recurring_delete" on public.recurring_invoices for delete to authenticated
  using ((select auth.uid()) = user_id or private.is_org_admin(org_id));
revoke all on public.recurring_invoices from anon, authenticated;
grant select, delete on public.recurring_invoices to authenticated;
grant insert (org_id, user_id, client_name, client_tax_id, items, tax_rate, currency, notes, day_of_month, due_days, next_run, active)
  on public.recurring_invoices to authenticated;
grant update (client_name, client_tax_id, items, tax_rate, currency, notes, day_of_month, due_days, next_run, active)
  on public.recurring_invoices to authenticated;

alter table public.invoices add column if not exists recurring_id uuid references public.recurring_invoices(id) on delete set null;
create index if not exists idx_invoices_recurring on public.invoices(recurring_id);

-- Próxima fecha: el día elegido del mes siguiente a p_from.
create or replace function private.next_month_day(p_from date, p_day integer)
returns date
language sql
immutable
set search_path = ''
as $$ select (date_trunc('month', p_from) + interval '1 month')::date + (p_day - 1) $$;

-- Genera las facturas vencidas de las plantillas activas (de una empresa o de todas). Cada plantilla en su
-- propia sub-transacción: si una falla, las demás siguen y el error queda en last_error.
create or replace function private.recurring_generate(p_org uuid, p_today date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.recurring_invoices;
  v_client uuid;
  v_next bigint;
  v_inv uuid;
  v_number text;
  v_made integer := 0;
begin
  for r in
    select * from public.recurring_invoices ri
    where ri.active and ri.next_run <= p_today and (p_org is null or ri.org_id = p_org)
    order by ri.next_run limit 500
    for update skip locked
  loop
    -- Si la app estuvo apagada varios meses, se genera una sola factura y se salta a la próxima fecha futura.
    begin
      perform pg_advisory_xact_lock(hashtextextended('invoice-number:' || r.org_id::text, 0));
      select c.id into v_client from public.clients c
       where c.org_id = r.org_id and lower(c.name) = lower(btrim(r.client_name)) order by c.created_at limit 1;
      if v_client is null then
        insert into public.clients (user_id, org_id, name, tax_id)
        values (r.user_id, r.org_id, btrim(r.client_name), nullif(btrim(coalesce(r.client_tax_id, '')), ''))
        returning id into v_client;
      end if;
      select coalesce(max((substring(i.number from '(\d+)$'))::bigint), 0) + 1 into v_next
      from public.invoices i where i.org_id = r.org_id and i.number ~ '\d+$';
      v_number := 'F-' || to_char(p_today, 'YYYY') || '-' || lpad(v_next::text, 4, '0');
      insert into public.invoices (user_id, org_id, client_id, number, issue_date, due_date, tax_rate, currency, notes, recurring_id)
      values (r.user_id, r.org_id, v_client, v_number, p_today,
              case when r.due_days > 0 then p_today + r.due_days end,
              r.tax_rate, r.currency,
              left(coalesce(r.notes || ' · ', '') || 'Recurrente ' || to_char(p_today, 'MM/YYYY'), 500), r.id)
      returning id into v_inv;
      insert into public.invoice_items (user_id, invoice_id, description, quantity, unit_price, position)
      select r.user_id, v_inv, btrim(e.item ->> 'description'), (e.item ->> 'quantity')::numeric, (e.item ->> 'unit_price')::numeric, e.ord::integer
      from jsonb_array_elements(r.items) with ordinality as e(item, ord);
      update public.recurring_invoices
         set runs = runs + 1, last_invoice_id = v_inv, last_error = null,
             next_run = private.next_month_day(p_today, r.day_of_month)
       where id = r.id;
      v_made := v_made + 1;
    exception when others then
      update public.recurring_invoices
         set last_error = left(sqlerrm, 300), next_run = private.next_month_day(p_today, r.day_of_month)
       where id = r.id;
    end;
  end loop;
  return v_made;
end;
$$;
revoke execute on function private.recurring_generate(uuid, date), private.next_month_day(date, integer) from public, anon;
grant execute on function private.next_month_day(date, integer) to authenticated, service_role;
grant execute on function private.recurring_generate(uuid, date) to authenticated;

-- Para la app ("Generar ahora"): solo la empresa del usuario.
create or replace function private.run_my_recurring_impl(p_org uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not private.is_org_member(p_org) then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return private.recurring_generate(p_org, private.today_pe());
end;
$$;
revoke execute on function private.run_my_recurring_impl(uuid) from public, anon;
grant execute on function private.run_my_recurring_impl(uuid) to authenticated;
create or replace function public.run_my_recurring(p_org uuid)
returns integer language sql security invoker set search_path = ''
as $$ select private.run_my_recurring_impl(p_org) $$;
revoke execute on function public.run_my_recurring(uuid) from public, anon;
grant execute on function public.run_my_recurring(uuid) to authenticated;

-- Worker diario (6:00 Lima) con pg_cron. Si no está activo, la app genera al abrir la pantalla.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'facturavoz-recurring';
    perform cron.schedule('facturavoz-recurring', '0 11 * * *', 'select private.recurring_generate(null, (now() at time zone ''America/Lima'')::date)');
  else
    raise notice 'pg_cron no está activado: la facturación recurrente se generará desde la app.';
  end if;
exception when others then
  raise notice 'No se pudo programar el worker recurrente: %', sqlerrm;
end $$;

-- 4) CLIENTES 360 ---------------------------------------------------------------------------------
-- Frecuencia de compra por cliente para detectar a los que se están yendo y a los mejores (RFM).
create or replace function public.client_activity(p_org uuid)
returns table (
  client_key text, client_name text, client_email text, purchases integer, total numeric,
  first_purchase date, last_purchase date, avg_gap numeric, days_since integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with d as (select private.today_pe() as today),
  cur as (select coalesce(o.currency, 'PEN') as cur_code from public.organizations o where o.id = p_org),
  t as (
    select i.id, i.issue_date, lower(btrim(c.name)) as k, c.name as cname, c.email as cemail,
           sum(round(it.quantity * it.unit_price, 2) + round(round(it.quantity * it.unit_price, 2) * i.tax_rate / 100, 2)) as total
    from public.invoices i
    join public.clients c on c.id = i.client_id
    join public.invoice_items it on it.invoice_id = i.id
    left join public.fiscal_documents fd on fd.invoice_id = i.id
    where i.org_id = p_org and i.status <> 'draft' and coalesce(fd.status, '') <> 'rejected'
      and i.currency = (select cur.cur_code from cur)
      and i.issue_date >= (select today from d) - 730
    group by i.id, c.name, c.email
  )
  select t.k, min(t.cname), max(t.cemail), count(*)::integer, round(sum(t.total), 2),
         min(t.issue_date), max(t.issue_date),
         case when count(*) > 1 then round((max(t.issue_date) - min(t.issue_date))::numeric / (count(*) - 1), 1) end,
         ((select today from d) - max(t.issue_date))::integer
  from t
  group by t.k
$$;
revoke execute on function public.client_activity(uuid) from public, anon;
grant execute on function public.client_activity(uuid) to authenticated;

-- 5) Tiempo real para pedidos web -----------------------------------------------------------------
-- (quotes ya está en la publicación desde la migración anterior)

commit;
