-- FacturaVoz · Migración 21 · Servicios del servidor: caché DNI/RUC, anti-reproducción de webhooks del Hub,
-- límites de uso por tipo, reporte diario por correo y despacho opcional de webhooks cada minuto (pg_cron + pg_net).
-- Todo lo de este archivo lo escribe SOLO el servidor (service_role). Idempotente y aditiva. Ejecutar después de 20261111.
begin;

-- Caché de consultas DNI/RUC (evita gastar el cupo del proveedor y responde al instante). Sin acceso desde la app.
create table if not exists public.doc_lookups (
  doc_type text not null check (doc_type in ('dni', 'ruc')),
  number text not null check (number ~ '^\d{8}$|^\d{11}$'),
  data jsonb not null,
  fetched_at timestamptz not null default now(),
  primary key (doc_type, number)
);
alter table public.doc_lookups enable row level security; -- sin políticas: solo service_role
revoke all on public.doc_lookups from anon, authenticated;
grant select, insert, update, delete on public.doc_lookups to service_role;

-- Webhooks del Hub ya procesados (no se aplican dos veces)
create table if not exists public.solvex_events (
  id text primary key check (char_length(id) between 3 and 80),
  received_at timestamptz not null default now()
);
alter table public.solvex_events enable row level security;
revoke all on public.solvex_events from anon, authenticated;
grant select, insert, delete on public.solvex_events to service_role;

-- Uso por tipo (dictado, consulta de documento, IA de visión, copiloto) para límites justos por usuario
alter table public.api_usage add column if not exists kind text not null default 'parse';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'api_usage_kind_chk') then
    alter table public.api_usage add constraint api_usage_kind_chk check (kind ~ '^[a-z_]{2,20}$');
  end if;
end $$;
create index if not exists idx_api_usage_user_kind on public.api_usage(user_id, kind, created_at desc);
grant insert (user_id, kind) on public.api_usage to authenticated;

-- Reporte del cierre del día por correo al dueño
alter table public.org_settings
  add column if not exists daily_report boolean not null default false,
  add column if not exists daily_report_to text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'org_settings_report_chk') then
    alter table public.org_settings add constraint org_settings_report_chk check (
      daily_report_to is null or (daily_report_to ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(daily_report_to) <= 200));
  end if;
end $$;
grant insert (daily_report, daily_report_to) on public.org_settings to authenticated;
grant update (daily_report, daily_report_to) on public.org_settings to authenticated;

-- Régimen tributario del negocio (para el estimador de impuestos y el Copiloto). null = aún no lo indicó.
alter table public.org_settings add column if not exists tax_regime text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'org_settings_regime_chk') then
    alter table public.org_settings add constraint org_settings_regime_chk check (tax_regime is null or tax_regime in ('nrus', 'rer', 'rmt', 'general'));
  end if;
end $$;
grant insert (tax_regime) on public.org_settings to authenticated;
grant update (tax_regime) on public.org_settings to authenticated;

-- Limpieza periódica (la llama el cron del servidor)
create or replace function public.maintenance_cleanup()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare a integer; b integer; c integer;
begin
  delete from public.solvex_events where received_at < now() - interval '7 days';
  get diagnostics a = row_count;
  delete from public.doc_lookups where fetched_at < now() - interval '30 days';
  get diagnostics b = row_count;
  delete from public.webhook_outbox where (delivered_at is not null and delivered_at < now() - interval '14 days') or created_at < now() - interval '30 days';
  get diagnostics c = row_count;
  return jsonb_build_object('events', a, 'lookups', b, 'outbox', c, 'trash', private.purge_trash());
end;
$$;
revoke execute on function public.maintenance_cleanup() from public, anon, authenticated;
grant execute on function public.maintenance_cleanup() to service_role;
grant execute on function private.purge_trash() to service_role;

-- OPCIONAL: despachar webhooks cada minuto sin pagar Vercel Pro. Requiere activar pg_cron y pg_net en Supabase y
-- guardar la URL y el secreto con:
--   insert into private.app_config(key, value) values
--     ('dispatch_url', '"https://TU-APP.vercel.app/api/cron/webhooks"'), ('cron_secret', '"EL_MISMO_CRON_SECRET_DE_VERCEL"')
--   on conflict (key) do update set value = excluded.value;
create or replace function private.dispatch_webhooks_ping()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text := (select value #>> '{}' from private.app_config where key = 'dispatch_url');
  v_secret text := (select value #>> '{}' from private.app_config where key = 'cron_secret');
begin
  if v_url is null or v_secret is null then return; end if;
  if not exists (select 1 from public.webhook_outbox where delivered_at is null and attempts < 12 and next_at <= now()) then return; end if;
  execute 'select net.http_get(url := $1, headers := $2)' using v_url, jsonb_build_object('Authorization', 'Bearer ' || v_secret);
end;
$$;
revoke execute on function private.dispatch_webhooks_ping() from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'facturavoz-webhooks';
    perform cron.schedule('facturavoz-webhooks', '* * * * *', 'select private.dispatch_webhooks_ping()');
  end if;
exception when others then
  raise notice 'Despacho por minuto no programado: %', sqlerrm;
end $$;

-- Modo de licencia efectivo para procesos del servidor (API pública, cron): solo service_role.
create or replace function public.org_mode_service(p_org uuid)
returns text language sql stable security invoker set search_path = '' as $$ select private.org_mode(p_org) $$;
revoke execute on function public.org_mode_service(uuid) from public, anon, authenticated;
grant execute on function public.org_mode_service(uuid) to service_role;

grant execute on function public.sales_summary(uuid, date, date, text), private.invoice_voided(uuid) to service_role;

-- Tablas nuevas con org_id quedan bajo el control de licencias
select private.install_license_guards();

commit;

notify pgrst, 'reload schema';
