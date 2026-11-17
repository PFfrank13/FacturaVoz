-- v3.4 · FASE A — PREPARAR LA TRANSICIÓN A SOLVEX HUB SIN CORTE DE SERVICIO (orden de producción §3–§5).
--
-- Esta migración NO cambia el acceso de ninguna empresa: no toca org_mode, effective_features ni license_enforced,
-- no cambia org_licenses. Solo:
--  1. respalda el estado de las empresas local/dev (private.license_v34_backups) y las pone en una cola con el código de
--     licencia que el Hub ya les había dado (private.license_reconcile_pending);
--  2. instala license_sync_apply(): el backend la llama con un token YA verificado (firma Ed25519, audiencia, tenant).
--     Si la empresa es local y el código firmado coincide → en UNA transacción pasa a la licencia del Hub con su
--     activación (sin corte). Si no coincide → no cambia nada y responde 'pending_code_mismatch';
--  3. corrige apply_stock_on_issue (min(uuid) y descuento por descripción).
-- El modo estricto (sin licencias locales) es la FASE B (20261210), que se niega a ejecutarse si alguna empresa
-- quedaría bloqueada.
--
-- Idempotente. Probada en PostgreSQL 17 sobre una réplica del estado real de producción (tests/upgrade/run_upgrade.sh).
begin;

-- ───────────── 0. Respaldo y cola de reconciliación ─────────────
create table if not exists private.license_v34_backups (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  before jsonb not null,
  hub_snapshot jsonb,
  saved_at timestamptz not null default now()
);
alter table private.license_v34_backups enable row level security;
revoke all on private.license_v34_backups from public, anon, authenticated;

create table if not exists private.license_reconcile_pending (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  license_code text not null,
  created_at timestamptz not null default now()
);
alter table private.license_reconcile_pending enable row level security;
revoke all on private.license_reconcile_pending from public, anon, authenticated;

-- standalone_license_backups existe si se aplicó 20261201; en instalaciones nuevas puede no existir.
create table if not exists private.standalone_license_backups (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  snapshot jsonb not null,
  saved_at timestamptz not null default now()
);
alter table private.standalone_license_backups enable row level security;
revoke all on private.standalone_license_backups from public, anon, authenticated;

-- Respaldo del estado actual de las empresas local/dev y cola con su código del Hub. NO cambia su acceso.
insert into private.license_v34_backups(org_id, before, hub_snapshot)
select l.org_id, to_jsonb(l), b.snapshot
  from public.org_licenses l
  left join private.standalone_license_backups b on b.org_id = l.org_id
 where l.source in ('local', 'dev')
on conflict (org_id) do nothing;

insert into private.license_reconcile_pending(org_id, license_code)
select l.org_id, coalesce(b.snapshot ->> 'license_code', l.license_code)
  from public.org_licenses l
  left join private.standalone_license_backups b on b.org_id = l.org_id
 where l.source in ('local', 'dev')
   and coalesce(b.snapshot ->> 'license_code', l.license_code) is not null
on conflict (org_id) do update set license_code = excluded.license_code;

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
    'enforced', private.license_enforced(),
    'dev', not private.license_enforced(),
    'source', l.source,
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
    'stale', l.source = 'hub' and l.token_exp is not null and l.token_exp < now(),
    'activated', exists (select 1 from private.org_license_activations a where a.org_id = p_org and a.license_code = l.license_code),
    'reconciling', exists (select 1 from private.license_reconcile_pending r where r.org_id = p_org),
    'trial_requested', l.trial_requested_at is not null,
    'is_admin', v_admin);
end $$;


-- ───────────── 4. Aplicar tokens verificados por el backend ─────────────
-- Solo el backend (service_role) la llama, DESPUÉS de verificar firma Ed25519, audiencia y tenant.
-- Si la empresa está en la cola de reconciliación y el código firmado coincide, registra también la activación.
create or replace function private.license_sync_apply_impl(p_org uuid, p_payload jsonb, p_token text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_pending text;
  v_owner uuid;
  v_result text;
  v_source text;
begin
  if p_org is null or p_payload is null or nullif(p_token, '') is null then
    raise exception 'Datos incompletos' using errcode = '22023';
  end if;
  if coalesce(p_payload ->> 'tenant', '') <> p_org::text then
    raise exception 'Licencia asociada a otra empresa' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_org::text), 9034);
  select r.license_code into v_pending from private.license_reconcile_pending r where r.org_id = p_org for update;
  select l.source into v_source from public.org_licenses l where l.org_id = p_org for update;
  -- Transición sin corte: una empresa todavía local SOLO pasa al Hub si el código firmado coincide con el suyo.
  -- Si no coincide, no se toca nada (sigue operando) y el propietario debe activar su código nuevo.
  if v_source in ('local', 'dev') and (v_pending is null or v_pending is distinct from (p_payload ->> 'lic')) then
    return 'pending_code_mismatch';
  end if;
  v_result := public.license_apply(p_org, p_payload, p_token);
  if v_result <> 'ok' then return v_result; end if;
  if v_pending is not null and v_pending = (p_payload ->> 'lic') then
    select m.user_id into v_owner from public.organization_members m where m.org_id = p_org and m.role = 'owner' limit 1;
    insert into private.org_license_activations(org_id, license_code, activated_by, activated_at)
    values (p_org, v_pending, v_owner, now())
    on conflict (org_id) do update set license_code = excluded.license_code, activated_by = excluded.activated_by, activated_at = now();
    delete from private.license_reconcile_pending where org_id = p_org;
    perform private.audit(p_org, 'license.v34_reconciled', 'org_licenses', p_org::text,
                          jsonb_build_object('plan', p_payload ->> 'plan', 'mode', p_payload ->> 'mode'), v_owner);
    return 'reconciled';
  end if;
  return 'ok';
end $$;
revoke all on function private.license_sync_apply_impl(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function private.license_sync_apply_impl(uuid, jsonb, text) to service_role;
-- Envoltura pública (invoker) para PostgREST; solo service_role puede ejecutarla.
create or replace function public.license_sync_apply(p_org uuid, p_payload jsonb, p_token text)
returns text language sql security invoker set search_path = '' as $$ select private.license_sync_apply_impl(p_org, p_payload, p_token) $$;
revoke all on function public.license_sync_apply(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.license_sync_apply(uuid, jsonb, text) to service_role;

-- Activación con código por el propietario/administrador (api/license/activate): también cierra la reconciliación.
create or replace function public.license_activate_authorized(p_org uuid, p_user uuid, p_payload jsonb, p_token text)
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
  delete from private.license_reconcile_pending where org_id = p_org;
  perform private.audit(p_org, 'license.activated', 'org_licenses', p_org::text,
                        jsonb_build_object('plan', p_payload ->> 'plan', 'mode', p_payload ->> 'mode'), p_user);
  return 'ok';
end $$;
revoke all on function public.license_activate_authorized(uuid, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.license_activate_authorized(uuid, uuid, jsonb, text) to service_role;

-- Estado mínimo para el preflight del backend (solo lectura, solo service_role). Sin token ni código completo fuera del servidor.
create or replace function private.license_preflight_state_impl(p_org uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'source', (select l.source from public.org_licenses l where l.org_id = p_org),
    'license_code', (select l.license_code from public.org_licenses l where l.org_id = p_org),
    'pending_code', (select r.license_code from private.license_reconcile_pending r where r.org_id = p_org),
    'activated_code', (select a.license_code from private.org_license_activations a where a.org_id = p_org))
$$;
revoke all on function private.license_preflight_state_impl(uuid) from public, anon, authenticated;
grant execute on function private.license_preflight_state_impl(uuid) to service_role;
create or replace function public.license_preflight_state(p_org uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$ select private.license_preflight_state_impl(p_org) $$;
revoke all on function public.license_preflight_state(uuid) from public, anon, authenticated;
grant execute on function public.license_preflight_state(uuid) to service_role;

-- ───────────── 5. Inventario: solo con product_id explícito ─────────────
-- Una línea sin product_id (texto libre, dictado) NUNCA mueve stock ni bloquea la emisión.
create or replace function private.apply_stock_on_issue()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_before numeric(14,2);
  v_after numeric(14,2);
begin
  if old.status = 'draft' and new.status <> 'draft' then
    for r in
      select it.id as item_id, it.product_id, it.quantity
        from public.invoice_items it
       where it.invoice_id = new.id and it.product_id is not null
       order by it.product_id, it.id
    loop
      if r.quantity <= 0 or r.quantity > 100000 then
        raise exception 'Cantidad no válida en una línea de venta' using errcode = '22023';
      end if;
      if exists (select 1 from public.retail_sale_stock_events e where e.invoice_item_id = r.item_id) then
        raise exception 'La salida de inventario de esta línea ya existe' using errcode = '23505';
      end if;
      select p.stock into v_before from public.products p
       where p.org_id = new.org_id and p.id = r.product_id for update;
      if not found then
        raise exception 'Producto ajeno o inexistente' using errcode = '42501';
      end if;
      if v_before is null then continue; end if; -- producto sin control de stock
      v_after := v_before - r.quantity;
      if v_after < -10000000 or v_after > 10000000 then
        raise exception 'Stock fuera de límites técnicos' using errcode = '22023';
      end if;
      update public.products set stock = v_after where id = r.product_id and org_id = new.org_id;
      insert into public.retail_sale_stock_events(org_id, invoice_id, invoice_item_id, product_id, quantity_delta, stock_before, stock_after)
      values (new.org_id, new.id, r.item_id, r.product_id, -r.quantity, v_before, v_after);
    end loop;
  end if;
  return new;
end $$;
revoke all on function private.apply_stock_on_issue() from public, anon, authenticated;

commit;
notify pgrst, 'reload schema';
