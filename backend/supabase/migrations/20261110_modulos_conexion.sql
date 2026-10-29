-- FacturaVoz · Migración 19 · Módulos revolucionarios (Fase 8, parte 2: conexión con el cliente y otros sistemas)
--   7  Portal del cliente final (QR/enlace en cada comprobante, sin cuenta)  → doc_links + portal_get()
--  12  Proyectos por avance (facturar un hito en un toque)                  → milestone_invoice()
--  14  Reservas y citas (página pública para reservar)                      → org_store.booking + store_book()
--  20  API pública y webhooks                                               → org_api_keys + org_webhooks + webhook_outbox
--  21  Encuestas de satisfacción post-venta                                  → surveys + survey_answer()
--   +  Avisos del día v2 (suma fiados vencidos y encuestas malas)
-- Idempotente y aditiva. Ejecutar después de 20261109.
begin;

-- ═════════════ 7) PORTAL DEL CLIENTE ═════════════
create table if not exists public.doc_links (
  token text primary key default private.new_token(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null unique references public.invoices(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_doc_links_org on public.doc_links(org_id);
alter table public.doc_links enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'doc_links' and policyname = 'doc_links_select') then
    create policy "doc_links_select" on public.doc_links for select to authenticated
      using (private.is_org_member(org_id) and exists (select 1 from public.invoices i where i.id = invoice_id));
  end if;
end $$;
revoke all on public.doc_links from anon, authenticated;
grant select on public.doc_links to authenticated;

create or replace function private.invoice_portal_link_impl(p_invoice uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_token text;
begin
  select i.org_id into v_org from public.invoices i where i.id = p_invoice;
  if v_org is null or not private.is_org_member(v_org) then raise exception 'Factura no encontrada' using errcode = '42501'; end if;
  insert into public.doc_links (org_id, invoice_id) values (v_org, p_invoice) on conflict (invoice_id) do nothing;
  select l.token into v_token from public.doc_links l where l.invoice_id = p_invoice;
  return v_token;
end;
$$;
revoke execute on function private.invoice_portal_link_impl(uuid) from public, anon;
grant execute on function private.invoice_portal_link_impl(uuid) to authenticated, service_role;
create or replace function public.invoice_portal_link(p_invoice uuid)
returns text language sql security invoker set search_path = '' as $$ select private.invoice_portal_link_impl(p_invoice) $$;
revoke execute on function public.invoice_portal_link(uuid) from public, anon;
grant execute on function public.invoice_portal_link(uuid) to authenticated, service_role;

-- Lectura pública (solo el servidor, con el token): el comprobante y el historial del mismo cliente en esa empresa.
create or replace function public.portal_get(p_token text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  l public.doc_links;
  i public.invoices;
  v_out jsonb;
begin
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{20,80}$' then return null; end if;
  select * into l from public.doc_links where token = p_token;
  if not found then return null; end if;
  select * into i from public.invoices where id = l.invoice_id;
  select jsonb_build_object(
    'org', (select jsonb_build_object('name', coalesce(nullif(o.trade_name, ''), o.name), 'legal_name', o.name, 'ruc', o.tax_id, 'address', o.address, 'logo_path', o.logo_path)
            from public.organizations o where o.id = l.org_id),
    'client', (select jsonb_build_object('name', c.name, 'tax_id', c.tax_id) from public.clients c where c.id = i.client_id),
    'invoice_id', i.id,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'number', h.number, 'issue_date', h.issue_date, 'currency', h.currency, 'status', h.status,
        'total', private.invoice_total(h.id), 'paid', private.invoice_paid(h.id),
        'fiscal', (select jsonb_build_object('series', fd.series, 'correlative', fd.correlative, 'status', fd.status, 'doc_type', fd.doc_type)
                   from public.fiscal_documents fd where fd.invoice_id = h.id)) order by h.issue_date desc, h.created_at desc)
      from (select * from public.invoices x
            where x.org_id = l.org_id and x.status <> 'draft'
              and (x.id = i.id or (i.client_id is not null and x.client_id = i.client_id))
            order by x.issue_date desc limit 60) h), '[]'::jsonb))
  into v_out;
  return v_out;
end;
$$;
revoke execute on function public.portal_get(text) from public, anon, authenticated;
grant execute on function public.portal_get(text) to service_role;

-- ═════════════ 12) FACTURAR UN HITO ═════════════
create or replace function public.milestone_invoice(p_milestone uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  m public.job_milestones;
  j public.jobs;
  v_client text;
  v_tax text;
  v_rate numeric;
  v_cur text;
  v_inv uuid;
begin
  select * into m from public.job_milestones where id = p_milestone for update;
  if not found then raise exception 'Hito no encontrado' using errcode = 'P0002'; end if;
  if m.status = 'facturado' then return m.invoice_id; end if;
  select * into j from public.jobs where id = m.job_id;
  select c.name, c.tax_id into v_client, v_tax from public.clients c where c.id = j.client_id;
  select coalesce(o.default_tax_rate, 18), coalesce(o.currency, 'PEN') into v_rate, v_cur from public.organizations o where o.id = m.org_id;
  -- El monto del hito es el TOTAL a cobrar (con IGV): la línea se guarda sin IGV.
  select ci.invoice_id into v_inv from public.create_invoice(
    coalesce(v_client, 'Cliente'), v_tax, v_rate, v_cur, left(j.title || ' · ' || m.title, 500), null,
    jsonb_build_array(jsonb_build_object('description', left(j.title || ' — ' || m.title, 200), 'quantity', 1,
                                         'unit_price', round(m.amount / (1 + v_rate / 100), 2))),
    m.org_id) ci;
  update public.job_milestones set status = 'facturado', invoice_id = v_inv where id = m.id;
  return v_inv;
end;
$$;
revoke execute on function public.milestone_invoice(uuid) from public, anon;
grant execute on function public.milestone_invoice(uuid) to authenticated;

-- ═════════════ 14) RESERVAS PÚBLICAS ═════════════
alter table public.org_store
  add column if not exists booking boolean not null default false,
  add column if not exists booking_services text[] not null default '{}',
  add column if not exists booking_hours text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'org_store_booking_chk') then
    alter table public.org_store add constraint org_store_booking_chk check (
      cardinality(booking_services) <= 30 and (booking_hours is null or char_length(booking_hours) <= 120));
  end if;
end $$;
grant insert (booking, booking_services, booking_hours) on public.org_store to authenticated;
grant update (booking, booking_services, booking_hours) on public.org_store to authenticated;

create or replace function public.store_book(p_slug text, p_name text, p_phone text, p_service text, p_at timestamptz, p_note text)
returns table (job_id uuid, org_id uuid, business text, whatsapp text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  s public.org_store;
  v_owner uuid;
  v_client uuid;
  v_name text := left(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 120);
  v_service text := left(btrim(coalesce(p_service, '')), 100);
  v_id uuid;
  v_n integer;
begin
  select * into s from public.org_store st where st.slug = lower(btrim(coalesce(p_slug, ''))) and st.enabled and st.booking;
  if not found then raise exception 'Reservas no disponibles' using errcode = 'P0002'; end if;
  if char_length(v_name) < 2 then raise exception 'Escribe tu nombre' using errcode = '22023'; end if;
  if p_phone is null or p_phone !~ '^9[0-9]{8}$' then raise exception 'Escribe un celular válido (9 dígitos)' using errcode = '22023'; end if;
  if p_at is null or p_at < now() or p_at > now() + interval '90 days' then raise exception 'Elige una fecha de los próximos 90 días' using errcode = '22023'; end if;
  if v_service = '' then v_service := 'Cita'; end if;
  select count(*) into v_n from public.jobs j where j.org_id = s.org_id and j.kind = 'cita' and j.source = 'web' and j.created_at > now() - interval '1 hour';
  if v_n >= 20 then raise exception 'Muchas reservas en este momento. Intenta en unos minutos.' using errcode = 'P0001'; end if;
  select count(*) into v_n from public.jobs j where j.org_id = s.org_id and j.contact_phone = p_phone and j.created_at > now() - interval '1 day';
  if v_n >= 3 then raise exception 'Ya tienes reservas pendientes. El negocio te confirmará pronto.' using errcode = 'P0001'; end if;
  -- Choque de horario (misma hora exacta, cita no terminada)
  if exists (select 1 from public.jobs j where j.org_id = s.org_id and j.kind = 'cita' and j.done_at is null and j.scheduled_at = p_at) then
    raise exception 'Ese horario ya está reservado. Elige otro.' using errcode = 'P0001';
  end if;
  select m.user_id into v_owner from public.organization_members m where m.org_id = s.org_id and m.role = 'owner' order by m.created_at limit 1;
  select c.id into v_client from public.clients c where c.org_id = s.org_id and (c.phone = p_phone or lower(c.name) = lower(v_name)) order by (c.phone = p_phone) desc, c.created_at limit 1;
  if v_client is null then
    insert into public.clients (user_id, org_id, name, phone, source) values (v_owner, s.org_id, v_name, p_phone, 'web') returning id into v_client;
  end if;
  insert into public.jobs (org_id, client_id, title, kind, status, source, scheduled_at, duration_min, contact_phone, notes, created_by)
  values (s.org_id, v_client, v_service, 'cita', 'nuevo', 'web', p_at, 30, p_phone, nullif(left(btrim(coalesce(p_note, '')), 300), ''), v_owner)
  returning id into v_id;
  perform private.alert(s.org_id, 'reserva', 'info', 'Nueva reserva: ' || v_service,
    v_name || ' · ' || to_char(p_at at time zone 'America/Lima', 'DD/MM HH24:MI'), jsonb_build_object('job_id', v_id));
  return query select v_id, s.org_id, (select coalesce(nullif(o.trade_name, ''), o.name) from public.organizations o where o.id = s.org_id), s.whatsapp;
end;
$$;
revoke execute on function public.store_book(text, text, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function public.store_book(text, text, text, text, timestamptz, text) to service_role;

-- ═════════════ 20) API PÚBLICA Y WEBHOOKS ═════════════
create table if not exists public.org_api_keys (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  prefix text not null,
  key_hash text not null unique,
  scopes text[] not null default '{invoices:read,clients:read,orders:write}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
create index if not exists idx_api_keys_org on public.org_api_keys(org_id);
create index if not exists idx_api_keys_created_by on public.org_api_keys(created_by);

create table if not exists public.api_rate (
  key_id uuid not null references public.org_api_keys(id) on delete cascade,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (key_id, window_start)
);

create table if not exists public.org_webhooks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  url text not null check (url ~ '^https://[^\s]+$' and char_length(url) between 12 and 400),
  secret text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  events text[] not null default '{invoice.created,invoice.paid,payment.created,order.created}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_status integer,
  last_error text
);
create index if not exists idx_webhooks_org on public.org_webhooks(org_id);

create table if not exists public.webhook_outbox (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organizations(id) on delete cascade,
  webhook_id uuid not null references public.org_webhooks(id) on delete cascade,
  event text not null,
  payload jsonb not null,
  attempts integer not null default 0,
  next_at timestamptz not null default now(),
  delivered_at timestamptz,
  last_status integer,
  last_error text,
  created_at timestamptz not null default now()
);
create index if not exists idx_webhook_outbox_due on public.webhook_outbox(next_at) where delivered_at is null and attempts < 12;
create index if not exists idx_webhook_outbox_org on public.webhook_outbox(org_id, created_at desc);
create index if not exists idx_webhook_outbox_hook on public.webhook_outbox(webhook_id);

alter table public.org_api_keys enable row level security;
alter table public.api_rate enable row level security;
alter table public.org_webhooks enable row level security;
alter table public.webhook_outbox enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'org_api_keys' and policyname = 'api_keys_select') then
    create policy "api_keys_select" on public.org_api_keys for select to authenticated using (private.is_org_admin(org_id));
    create policy "webhooks_all" on public.org_webhooks for all to authenticated using (private.is_org_admin(org_id)) with check (private.is_org_admin(org_id));
    create policy "webhook_outbox_select" on public.webhook_outbox for select to authenticated using (private.is_org_admin(org_id));
  end if;
end $$;
revoke all on public.org_api_keys, public.api_rate, public.org_webhooks, public.webhook_outbox from anon, authenticated;
grant select on public.org_api_keys, public.webhook_outbox to authenticated;
grant select, insert, delete on public.org_webhooks to authenticated;
grant update (url, events, active) on public.org_webhooks to authenticated;
grant select, insert, update, delete on public.org_api_keys, public.api_rate, public.org_webhooks, public.webhook_outbox to service_role;

-- Crea una clave (se muestra UNA vez; solo se guarda su hash SHA-256).
create or replace function private.create_api_key_impl(p_org uuid, p_name text, p_scopes text[])
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := 'fvk_' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_scopes text[] := coalesce(p_scopes, '{invoices:read,clients:read,orders:write}');
begin
  if not private.is_org_admin(p_org) then raise exception 'Solo el propietario o un administrador' using errcode = '42501'; end if;
  if not (v_scopes <@ array['invoices:read', 'clients:read', 'orders:write', 'products:read']) then
    raise exception 'Permiso no válido' using errcode = '22023';
  end if;
  if (select count(*) from public.org_api_keys k where k.org_id = p_org and k.revoked_at is null) >= 10 then
    raise exception 'Máximo 10 claves activas' using errcode = 'P0001';
  end if;
  insert into public.org_api_keys (org_id, name, prefix, key_hash, scopes, created_by)
  values (p_org, left(btrim(coalesce(p_name, 'Mi integración')), 60), left(v_key, 12), encode(sha256(convert_to(v_key, 'UTF8')), 'hex'), v_scopes, (select auth.uid()));
  perform private.audit(p_org, 'api.clave_creada', 'org_api_keys', left(v_key, 12), jsonb_build_object('scopes', v_scopes));
  return v_key;
end;
$$;
create or replace function private.revoke_api_key_impl(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_org uuid;
begin
  select k.org_id into v_org from public.org_api_keys k where k.id = p_id;
  if v_org is null or not private.is_org_admin(v_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  update public.org_api_keys set revoked_at = now() where id = p_id and revoked_at is null;
  perform private.audit(v_org, 'api.clave_revocada', 'org_api_keys', p_id::text, '{}'::jsonb);
end;
$$;
revoke execute on function private.create_api_key_impl(uuid, text, text[]), private.revoke_api_key_impl(uuid) from public, anon;
grant execute on function private.create_api_key_impl(uuid, text, text[]), private.revoke_api_key_impl(uuid) to authenticated;
create or replace function public.create_api_key(p_org uuid, p_name text, p_scopes text[] default null)
returns text language sql security invoker set search_path = '' as $$ select private.create_api_key_impl(p_org, p_name, p_scopes) $$;
create or replace function public.revoke_api_key(p_id uuid)
returns void language sql security invoker set search_path = '' as $$ select private.revoke_api_key_impl(p_id) $$;
revoke execute on function public.create_api_key(uuid, text, text[]), public.revoke_api_key(uuid) from public, anon;
grant execute on function public.create_api_key(uuid, text, text[]), public.revoke_api_key(uuid) to authenticated;

-- Autenticación de la API (solo el servidor): valida el hash, revisa el permiso y aplica 120 solicitudes por minuto.
create or replace function public.api_key_auth(p_hash text, p_scope text)
returns table (org_id uuid, key_id uuid)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  k public.org_api_keys;
  v_win timestamptz := date_trunc('minute', now());
  v_hits integer;
begin
  select * into k from public.org_api_keys where key_hash = p_hash and revoked_at is null;
  if not found then raise exception 'Clave no válida' using errcode = '28000'; end if;
  if not (p_scope = any(k.scopes)) then raise exception 'La clave no tiene permiso para esto' using errcode = '42501'; end if;
  insert into public.api_rate as r (key_id, window_start, hits) values (k.id, v_win, 1)
  on conflict on constraint api_rate_pkey do update set hits = r.hits + 1
  returning r.hits into v_hits;
  if v_hits > 120 then raise exception 'Demasiadas solicitudes: máximo 120 por minuto' using errcode = 'P0001'; end if;
  update public.org_api_keys ak set last_used_at = now() where ak.id = k.id and (ak.last_used_at is null or ak.last_used_at < now() - interval '1 minute');
  delete from public.api_rate ar where ar.key_id = k.id and ar.window_start < now() - interval '10 minutes';
  return query select k.org_id, k.id;
end;
$$;
revoke execute on function public.api_key_auth(text, text) from public, anon, authenticated;
grant execute on function public.api_key_auth(text, text) to service_role;

-- Eventos → cola de webhooks (solo si la empresa tiene webhooks activos para ese evento)
create or replace function private.enqueue_webhook(p_org uuid, p_event text, p_payload jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.webhook_outbox (org_id, webhook_id, event, payload)
  select w.org_id, w.id, p_event, jsonb_build_object('event', p_event, 'created_at', now(), 'data', p_payload)
  from public.org_webhooks w where w.org_id = p_org and w.active and p_event = any(w.events);
$$;

create or replace function private.webhook_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
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
create or replace trigger invoices_webhooks after insert or update on public.invoices for each row execute function private.webhook_events();
create or replace trigger payments_webhooks after insert on public.payments for each row execute function private.webhook_events();
create or replace trigger quotes_webhooks after insert on public.quotes for each row execute function private.webhook_events();

-- La API crea pedidos como cotización "Pedido API" (canal 'api'; precios del catálogo si se envía product_id).
alter table public.quotes add column if not exists channel text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'quotes_channel_chk') then
    alter table public.quotes add constraint quotes_channel_chk check (channel is null or channel in ('api', 'mesa', 'web', 'whatsapp'));
  end if;
end $$;

create or replace function public.api_create_order(p_org uuid, p_client_name text, p_client_tax_id text, p_phone text, p_note text, p_items jsonb)
returns table (quote_id uuid, quote_number text, public_token text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_owner uuid;
  v_cur text;
  v_rate numeric;
  v_client uuid;
  v_name text := left(btrim(coalesce(p_client_name, '')), 120);
  v_next bigint;
  v_number text;
  v_id uuid;
  v_token text;
  v_items jsonb;
  v_today date := private.today_pe();
begin
  if char_length(v_name) < 2 then raise exception 'client_name es obligatorio' using errcode = '22023'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'items debe tener entre 1 y 50 líneas' using errcode = '22023';
  end if;
  select jsonb_agg(jsonb_build_object(
           'description', left(coalesce(p.name, nullif(btrim(e.item ->> 'description'), '')), 200),
           'quantity', least(greatest(coalesce((e.item ->> 'quantity')::numeric, 1), 0.01), 100000),
           'unit_price', coalesce(p.unit_price, greatest(coalesce((e.item ->> 'unit_price')::numeric, 0), 0))) order by e.ord)
    into v_items
  from jsonb_array_elements(p_items) with ordinality as e(item, ord)
  left join public.products p on p.org_id = p_org and p.active
       and p.id = case when (e.item ->> 'product_id') ~ '^[0-9a-f-]{36}$' then (e.item ->> 'product_id')::uuid end
  where coalesce(p.name, nullif(btrim(e.item ->> 'description'), '')) is not null;
  if v_items is null then raise exception 'Ninguna línea es válida' using errcode = '22023'; end if;

  select m.user_id into v_owner from public.organization_members m where m.org_id = p_org and m.role = 'owner' order by m.created_at limit 1;
  select coalesce(o.currency, 'PEN'), coalesce(o.default_tax_rate, 18) into v_cur, v_rate from public.organizations o where o.id = p_org;
  perform pg_advisory_xact_lock(hashtextextended('quote-number:' || p_org::text, 0));
  select c.id into v_client from public.clients c where c.org_id = p_org and lower(c.name) = lower(v_name) order by c.created_at limit 1;
  if v_client is null then
    insert into public.clients (user_id, org_id, name, tax_id, phone, source)
    values (v_owner, p_org, v_name, nullif(left(btrim(coalesce(p_client_tax_id, '')), 30), ''), nullif(left(btrim(coalesce(p_phone, '')), 30), ''), 'web')
    returning id into v_client;
  end if;
  select coalesce(max((substring(q.number from '(\d+)$'))::bigint), 0) + 1 into v_next from public.quotes q where q.org_id = p_org and q.number ~ '\d+$';
  v_number := 'COT-' || to_char(v_today, 'YYYY') || '-' || lpad(v_next::text, 4, '0');
  insert into public.quotes (org_id, user_id, client_id, number, issue_date, valid_until, status, tax_rate, currency, notes, source, channel)
  values (p_org, v_owner, v_client, v_number, v_today, v_today + 7, 'sent', v_rate, v_cur,
          left('Pedido API' || coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), ''), 500), 'app', 'api')
  returning id, quotes.public_token into v_id, v_token;
  insert into public.quote_items (quote_id, description, quantity, unit_price, position)
  select v_id, e.item ->> 'description', (e.item ->> 'quantity')::numeric, (e.item ->> 'unit_price')::numeric, e.ord::integer
  from jsonb_array_elements(v_items) with ordinality as e(item, ord);
  perform private.enqueue_webhook(p_org, 'order.created', jsonb_build_object('id', v_id, 'number', v_number, 'channel', 'api'));
  return query select v_id, v_number, v_token;
end;
$$;
revoke execute on function public.api_create_order(uuid, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.api_create_order(uuid, text, text, text, text, jsonb) to service_role;

-- ═════════════ 21) ENCUESTAS ═════════════
alter table public.org_settings add column if not exists survey_auto boolean not null default false;
grant insert (survey_auto) on public.org_settings to authenticated;
grant update (survey_auto) on public.org_settings to authenticated;

create table if not exists public.surveys (
  token text primary key default private.new_token(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid unique references public.invoices(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  score smallint check (score is null or score between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 500)
);
create index if not exists idx_surveys_org on public.surveys(org_id, created_at desc);
create index if not exists idx_surveys_client on public.surveys(client_id);
alter table public.surveys enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'surveys' and policyname = 'surveys_select') then
    create policy "surveys_select" on public.surveys for select to authenticated using (private.is_org_member(org_id) and not private.is_tech(org_id));
  end if;
end $$;
revoke all on public.surveys from anon, authenticated;
grant select on public.surveys to authenticated;
grant select, insert, update, delete on public.surveys, public.doc_links to service_role;

create or replace function private.survey_link_impl(p_invoice uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  i public.invoices;
  v_token text;
begin
  select * into i from public.invoices where id = p_invoice;
  if not found or not private.is_org_member(i.org_id) then raise exception 'Factura no encontrada' using errcode = '42501'; end if;
  insert into public.surveys (org_id, invoice_id, client_id) values (i.org_id, i.id, i.client_id) on conflict (invoice_id) do nothing;
  select s.token into v_token from public.surveys s where s.invoice_id = p_invoice;
  return v_token;
end;
$$;
revoke execute on function private.survey_link_impl(uuid) from public, anon;
grant execute on function private.survey_link_impl(uuid) to authenticated;
create or replace function public.survey_link(p_invoice uuid)
returns text language sql security invoker set search_path = '' as $$ select private.survey_link_impl(p_invoice) $$;
revoke execute on function public.survey_link(uuid) from public, anon;
grant execute on function public.survey_link(uuid) to authenticated;

create or replace function public.survey_answer(p_token text, p_score integer, p_comment text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare s public.surveys;
begin
  select * into s from public.surveys where token = p_token for update;
  if not found then raise exception 'Encuesta no encontrada' using errcode = 'P0002'; end if;
  if s.answered_at is not null then return 'ya'; end if;
  if p_score is null or p_score not between 1 and 5 then raise exception 'Elige de 1 a 5' using errcode = '22023'; end if;
  update public.surveys set score = p_score, comment = nullif(left(btrim(coalesce(p_comment, '')), 500), ''), answered_at = now() where token = p_token;
  if p_score <= 2 then
    perform private.alert(s.org_id, 'encuesta_mala', 'warn', 'Un cliente calificó con ' || p_score || '/5',
      coalesce(nullif(left(btrim(coalesce(p_comment, '')), 200), ''), 'Sin comentario'), jsonb_build_object('invoice_id', s.invoice_id));
  end if;
  return 'ok';
end;
$$;
revoke execute on function public.survey_answer(text, integer, text) from public, anon, authenticated;
grant execute on function public.survey_answer(text, integer, text) to service_role;

-- ═════════════ Avisos del día v2 (+ fiados vencidos) ═════════════
create or replace function public.daily_alerts(p_org uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'America/Lima')::date;
  v_out jsonb := '[]'::jsonb;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;

  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object(
      'kind', case when (j.scheduled_at at time zone 'America/Lima')::date = v_today then 'visit_today' else 'visit_tomorrow' end,
      'job_id', j.id, 'title', j.title, 'job_kind', j.kind, 'client', c.name, 'phone', coalesce(j.contact_phone, c.phone),
      'at', j.scheduled_at, 'address', j.address) order by j.scheduled_at)
    from public.jobs j left join public.clients c on c.id = j.client_id
    where j.org_id = p_org and j.done_at is null
      and (j.scheduled_at at time zone 'America/Lima')::date between v_today and v_today + 1), '[]'::jsonb);

  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'job_late', 'job_id', j.id, 'title', j.title, 'client', c.name, 'at', j.scheduled_at) order by j.scheduled_at)
    from (select * from public.jobs where org_id = p_org and done_at is null
            and (scheduled_at at time zone 'America/Lima')::date < v_today
            and scheduled_at > now() - interval '60 days' order by scheduled_at limit 10) j
    left join public.clients c on c.id = j.client_id), '[]'::jsonb);

  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'no_contact', 'client_id', x.id, 'client', x.name, 'phone', x.phone, 'days', x.days) order by x.days desc)
    from (
      select c.id, c.name, c.phone,
             (v_today - greatest(coalesce((c.last_contact_at at time zone 'America/Lima')::date, '1900-01-01'), max(i.issue_date))) as days
      from public.clients c join public.invoices i on i.client_id = c.id and i.status <> 'draft'
      where c.org_id = p_org
      group by c.id
      having count(i.id) >= 2
         and v_today - greatest(coalesce((c.last_contact_at at time zone 'America/Lima')::date, '1900-01-01'), max(i.issue_date)) between 30 and 365
      order by 4 desc limit 5) x), '[]'::jsonb);

  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'birthday', 'client_id', c.id, 'client', c.name, 'phone', c.phone))
    from public.clients c
    where c.org_id = p_org and c.birthday is not null
      and extract(month from c.birthday) = extract(month from v_today) and extract(day from c.birthday) = extract(day from v_today)), '[]'::jsonb);

  -- Fiados vencidos (saldo > 0 y algún cargo con fecha límite pasada)
  if not private.is_tech(p_org) then
    v_out := v_out || coalesce((
      select jsonb_agg(jsonb_build_object('kind', 'fiado_due', 'client_id', b.client_id, 'client', b.client_name, 'phone', b.phone,
                                          'amount', b.balance, 'due', b.oldest_due) order by b.oldest_due)
      from public.credit_balances(p_org) b
      where b.balance > 0 and b.oldest_due is not null and b.oldest_due < v_today), '[]'::jsonb);
  end if;

  return v_out;
end;
$$;
revoke execute on function public.daily_alerts(uuid) from public, anon;
grant execute on function public.daily_alerts(uuid) to authenticated;

commit;

notify pgrst, 'reload schema';
