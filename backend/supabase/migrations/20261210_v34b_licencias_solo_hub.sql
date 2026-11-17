-- v3.4 · FASE B — LICENCIAS SOLO DESDE SOLVEX HUB (modo estricto).
--
-- Se NIEGA a ejecutarse (y no cambia nada) si alguna empresa quedaría bloqueada:
--   * empresas todavía con source local/dev,
--   * empresas en la cola de reconciliación,
--   * empresas con token del Hub pero sin activación registrada de ese código.
-- Primero hay que completar la FASE A y la reconciliación verificada con el Hub (docs/reconstruccion/08_RUNBOOK_PRODUCCION_V34.md).
--
-- Después de esta fase: el control no se puede apagar; org_mode exige Hub + token + activación; no existen licencias local/dev.
-- Idempotente. Probada en PostgreSQL 17.
begin;

do $$
declare v_local int; v_pending int; v_unactivated int;
begin
  select count(*) into v_local from public.org_licenses where source <> 'hub';
  select count(*) into v_pending from private.license_reconcile_pending;
  select count(*) into v_unactivated from public.org_licenses l
   where l.source = 'hub' and l.token is not null
     and not exists (select 1 from private.org_license_activations a where a.org_id = l.org_id and a.license_code = l.license_code);
  if v_local + v_pending + v_unactivated > 0 then
    raise exception 'FASE B detenida para no bloquear empresas: % local/dev, % en reconciliación, % sin activación. Completa la FASE A y la reconciliación con Solvex Hub.',
      v_local, v_pending, v_unactivated using errcode = 'P0001';
  end if;
end $$;

-- ───────────── 1. El control de licencias no se puede apagar ─────────────
create or replace function private.license_enforced()
returns boolean language sql immutable set search_path = '' as $$ select true $$;

create or replace function public.license_set_enforced(p_on boolean)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  raise exception 'El control de licencias de Solvex Hub no se puede desactivar.' using errcode = '42501';
end $$;
revoke all on function public.license_set_enforced(boolean) from public, anon, authenticated, service_role;

-- ───────────── 2. Estado efectivo: solo Hub con token y activación ─────────────
create or replace function private.org_mode(p_org uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare l public.org_licenses;
begin
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
end $$;

create or replace function private.effective_features(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  l public.org_licenses;
  v_rubro text;
  k text;
  v jsonb;
  out jsonb := '{}'::jsonb;
begin
  select * into l from public.org_licenses where org_id = p_org;
  if not found or l.source <> 'hub' or l.token is null then return '{}'::jsonb; end if;
  select business_type into v_rubro from public.org_settings where org_id = p_org;
  for k, v in select * from jsonb_each(private.all_features()) loop
    if jsonb_typeof(v) = 'boolean' then
      out := out || jsonb_build_object(k, private.plan_allows(v_rubro, l.plan, coalesce(l.features, '{}'::jsonb), k));
    else
      -- Límites numéricos: los entrega el Hub; si faltan, 0 (denegado).
      out := out || jsonb_build_object(k, coalesce(l.features -> k, to_jsonb(0)));
    end if;
  end loop;
  return out;
end $$;

-- feature_for: producción había perdido invoices/clients/payments (deriva no versionada). Se restaura la tabla completa.
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
    else null end
$$;

create or replace function private.my_license_impl(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  l public.org_licenses;
  v_admin boolean;
  v_owner boolean;
begin
  if not exists (select 1 from public.organization_members m where m.org_id = p_org and m.user_id = (select auth.uid())) then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  v_admin := private.is_org_admin(p_org);
  v_owner := exists (select 1 from public.organization_members m where m.org_id = p_org and m.user_id = (select auth.uid()) and m.role = 'owner');
  select * into l from public.org_licenses where org_id = p_org;
  return jsonb_build_object(
    'enforced', true,
    'dev', false,
    'source', coalesce(l.source, 'hub'),
    'mode', private.org_mode(p_org),
    'plan', coalesce(l.plan, 'BASICO'),
    'status', coalesce(l.status, 'pendiente'),
    'features', private.effective_features(p_org),
    'message', l.message,
    'pay_url', case when v_owner then l.pay_url end,
    'period_end', l.period_end,
    'grace_end', l.grace_end,
    'cut_at', coalesce(l.cut_at, l.grace_end),
    'is_trial', l.status = 'prueba',
    'last_sync_at', case when v_admin then l.last_sync_at end,
    'stale', l.token_exp is not null and l.token_exp < now(),
    'activated', exists (select 1 from private.org_license_activations a where a.org_id = p_org and a.license_code = l.license_code),
    'reconciling', exists (select 1 from private.license_reconcile_pending r where r.org_id = p_org),
    'trial_requested', l.trial_requested_at is not null,
    'is_admin', v_admin);
end $$;

-- Ninguna licencia vuelve a ser local o dev.
alter table public.org_licenses drop constraint if exists org_licenses_source_check;
alter table public.org_licenses add constraint org_licenses_source_check check (source = 'hub');

commit;
notify pgrst, 'reload schema';
