-- FacturaVoz · Migración 20 · Licencias y membresías con Solvex Hub (Fase 5) — KILL-SWITCH REAL EN LA BASE DE DATOS
--
-- Cada empresa (organización) es un "tenant" del Hub: tenant_ref = organizations.id. Los empleados heredan su estado.
-- El servidor (Next.js, con la clave service_role) verifica el token Ed25519 del Hub y guarda aquí el estado.
-- La app SOLO LEE su propia fila (a través de my_license); nunca la escribe.
--
-- Modos (los del Hub):
--   full        → todo funciona.
--   warning     → todo funciona + aviso con enlace de pago.
--   restricted  → el dueño/administrador solo puede pagar, EXPORTAR (leer) sus datos y salir; el personal no entra.
--   blocked     → nadie opera: pantalla "aún no activado".
-- Cómo se aplica (no solo en la UI):
--   · LECTURA: políticas RLS RESTRICTIVAS en todas las tablas con org_id.
--   · ESCRITURA: un disparador en todas esas tablas (alcanza también a las funciones SECURITY DEFINER, a la tienda
--     pública y a los procesos automáticos). Además verifica que el plan incluya la función (cotizaciones, tienda…).
--   · Corte sin conexión: si el token anunció un corte (cut_at / grace_end) y ya pasó, se trata como 'restricted'
--     aunque el Hub no haya respondido. Si el Hub se cae, se respeta el último estado hasta su fecha de corte.
-- Mientras el Hub no esté configurado (license_enforced = false) todo funciona en "modo desarrollo".
-- Idempotente y aditiva. Ejecutar AL FINAL (después de 20261110): protege también las tablas de las migraciones anteriores.
begin;

-- ───────────── Configuración interna ─────────────
create table if not exists private.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
insert into private.app_config (key, value) values ('license_enforced', 'false'::jsonb) on conflict (key) do nothing;
revoke all on private.app_config from public, anon, authenticated;
grant select, insert, update on private.app_config to service_role;

-- ───────────── Estado de licencia por empresa ─────────────
create table if not exists public.org_licenses (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  source text not null default 'local' check (source in ('local', 'hub', 'dev')),
  license_code text,
  plan text not null default 'EMPRESA',
  status text not null default 'prueba' check (status in ('pendiente', 'prueba', 'activa', 'gracia', 'suspendida', 'cancelada')),
  mode text not null default 'full' check (mode in ('full', 'warning', 'restricted', 'blocked')),
  features jsonb not null default '{}'::jsonb check (jsonb_typeof(features) = 'object'),
  message text,
  pay_url text check (pay_url is null or pay_url ~ '^https?://'),
  period_end timestamptz,
  grace_end timestamptz,
  cut_at timestamptz,
  auto_cut boolean not null default true,
  token text,
  token_iat bigint,
  token_exp timestamptz,
  trial_requested_at timestamptz,
  last_sync_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);
alter table public.org_licenses enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'org_licenses' and policyname = 'org_licenses_select') then
    create policy "org_licenses_select" on public.org_licenses for select to authenticated using (private.is_org_admin(org_id));
  end if;
end $$;
revoke all on public.org_licenses from anon, authenticated;
grant select on public.org_licenses to authenticated;
grant select, insert, update, delete on public.org_licenses to service_role;

-- Todas las funciones habilitadas (prueba gratis = acceso total)
create or replace function private.all_features()
returns jsonb language sql immutable set search_path = ''
as $$
  select '{"facturar":true,"clientes":true,"cobros":true,"voz":true,"cotizaciones":true,"tienda":true,"stock":true,
           "recurrentes":true,"copiloto":true,"trabajos":true,"agenda":true,"reportes":true,"multisucursal":true,
           "fiados":true,"caja":true,"cuaderno_ia":true,"portal_cliente":true,"precios":true,"fidelizacion":true,
           "carta_qr":true,"conciliacion":true,"comisiones":true,"avisos_pago":true,"multimoneda":true,"api_publica":true,
           "encuestas":true,"antifraude":true,"max_users":-1,"max_branches":-1}'::jsonb;
$$;

create or replace function private.license_enforced()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce((select (value)::text = 'true' from private.app_config where key = 'license_enforced'), false); $$;

-- Modo efectivo AHORA (corta sin conexión si el corte anunciado ya pasó).
create or replace function private.org_mode(p_org uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare l public.org_licenses;
begin
  if not private.license_enforced() then return 'full'; end if;
  select * into l from public.org_licenses where org_id = p_org;
  if not found then return 'blocked'; end if;
  if l.source in ('local', 'dev') then
    return case when l.period_end is null or now() <= l.period_end then 'full' else 'blocked' end;
  end if;
  if l.mode in ('full', 'warning') and l.auto_cut and coalesce(l.cut_at, l.grace_end) is not null
     and now() > coalesce(l.cut_at, l.grace_end) then
    return 'restricted';
  end if;
  return l.mode;
end;
$$;

-- ¿El plan incluye esta función? (las básicas siempre; en modo desarrollo, todas)
create or replace function private.has_feature(p_org uuid, p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
  f jsonb;
  v_src text;
begin
  if not private.license_enforced() then return true; end if;
  if p_key in ('facturar', 'clientes', 'cobros', 'voz') then return true; end if;
  select l.features, l.source into f, v_src from public.org_licenses l where l.org_id = p_org;
  if f is null then return false; end if;
  if v_src in ('local', 'dev') then return true; end if; -- prueba local: acceso total
  v := f -> p_key;
  return case jsonb_typeof(v) when 'boolean' then v::text = 'true' when 'number' then (v::text)::numeric <> 0 else false end;
end;
$$;

-- Límite numérico del plan (-1 = sin límite)
create or replace function private.feature_limit(p_org uuid, p_key text)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb;
begin
  if not private.license_enforced() then return -1; end if;
  select l.features -> p_key into v from public.org_licenses l where l.org_id = p_org and l.source = 'hub';
  if v is null or jsonb_typeof(v) <> 'number' then return -1; end if;
  return (v::text)::integer;
end;
$$;

-- El límite de usuarios del plan se aplica al invitar (Fase 2 lo consulta aquí).
create or replace function private.max_users(p_org uuid)
returns integer language sql stable security definer set search_path = ''
as $$ select private.feature_limit(p_org, 'max_users'); $$;

create or replace function private.license_read_ok(p_org uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case private.org_mode(p_org)
           when 'full' then true when 'warning' then true
           when 'restricted' then private.is_org_admin(p_org)
           else false end;
$$;

create or replace function private.license_write_ok(p_org uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select private.org_mode(p_org) in ('full', 'warning'); $$;

revoke execute on function private.all_features(), private.license_enforced(), private.org_mode(uuid), private.has_feature(uuid, text),
  private.feature_limit(uuid, text), private.license_read_ok(uuid), private.license_write_ok(uuid) from public, anon;
grant execute on function private.all_features(), private.license_enforced(), private.org_mode(uuid), private.has_feature(uuid, text),
  private.feature_limit(uuid, text), private.license_read_ok(uuid), private.license_write_ok(uuid) to authenticated, service_role;

-- ───────────── Prueba local de 3 días al crear la empresa (luego la reemplaza la licencia del Hub) ─────────────
create or replace function private.org_license_init()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.org_licenses (org_id, source, plan, status, mode, features, message, period_end)
  values (new.id, 'local', 'EMPRESA', 'prueba', 'full', private.all_features(),
          'Prueba gratis de 3 días con todas las funciones',
          (((now() at time zone 'America/Lima')::date + 3)::timestamp at time zone 'America/Lima') - interval '1 second')
  on conflict (org_id) do nothing;
  return new;
end;
$$;
create or replace trigger organizations_license_init after insert on public.organizations for each row execute function private.org_license_init();

-- Empresas que ya existían: 14 días para que el dueño active su plan cuando se encienda el control de licencias.
insert into public.org_licenses (org_id, source, plan, status, mode, features, message, period_end)
select o.id, 'local', 'EMPRESA', 'prueba', 'full', private.all_features(), 'Activa tu plan para seguir usando FacturaVoz',
       now() + interval '14 days'
from public.organizations o
on conflict (org_id) do nothing;

-- ───────────── Guardia de escritura (kill-switch + funciones del plan) ─────────────
-- Tabla → función del plan necesaria para CREAR registros (null = solo el estado de la licencia).
create or replace function private.feature_for(p_table text, p_row jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_table
    when 'quotes' then case when p_row ->> 'source' = 'store' then 'tienda' else 'cotizaciones' end
    when 'org_store' then 'tienda'
    when 'recurring_invoices' then 'recurrentes'
    when 'jobs' then case when p_row ->> 'kind' = 'cita' then 'agenda' else 'trabajos' end
    when 'job_materials' then 'trabajos'
    when 'job_milestones' then 'trabajos'
    when 'credit_ledger' then 'fiados'
    when 'cash_movements' then 'caja'
    when 'day_closings' then 'caja'
    when 'promotions' then 'precios'
    when 'coupons' then 'precios'
    when 'loyalty_ledger' then 'fidelizacion'
    when 'bank_lines' then 'conciliacion'
    when 'payment_notices' then 'avisos_pago'
    when 'org_api_keys' then 'api_publica'
    when 'org_webhooks' then 'api_publica'
    when 'surveys' then 'encuestas'
    when 'doc_links' then 'portal_cliente'
    else null end;
$$;

create or replace function private.license_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_org uuid := (case when tg_table_name = 'organizations' then v_row ->> 'id' else v_row ->> 'org_id' end)::uuid;
  v_feature text;
begin
  if v_org is null or not private.license_enforced() then return case when tg_op = 'DELETE' then old else new end; end if;
  -- Mantenimiento del servidor (sincronización con el Hub, exportación) puede saltar la guardia explícitamente.
  if current_setting('facturavoz.bypass_license', true) = 'on' then return case when tg_op = 'DELETE' then old else new end; end if;
  -- Borrado de la empresa completa (cerrar cuenta): se permite.
  if tg_op = 'DELETE' and not exists (select 1 from public.organizations o where o.id = v_org) then return old; end if;
  if not private.license_write_ok(v_org) then
    raise exception 'Tu licencia de FacturaVoz no permite cambios ahora (%). Renueva tu plan para continuar.', private.org_mode(v_org)
      using errcode = '42501', hint = 'license';
  end if;
  if tg_op = 'INSERT' then
    v_feature := private.feature_for(tg_table_name, v_row);
    if v_feature is not null and not private.has_feature(v_org, v_feature) then
      raise exception 'Tu plan no incluye esta función (%). Mejora tu plan para usarla.', v_feature using errcode = '42501', hint = 'feature';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- Se instala en TODAS las tablas de public con org_id (salvo las de control). Las migraciones futuras que creen tablas
-- con org_id solo deben llamar: select private.install_license_guards();
create or replace function private.install_license_guards()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  t text;
  n integer := 0;
  v_skip text[] := array['org_licenses', 'organization_members', 'audit_log', 'owner_alerts', 'trash', 'pin_grants', 'api_rate', 'webhook_outbox', 'job_events'];
begin
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
    where c.table_schema = 'public' and c.column_name = 'org_id'
  loop
    if t = any(v_skip) then continue; end if;
    execute format('create or replace trigger %I before insert or update or delete on public.%I for each row execute function private.license_guard()', t || '_license_guard', t);
    -- Lectura: política restrictiva (en 'restricted' solo el dueño/admin puede ver para exportar; en 'blocked' nadie)
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'license_read_' || t) then
      execute format('create policy %I on public.%I as restrictive for select to authenticated using (private.license_read_ok(org_id))', 'license_read_' || t, t);
    end if;
    n := n + 1;
  end loop;
  -- organizations NO se bloquea: el dueño debe poder registrar su RUC para activar la prueba o pagar.
  return n;
end;
$fn$;
revoke execute on function private.install_license_guards() from public, anon, authenticated;
select private.install_license_guards();

-- Archivos (Storage): no se suben fotos/logos con la licencia cortada.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage')
     and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'org_media_license') then
    create policy "org_media_license" on storage.objects as restrictive for insert to authenticated
      with check (bucket_id <> 'org-media' or private.license_write_ok(private.try_uuid((storage.foldername(name))[1])));
  end if;
end $$;

-- ───────────── Lo que la app consulta ─────────────
create or replace function private.my_license_impl(p_org uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l public.org_licenses;
  v_admin boolean;
  v_mode text;
  v_features jsonb;
begin
  if not exists (select 1 from public.organization_members m where m.org_id = p_org and m.user_id = (select auth.uid())) then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  v_admin := private.is_org_admin(p_org);
  v_mode := private.org_mode(p_org);
  select * into l from public.org_licenses where org_id = p_org;
  v_features := case when not private.license_enforced() or l.source in ('local', 'dev') then private.all_features()
                     else coalesce(l.features, '{}'::jsonb) end;
  return jsonb_build_object(
    'enforced', private.license_enforced(),
    'dev', not private.license_enforced(),
    'source', l.source,
    'mode', v_mode,
    'plan', coalesce(l.plan, 'EMPRESA'),
    'status', l.status,
    'features', v_features,
    'message', l.message,
    'pay_url', case when v_admin then l.pay_url end,
    'period_end', l.period_end,
    'grace_end', l.grace_end,
    'cut_at', coalesce(l.cut_at, l.grace_end),
    'is_trial', l.status = 'prueba',
    'last_sync_at', case when v_admin then l.last_sync_at end,
    'stale', l.source = 'hub' and l.token_exp is not null and l.token_exp < now(),
    'trial_requested', l.trial_requested_at is not null,
    'is_admin', v_admin);
end;
$$;
revoke execute on function private.my_license_impl(uuid) from public, anon;
grant execute on function private.my_license_impl(uuid) to authenticated;
create or replace function public.my_license(p_org uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$ select private.my_license_impl(p_org) $$;
revoke execute on function public.my_license(uuid) from public, anon;
grant execute on function public.my_license(uuid) to authenticated;

-- ───────────── Funciones SOLO del servidor (service_role) ─────────────
-- Aplica un token YA VERIFICADO (firma Ed25519, emisor, audiencia, fechas) por el servidor. Descarta tokens viejos (iat).
create or replace function public.license_apply(p_org uuid, p_payload jsonb, p_token text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_iat bigint := (p_payload ->> 'iat')::bigint;
  v_prev bigint;
begin
  if p_org is null or p_payload is null then raise exception 'Datos incompletos' using errcode = '22023'; end if;
  if not exists (select 1 from public.organizations o where o.id = p_org) then return 'unknown_org'; end if;
  select l.token_iat into v_prev from public.org_licenses l where l.org_id = p_org and l.source = 'hub';
  if v_prev is not null and v_iat is not null and v_iat < v_prev then return 'stale'; end if;
  insert into public.org_licenses as l (org_id, source, license_code, plan, status, mode, features, message, pay_url, period_end, grace_end, cut_at,
                                        auto_cut, token, token_iat, token_exp, last_sync_at, last_error, updated_at)
  values (p_org, 'hub', p_payload ->> 'lic', coalesce(p_payload ->> 'plan', 'BASICO'), coalesce(p_payload ->> 'status', 'pendiente'),
          coalesce(p_payload ->> 'mode', 'blocked'), coalesce(p_payload -> 'features', '{}'::jsonb), p_payload ->> 'message',
          case when (p_payload ->> 'pay_url') ~ '^https?://' then p_payload ->> 'pay_url' end,
          (p_payload ->> 'period_end')::timestamptz, (p_payload ->> 'grace_end')::timestamptz, (p_payload ->> 'cut_at')::timestamptz,
          coalesce((p_payload ->> 'auto_cut')::boolean, true), p_token, v_iat, to_timestamp((p_payload ->> 'exp')::bigint),
          now(), null, now())
  on conflict (org_id) do update set
    source = 'hub', license_code = excluded.license_code, plan = excluded.plan, status = excluded.status, mode = excluded.mode,
    features = excluded.features, message = excluded.message, pay_url = excluded.pay_url, period_end = excluded.period_end,
    grace_end = excluded.grace_end, cut_at = excluded.cut_at, auto_cut = excluded.auto_cut, token = excluded.token,
    token_iat = excluded.token_iat, token_exp = excluded.token_exp, last_sync_at = now(), last_error = null, updated_at = now();
  return 'ok';
end;
$$;

create or replace function public.license_mark(p_org uuid, p_trial_requested boolean, p_error text)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.org_licenses
     set trial_requested_at = case when p_trial_requested then coalesce(trial_requested_at, now()) else trial_requested_at end,
         last_error = left(p_error, 300), updated_at = now()
   where org_id = p_org;
$$;

-- Enciende/apaga el control de licencias. La PRIMERA vez que se enciende, las empresas en prueba local
-- reciben al menos 7 días desde ese momento (nadie queda bloqueado de golpe por haber migrado antes).
create or replace function public.license_set_enforced(p_on boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare v_was boolean := private.license_enforced();
begin
  insert into private.app_config (key, value, updated_at) values ('license_enforced', to_jsonb(coalesce(p_on, false)), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  if coalesce(p_on, false) and not v_was then
    update public.org_licenses set period_end = greatest(coalesce(period_end, now()), now() + interval '7 days'), updated_at = now()
     where source = 'local';
  end if;
  return coalesce(p_on, false) and not v_was;
end;
$$;

-- Empresas que aún usan la prueba local y ya registraron un RUC válido (para pedir su prueba en el Hub).
create or replace function public.license_pending_trials(p_limit integer default 50)
returns table (org_id uuid, ruc text, name text, owner_email text)
language sql
stable
security invoker
set search_path = ''
as $$
  select o.id, o.tax_id, o.name,
         (select u.email::text from public.organization_members m join auth.users u on u.id = m.user_id
           where m.org_id = o.id and m.role = 'owner' order by m.created_at limit 1)
  from public.org_licenses l join public.organizations o on o.id = l.org_id
  where l.source = 'local' and l.trial_requested_at is null and o.tax_id ~ '^(10|15|16|17|20)\d{9}$'
  order by o.created_at
  limit greatest(1, least(coalesce(p_limit, 50), 500));
$$;

revoke execute on function public.license_apply(uuid, jsonb, text), public.license_mark(uuid, boolean, text),
  public.license_set_enforced(boolean), public.license_pending_trials(integer) from public, anon, authenticated;
grant execute on function public.license_apply(uuid, jsonb, text), public.license_mark(uuid, boolean, text),
  public.license_set_enforced(boolean), public.license_pending_trials(integer) to service_role;

-- Tiempo real: el cambio de licencia llega al instante a la app del dueño
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'org_licenses') then
    alter publication supabase_realtime add table public.org_licenses;
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
