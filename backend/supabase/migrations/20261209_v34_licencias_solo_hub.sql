-- v3.4 · LICENCIAS COMERCIALES SOLO DESDE SOLVEX HUB (orden maestra de producción, §2–§5).
--
-- Qué corrige (verificado contra producción el 2026-11-17, solo lectura):
--  * private.org_mode() en producción aceptaba source='local'/'dev' como acceso total ("full") sin token ni
--    activación, y devolvía 'full' si el control de licencias estaba apagado. Difiere del repositorio.
--  * La empresa existente quedó en source='local' (migración 20261108223032 isolated_bodega_local_plan, equivalente a
--    20261201_v32_local_dev_license_bodega.sql) y el webhook y la sincronización diaria SALTAN los tenants locales,
--    por eso la extensión de prueba hecha en el Hub nunca llegó a Supabase.
--  * private.license_enforced() devolvía false si faltaba la configuración (acceso total por omisión).
--  * apply_stock_on_issue(): min(uuid) no existe en PostgreSQL 17 y además descontaba stock por coincidencia de
--    descripción. Ahora solo descuenta con product_id explícito.
--
-- Transición de tenants locales (sin borrar datos):
--  1. Respaldo completo del estado actual en private.license_v34_backups.
--  2. La licencia pasa a source='hub', estado 'pendiente', modo 'blocked', SIN token: nadie obtiene acceso comercial
--     por esta migración.
--  3. Se registra private.license_reconcile_pending con el código de licencia que el Hub había entregado antes.
--  4. El backend (sincronización, webhook o POST /api/license/refresh) verifica la firma Ed25519, la audiencia (instancia)
--     y el tenant; si el código coincide, public.license_sync_apply() aplica el token y registra la activación de forma
--     atómica. Si el Hub no tiene licencia para ese tenant, la empresa queda pendiente hasta que el propietario active
--     un código válido.
--
-- Idempotente. Probada en PostgreSQL 17 (tests/test_v34_licencias_hub.sql, tests/test_v34_stock.sql).
-- NO aplicar en producción sin seguir docs/reconstruccion/08_RUNBOOK_PRODUCCION_V34.md.
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

-- ───────────── 3. Conversión respaldada de tenants local/dev ─────────────
create or replace function private.license_v34_convert_legacy()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_n integer;
begin
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

  update public.org_licenses l set
    source = 'hub',
    license_code = coalesce(b.snapshot ->> 'license_code', l.license_code),
    status = 'pendiente', mode = 'blocked', features = '{}'::jsonb,
    token = null, token_iat = null, token_exp = null,
    period_end = null, grace_end = null, cut_at = null, auto_cut = true, pay_url = null,
    message = 'Estamos verificando tu licencia con Solvex Hub.',
    last_error = null, updated_at = now()
  from public.org_licenses l2
  left join private.standalone_license_backups b on b.org_id = l2.org_id
  where l.org_id = l2.org_id and l.source in ('local', 'dev');
  get diagnostics v_n = row_count;

  perform private.audit(b.org_id, 'license.v34_legacy_to_hub', 'org_licenses', b.org_id::text,
                        jsonb_build_object('from_source', b.before ->> 'source', 'from_plan', b.before ->> 'plan'), null)
     from private.license_v34_backups b
    where b.saved_at >= now() - interval '1 minute';
  return v_n;
end $$;
revoke all on function private.license_v34_convert_legacy() from public, anon, authenticated;

select private.license_v34_convert_legacy();

-- Ninguna licencia vuelve a ser local o dev.
alter table public.org_licenses drop constraint if exists org_licenses_source_check;
alter table public.org_licenses add constraint org_licenses_source_check check (source = 'hub');

-- ───────────── 4. Aplicar tokens verificados por el backend ─────────────
-- Solo el backend (service_role) la llama, DESPUÉS de verificar firma Ed25519, audiencia y tenant.
-- Si la empresa está en la cola de reconciliación y el código firmado coincide, registra también la activación.
create or replace function private.license_sync_apply_impl(p_org uuid, p_payload jsonb, p_token text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_pending text;
  v_owner uuid;
  v_result text;
begin
  if p_org is null or p_payload is null or nullif(p_token, '') is null then
    raise exception 'Datos incompletos' using errcode = '22023';
  end if;
  if coalesce(p_payload ->> 'tenant', '') <> p_org::text then
    raise exception 'Licencia asociada a otra empresa' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_org::text), 9034);
  select r.license_code into v_pending from private.license_reconcile_pending r where r.org_id = p_org for update;
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
