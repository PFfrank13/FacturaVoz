-- FacturaVoz v3 · D3 voz premium (ElevenLabs) + J consultas DNI/RUC (APISPERU) con consumo controlado.
--   tts_usage / tts_global : caracteres sintetizados por empresa y por día (solo cuentan los que NO estaban en caché).
--   lookup_usage           : consultas DNI/RUC que salieron al proveedor, por empresa/usuario/día.
--   Caché DNI 180 días, RUC 15 días (la limpieza ya no borra los DNI a los 30 días).
-- Las claves (ELEVENLABS_API_KEY, DOC_API_TOKEN) NUNCA tocan la base: viven solo en Vercel.
-- Aditiva e idempotente. Requiere 20261115.
begin;

-- ───────────── Voz ─────────────
create table if not exists public.tts_usage (
  org_id   uuid not null references public.organizations(id) on delete cascade,
  day      date not null,
  chars    integer not null default 0 check (chars >= 0),
  requests integer not null default 0 check (requests >= 0),
  primary key (org_id, day)
);
create table if not exists public.tts_global (
  day   date primary key,
  chars integer not null default 0 check (chars >= 0)
);
alter table public.tts_usage enable row level security;
alter table public.tts_global enable row level security;
drop policy if exists "tts_usage_select" on public.tts_usage;
create policy "tts_usage_select" on public.tts_usage for select to authenticated
  using (org_id = any ((select private.my_org_ids())::uuid[]));
revoke all on public.tts_usage, public.tts_global from anon, authenticated;
grant select on public.tts_usage to authenticated;

-- Caracteres de voz premium por día según el plan (frases ya generadas no cuentan: salen de la caché).
create or replace function private.tts_daily_limit(p_org uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when l.source in ('local', 'dev') or l.org_id is null then 1500
    when l.plan = 'EMPRESA' then 6000
    when l.plan = 'PRO' then 2000
    else 300 end
  from (select 1) x left join public.org_licenses l on l.org_id = p_org
$$;

-- Reserva caracteres: false si se pasa del día de la empresa o del tope global (p_global_cap, 0 = sin tope).
create or replace function private.consume_tts_impl(p_org uuid, p_chars integer, p_global_cap integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := private.today_pe();
  v_limit integer := private.tts_daily_limit(p_org);
  v_used integer;
  v_global integer;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  if p_chars is null or p_chars < 1 or p_chars > 1200 then raise exception 'Texto no válido' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('tts:' || v_day::text, 0));
  select coalesce(u.chars, 0) into v_used from public.tts_usage u where u.org_id = p_org and u.day = v_day;
  v_used := coalesce(v_used, 0);
  select coalesce(g.chars, 0) into v_global from public.tts_global g where g.day = v_day;
  v_global := coalesce(v_global, 0);
  if v_used + p_chars > v_limit then
    return jsonb_build_object('ok', false, 'reason', 'org_limit', 'used', v_used, 'limit', v_limit);
  end if;
  if coalesce(p_global_cap, 0) > 0 and v_global + p_chars > p_global_cap then
    return jsonb_build_object('ok', false, 'reason', 'global_limit', 'used', v_used, 'limit', v_limit);
  end if;
  insert into public.tts_usage as u (org_id, day, chars, requests) values (p_org, v_day, p_chars, 1)
    on conflict (org_id, day) do update set chars = u.chars + excluded.chars, requests = u.requests + 1;
  insert into public.tts_global as g (day, chars) values (v_day, p_chars)
    on conflict (day) do update set chars = g.chars + excluded.chars;
  return jsonb_build_object('ok', true, 'used', v_used + p_chars, 'limit', v_limit);
end;
$$;

create or replace function private.voice_quota_impl(p_org uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_used integer;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  select u.chars into v_used from public.tts_usage u where u.org_id = p_org and u.day = private.today_pe();
  return jsonb_build_object('used', coalesce(v_used, 0), 'limit', private.tts_daily_limit(p_org));
end;
$$;

create or replace function public.consume_tts(p_org uuid, p_chars integer, p_global_cap integer default 0)
returns jsonb language sql security invoker set search_path = '' as $$ select private.consume_tts_impl(p_org, p_chars, p_global_cap) $$;
create or replace function public.voice_quota(p_org uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$ select private.voice_quota_impl(p_org) $$;

revoke execute on function private.tts_daily_limit(uuid), private.consume_tts_impl(uuid, integer, integer), private.voice_quota_impl(uuid),
  public.consume_tts(uuid, integer, integer), public.voice_quota(uuid) from public, anon;
grant execute on function private.tts_daily_limit(uuid), private.consume_tts_impl(uuid, integer, integer), private.voice_quota_impl(uuid),
  public.consume_tts(uuid, integer, integer), public.voice_quota(uuid) to authenticated;

-- Caché de audios (MP3) en Storage, privado: solo el servidor lee y escribe.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public) values ('tts-cache', 'tts-cache', false) on conflict (id) do nothing;
  end if;
exception when others then
  raise notice 'Crea el bucket privado "tts-cache" en Supabase Storage: %', sqlerrm;
end $$;

-- ───────────── Consultas DNI/RUC ─────────────
create table if not exists public.lookup_usage (
  org_id  uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null,
  n       integer not null default 0 check (n >= 0),
  primary key (org_id, user_id, day)
);
create index if not exists idx_lookup_usage_user on public.lookup_usage(user_id);
create index if not exists idx_lookup_usage_day on public.lookup_usage(org_id, day);
alter table public.lookup_usage enable row level security;
drop policy if exists "lookup_usage_select" on public.lookup_usage;
create policy "lookup_usage_select" on public.lookup_usage for select to authenticated
  using (org_id = any ((select private.my_org_ids())::uuid[]));
revoke all on public.lookup_usage from anon, authenticated;
grant select on public.lookup_usage to authenticated;

create or replace function private.lookup_daily_limit(p_org uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when l.source in ('local', 'dev') or l.org_id is null then 100
    when l.plan = 'EMPRESA' then 600
    when l.plan = 'PRO' then 200
    else 60 end
  from (select 1) x left join public.org_licenses l on l.org_id = p_org
$$;

-- Una consulta al proveedor: máx. 40 por persona y el tope del plan por empresa, por día (la caché no cuenta).
create or replace function private.consume_lookup_impl(p_org uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_day date := private.today_pe();
  v_mine integer;
  v_org integer;
  v_limit integer := private.lookup_daily_limit(p_org);
begin
  if v_uid is null or not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('lookup:' || p_org::text, 0));
  select coalesce(sum(n) filter (where user_id = v_uid), 0), coalesce(sum(n), 0) into v_mine, v_org
    from public.lookup_usage where org_id = p_org and day = v_day;
  if v_mine >= 40 then return jsonb_build_object('ok', false, 'reason', 'user_limit', 'used', v_org, 'limit', v_limit); end if;
  if v_org >= v_limit then return jsonb_build_object('ok', false, 'reason', 'org_limit', 'used', v_org, 'limit', v_limit); end if;
  insert into public.lookup_usage as u (org_id, user_id, day, n) values (p_org, v_uid, v_day, 1)
    on conflict (org_id, user_id, day) do update set n = u.n + 1;
  return jsonb_build_object('ok', true, 'used', v_org + 1, 'limit', v_limit);
end;
$$;

create or replace function private.lookup_quota_impl(p_org uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  return jsonb_build_object(
    'used', (select coalesce(sum(n), 0) from public.lookup_usage where org_id = p_org and day = private.today_pe()),
    'month', (select coalesce(sum(n), 0) from public.lookup_usage where org_id = p_org and day >= date_trunc('month', private.today_pe())::date),
    'limit', private.lookup_daily_limit(p_org));
end;
$$;

create or replace function public.consume_lookup(p_org uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.consume_lookup_impl(p_org) $$;
create or replace function public.lookup_quota(p_org uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$ select private.lookup_quota_impl(p_org) $$;
revoke execute on function private.lookup_daily_limit(uuid), private.consume_lookup_impl(uuid), private.lookup_quota_impl(uuid),
  public.consume_lookup(uuid), public.lookup_quota(uuid) from public, anon;
grant execute on function private.lookup_daily_limit(uuid), private.consume_lookup_impl(uuid), private.lookup_quota_impl(uuid),
  public.consume_lookup(uuid), public.lookup_quota(uuid) to authenticated;

-- Limpieza: DNI 180 días, RUC 60 días (se usan hasta 15 días "frescos"; después solo si el proveedor está caído).
create or replace function public.maintenance_cleanup()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare a integer; b integer; c integer; d integer;
begin
  delete from public.solvex_events where received_at < now() - interval '7 days';
  get diagnostics a = row_count;
  delete from public.doc_lookups where (doc_type = 'dni' and fetched_at < now() - interval '180 days')
                                    or (doc_type = 'ruc' and fetched_at < now() - interval '60 days');
  get diagnostics b = row_count;
  delete from public.webhook_outbox where (delivered_at is not null and delivered_at < now() - interval '14 days') or created_at < now() - interval '30 days';
  get diagnostics c = row_count;
  delete from public.tts_global where day < private.today_pe() - 400;
  delete from public.lookup_usage where day < private.today_pe() - 400;
  get diagnostics d = row_count;
  return jsonb_build_object('events', a, 'lookups', b, 'outbox', c, 'usage', d, 'trash', private.purge_trash());
end;
$$;
revoke execute on function public.maintenance_cleanup() from public, anon, authenticated;
grant execute on function public.maintenance_cleanup() to service_role;

select private.install_license_guards();

commit;

notify pgrst, 'reload schema';
