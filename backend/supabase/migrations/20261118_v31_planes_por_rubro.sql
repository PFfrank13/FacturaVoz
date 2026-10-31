-- FacturaVoz · v3.1 · Membresías por rubro + Copiloto Pro / Empresa (agente con aprobación)
-- Mismos 3 planes y precios para todos; lo que desbloquea cada plan cambia según el rubro:
--   Básico  = lo esencial del rubro.
--   Pro     = Básico + UN módulo estrella del rubro + Copiloto (consultas con tus datos).
--   Empresa = TODO + Copiloto agente (le encargas una tarea, la prepara, tú la apruebas).
-- La tabla vive aquí (private.plan_matrix) y en la app (rubros.dart: planMatrix); una prueba exige que sean iguales.
-- Licencias del Hub: el plan decide; una función suelta que el Hub active y que NO sea parte del plan estándar
-- (complemento / add-on) se respeta. Aditiva e idempotente. Ejecutar después de 20261117.
begin;

create or replace function private.all_features()
returns jsonb language sql immutable set search_path = ''
as $$
  select '{"facturar":true,"clientes":true,"cobros":true,"voz":true,"cotizaciones":true,"tienda":true,"stock":true,
           "recurrentes":true,"copiloto":true,"copiloto_agente":true,"trabajos":true,"agenda":true,"reportes":true,"multisucursal":true,
           "fiados":true,"caja":true,"cuaderno_ia":true,"portal_cliente":true,"precios":true,"fidelizacion":true,
           "carta_qr":true,"conciliacion":true,"comisiones":true,"avisos_pago":true,"multimoneda":true,"api_publica":true,
           "encuestas":true,"antifraude":true,"max_users":-1,"max_branches":-1}'::jsonb;
$$;

-- Funciones que desbloquea cada plan para cada rubro (acumulativo: Pro incluye Básico; Empresa = todo).
create or replace function private.plan_matrix(p_rubro text, p_plan text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case
    when p_plan = 'EMPRESA' then array(select jsonb_object_keys(private.all_features()) except select unnest(array['max_users', 'max_branches']))
    else array['facturar','clientes','cobros','voz','cotizaciones','reportes','avisos_pago','caja']
      || case p_rubro
           when 'bodega' then array['stock','fiados']
           when 'restaurante' then array['carta_qr','stock']
           when 'servicios_tecnicos' then array['trabajos','agenda','recurrentes']
           when 'salon' then array['agenda']
           when 'consultorio' then array['agenda']
           when 'taller' then array['trabajos','stock']
           when 'mayorista' then array['stock','precios']
           when 'educacion' then array['recurrentes','agenda']
           when 'construccion' then array['trabajos']
           else array[]::text[] end
      || case when p_plan = 'PRO' then
           array['copiloto'] || case p_rubro
             when 'bodega' then array['fidelizacion']
             when 'restaurante' then array['agenda']
             when 'servicios_tecnicos' then array['portal_cliente']
             when 'salon' then array['comisiones']
             when 'consultorio' then array['recurrentes']
             when 'taller' then array['agenda']
             when 'mayorista' then array['tienda']
             when 'educacion' then array['portal_cliente']
             when 'construccion' then array['agenda']
             else array[]::text[] end
         else array[]::text[] end
  end
$$;

-- Unión de lo que el plan estándar da a ALGÚN rubro: lo que el Hub active fuera de eso es un complemento (add-on).
create or replace function private.plan_union(p_plan text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(distinct k), array[]::text[])
  from unnest(array['bodega','restaurante','servicios_tecnicos','salon','consultorio','taller','mayorista','educacion','construccion']) r,
       lateral unnest(private.plan_matrix(r, p_plan)) k
$$;

create or replace function private.plan_allows(p_rubro text, p_plan text, p_features jsonb, p_key text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v jsonb := p_features -> p_key;
  v_on boolean := case jsonb_typeof(v) when 'boolean' then v::text = 'true' when 'number' then (v::text)::numeric <> 0 else false end;
begin
  -- Plan o rubro desconocidos: se respeta la licencia tal cual (comportamiento anterior).
  if p_plan not in ('BASICO', 'PRO', 'EMPRESA') or p_rubro is null or p_rubro not in ('bodega','restaurante','servicios_tecnicos','salon','consultorio','taller','mayorista','educacion','construccion') then
    return v_on;
  end if;
  if p_key = any(private.rubro_core(p_rubro)) then return true; end if;
  if p_key = any(private.plan_matrix(p_rubro, p_plan)) then return true; end if;
  return v_on and not (p_key = any(private.plan_union(p_plan)));
end
$$;

-- Funciones efectivas de una empresa (todas las claves, true/false) + límites numéricos.
create or replace function private.effective_features(p_org uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l public.org_licenses;
  v_rubro text;
  k text;
  v jsonb;
  out jsonb := '{}'::jsonb;
begin
  if not private.license_enforced() then return private.all_features(); end if;
  select * into l from public.org_licenses where org_id = p_org;
  if not found or l.source in ('local', 'dev') then return private.all_features(); end if;
  select s.business_type into v_rubro from public.org_settings s where s.org_id = p_org;
  for k, v in select * from jsonb_each(private.all_features()) loop
    if jsonb_typeof(v) = 'boolean' then
      out := out || jsonb_build_object(k, private.plan_allows(v_rubro, l.plan, coalesce(l.features, '{}'::jsonb), k));
    else
      out := out || jsonb_build_object(k, coalesce(l.features -> k, v));
    end if;
  end loop;
  -- Claves extra que el Hub haya puesto (no listadas arriba) se conservan tal cual.
  return coalesce(l.features, '{}'::jsonb) || out;
end
$$;

create or replace function private.has_feature(p_org uuid, p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  l public.org_licenses;
  v_rubro text;
  v jsonb;
begin
  if not private.license_enforced() then return true; end if;
  if p_key in ('facturar', 'clientes', 'cobros', 'voz') then return true; end if;
  select * into l from public.org_licenses where org_id = p_org;
  if not found then return false; end if;
  if l.source in ('local', 'dev') then return true; end if;
  select s.business_type into v_rubro from public.org_settings s where s.org_id = p_org;
  return private.plan_allows(v_rubro, l.plan, coalesce(l.features, '{}'::jsonb), p_key);
end
$$;

revoke execute on function private.plan_matrix(text, text), private.plan_union(text), private.plan_allows(text, text, jsonb, text),
  private.effective_features(uuid) from public, anon;
grant execute on function private.plan_matrix(text, text), private.plan_union(text), private.plan_allows(text, text, jsonb, text),
  private.effective_features(uuid) to authenticated, service_role;

-- La app (y el Copiloto) leen las funciones YA resueltas por rubro y plan.
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
  v_features := private.effective_features(p_org);
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

-- ───────────── Copiloto agente (Empresa): tareas preparadas por el Copiloto y aprobadas por el dueño ─────────────
create table if not exists public.agent_tasks (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  prompt      text not null check (char_length(btrim(prompt)) between 1 and 1000),
  title       text not null default '' check (char_length(title) <= 160),
  status      text not null default 'proposed' check (status in ('proposed', 'approved', 'rejected', 'done', 'failed')),
  plan        jsonb not null default '{}'::jsonb check (jsonb_typeof(plan) = 'object' and pg_column_size(plan) < 200000),
  result      jsonb check (result is null or (jsonb_typeof(result) = 'object' and pg_column_size(result) < 100000)),
  decided_by  uuid references auth.users(id) on delete set null,
  decided_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists idx_agent_tasks_org on public.agent_tasks(org_id, created_at desc);
create index if not exists idx_agent_tasks_creator on public.agent_tasks(created_by);
create index if not exists idx_agent_tasks_decider on public.agent_tasks(decided_by);
alter table public.agent_tasks enable row level security;
drop policy if exists "agent_tasks_select" on public.agent_tasks;
create policy "agent_tasks_select" on public.agent_tasks for select to authenticated
  using (org_id = any ((select private.my_admin_org_ids())::uuid[]));
drop policy if exists "agent_tasks_insert" on public.agent_tasks;
create policy "agent_tasks_insert" on public.agent_tasks for insert to authenticated
  with check (created_by = (select auth.uid()) and status = 'proposed'
              and org_id = any ((select private.my_admin_org_ids())::uuid[])
              and private.has_feature(org_id, 'copiloto_agente'));
drop policy if exists "agent_tasks_update" on public.agent_tasks;
create policy "agent_tasks_update" on public.agent_tasks for update to authenticated
  using (org_id = any ((select private.my_admin_org_ids())::uuid[]) and private.has_feature(org_id, 'copiloto_agente'))
  with check (org_id = any ((select private.my_admin_org_ids())::uuid[]));
revoke all on public.agent_tasks from anon, authenticated;
grant select, insert on public.agent_tasks to authenticated;
grant update (status, result, decided_by, decided_at) on public.agent_tasks to authenticated;

-- Solo se pasa de 'proposed' a aprobar/rechazar y de 'approved' a hecho/fallido (nunca se reescribe una tarea cerrada).
create or replace function private.agent_task_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if not ((old.status = 'proposed' and new.status in ('approved', 'rejected'))
         or (old.status = 'approved' and new.status in ('done', 'failed'))) then
      raise exception 'Cambio de estado no permitido: % → %', old.status, new.status using errcode = '42501';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.status in ('rejected', 'done', 'failed') then
    raise exception 'La tarea ya está cerrada' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.status in ('approved', 'rejected') and old.status = 'proposed' then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  perform private.audit(new.org_id, 'agente.' || new.status, 'agent_tasks', new.id::text,
                        jsonb_build_object('titulo', new.title), auth.uid());
  return new;
end
$$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_agent_task_guard' and tgrelid = 'public.agent_tasks'::regclass) then
    create trigger trg_agent_task_guard before insert or update on public.agent_tasks
      for each row execute function private.agent_task_guard();
  end if;
end $$;

select private.install_license_guards();
commit;
