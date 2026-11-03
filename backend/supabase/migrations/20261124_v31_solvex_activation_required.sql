-- FacturaVoz v3.1 · Activación obligatoria de licencias expedidas por Solvex Hub.
-- ATENCIÓN: bloquea deliberadamente TODAS las empresas que usan prueba local/dev.
-- Probar en staging y entregar licencias a clientes existentes ANTES de aplicarlo en producción.
-- Ejecutar DESPUÉS de 20261123. No borra empresas ni sus ventas.
begin;

-- La empresa se crea como pendiente. No hay prueba local automática.
create or replace function private.org_license_init()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.org_licenses (org_id, source, plan, status, mode, features, message, period_end)
  values (new.id, 'hub', 'BASICO', 'pendiente', 'blocked', '{}'::jsonb,
    'Introduce la licencia asignada por Solvex Hub para activar tu negocio.', null)
  on conflict (org_id) do nothing;
  return new;
end;
$$;

-- Las organizaciones antiguas sin licencia del Hub pasan a activación pendiente.
-- Las ya activadas en Hub permanecen intactas.
update public.org_licenses
   set source = 'hub', plan = 'BASICO', status = 'pendiente', mode = 'blocked',
       features = '{}'::jsonb, message = 'Introduce la licencia de Solvex Hub para activar tu negocio.',
       period_end = null, grace_end = null, cut_at = null, token = null,
       token_iat = null, token_exp = null, last_error = null, updated_at = now()
 where source in ('local', 'dev');

insert into public.org_licenses (org_id, source, plan, status, mode, features, message)
select o.id, 'hub', 'BASICO', 'pendiente', 'blocked', '{}'::jsonb,
       'Introduce la licencia de Solvex Hub para activar tu negocio.'
  from public.organizations o
 where not exists (select 1 from public.org_licenses l where l.org_id = o.id);

-- El Hub puede enviar webhooks ANTES de que el cliente escriba su clave.
-- Nunca debe desbloquear la empresa sólo por recibir un token válido.
create table if not exists private.org_license_activations (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  license_code text not null,
  activated_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz not null default now()
);
revoke all on private.org_license_activations from public, anon, authenticated;
grant select, insert, update on private.org_license_activations to service_role;

-- Modo real: además del Hub exige que el cliente haya introducido una clave
-- correspondiente a la licencia ACTUAL de la empresa.
create or replace function private.org_mode(p_org uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare l public.org_licenses;
begin
  if not private.license_enforced() then return 'blocked'; end if;
  select * into l from public.org_licenses where org_id = p_org;
  if not found or l.source <> 'hub' or l.token is null then return 'blocked'; end if;
  if not exists (select 1 from private.org_license_activations a
                 where a.org_id = p_org and a.license_code = l.license_code) then
    return 'blocked';
  end if;
  if l.mode in ('full', 'warning') and l.auto_cut
     and coalesce(l.cut_at, l.grace_end) is not null
     and now() > coalesce(l.cut_at, l.grace_end) then
    return 'restricted';
  end if;
  return l.mode;
end;
$$;

-- Sólo el servidor con service_role invoca esta operación después de validar
-- la firma del Hub, su audiencia, la empresa y el código proporcionado.
create or replace function public.license_activate_authorized(
  p_org uuid, p_user uuid, p_payload jsonb, p_token text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_result text;
        v_code text := p_payload ->> 'lic';
begin
  if p_org is null or p_user is null or nullif(v_code, '') is null then
    raise exception 'Datos de activación incompletos' using errcode = '22023';
  end if;
  if not exists(select 1 from public.organization_members m
      where m.org_id = p_org and m.user_id = p_user and m.role in ('owner','admin')) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if coalesce(p_payload ->> 'tenant', '') <> p_org::text then
    raise exception 'Licencia asociada a otra empresa' using errcode = '42501';
  end if;
  v_result := public.license_apply(p_org, p_payload, p_token);
  if v_result <> 'ok' then return v_result; end if;
  insert into private.org_license_activations(org_id, license_code, activated_by, activated_at)
    values(p_org, v_code, p_user, now())
    on conflict (org_id) do update set license_code = excluded.license_code,
      activated_by = excluded.activated_by, activated_at = now();
  return 'ok';
end;
$$;
revoke all on function public.license_activate_authorized(uuid,uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.license_activate_authorized(uuid,uuid,jsonb,text) to service_role;

-- La licencia del Hub es la fuente de verdad. No desbloqueamos módulos solo
-- porque el nombre del plan coincide con una matriz de valores locales.
create or replace function private.effective_features(p_org uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select l.features from public.org_licenses l
                    where l.org_id = p_org and l.source = 'hub' and l.token is not null
                      and private.org_mode(p_org) in ('full','warning')),
                  '{}'::jsonb);
$$;

create or replace function private.has_feature(p_org uuid, p_key text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  v := private.effective_features(p_org) -> p_key;
  return case jsonb_typeof(v)
    when 'boolean' then v::text = 'true'
    when 'number' then (v::text)::numeric <> 0
    else false end;
end;
$$;

-- Las operaciones fundamentales también respetan los flags del plan
-- (antes se trataban como siempre incluidas, aunque Hub las apagara).
create or replace function private.feature_for(p_table text, p_row jsonb)
returns text language sql immutable set search_path = '' as $$
  select case p_table
    when 'invoices' then 'facturar'
    when 'clients' then 'clientes'
    when 'payments' then 'cobros'
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

-- Límite anti-fuerza-bruta de activación. Sólo service_role ve estos intentos;
-- NO almacenamos el código introducido ni contraseñas.
create table if not exists private.license_activation_attempts (
  id bigint generated always as identity primary key,
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_license_activation_attempts_org_time
  on private.license_activation_attempts (org_id, created_at desc);
revoke all on private.license_activation_attempts from public, anon, authenticated;
grant select, insert, delete on private.license_activation_attempts to service_role;

-- RPC service_role, limitación atómica entre instancias Vercel (sin exponer private por PostgREST).
create or replace function public.license_activation_attempt(p_org uuid, p_user uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_org::text), 9024);
  if (select count(*) from private.license_activation_attempts
      where org_id = p_org and created_at > now() - interval '1 hour') >= 8 then
    return false;
  end if;
  insert into private.license_activation_attempts (org_id, user_id) values (p_org, p_user);
  return true;
end;
$$;
revoke all on function public.license_activation_attempt(uuid,uuid) from public, anon, authenticated;
grant execute on function public.license_activation_attempt(uuid,uuid) to service_role;

-- Fallar cerrado incluso si el Hub aún no está conectado. El cron ya no debe
-- apagar este indicador cuando faltan credenciales.
insert into private.app_config (key, value, updated_at)
values ('license_enforced', 'true'::jsonb, now())
on conflict (key) do update set value = 'true'::jsonb, updated_at = now();

-- Se conservan los controles RLS y triggers instalados previamente.
select private.install_license_guards();
commit;
