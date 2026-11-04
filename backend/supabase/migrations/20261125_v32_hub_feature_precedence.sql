-- LOCAL REVIEW ONLY. Requires migrations through 20261124; do not apply to production automatically.
-- No license rows, activation state, enforcement configuration or Hub synchronization are changed.
begin;

-- Historical helper must never resurrect false/omitted Hub flags via a plan or rubro matrix.
create or replace function private.plan_allows(p_rubro text, p_plan text, p_features jsonb, p_key text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_features -> p_key = 'true'::jsonb, false);
$$;

create or replace function private.has_feature(p_org uuid, p_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(private.effective_features(p_org) -> p_key = 'true'::jsonb, false);
$$;

-- Missing/malformed limits deny instead of silently meaning unlimited. -1 is the only unlimited value.
create or replace function private.feature_limit(p_org uuid, p_key text)
returns integer language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := private.effective_features(p_org) -> p_key; n numeric;
begin
  if v is null or jsonb_typeof(v) <> 'number' then return 0; end if;
  n := (v::text)::numeric;
  if n <> trunc(n) or n < -1 or n > 2147483647 then return 0; end if;
  return n::integer;
end;
$$;

-- Validate both the old and new feature on updates (e.g. cita -> servicio).
-- Existing RLS and role guards remain in place.
create or replace function private.license_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_org uuid := (case when tg_table_name = 'organizations' then v_row ->> 'id' else v_row ->> 'org_id' end)::uuid;
  v_feature text;
begin
  if v_org is null or not private.license_enforced() then return case when tg_op = 'DELETE' then old else new end; end if;
  if current_setting('facturavoz.bypass_license', true) = 'on' then return case when tg_op = 'DELETE' then old else new end; end if;
  if tg_op = 'DELETE' and not exists(select 1 from public.organizations where id = v_org) then return old; end if;
  if not private.license_write_ok(v_org) then
    raise exception 'La licencia no permite cambios ahora.' using errcode = '42501', hint = 'license';
  end if;
  v_feature := private.feature_for(tg_table_name, v_row);
  if v_feature is not null and not private.has_feature(v_org, v_feature) then
    raise exception 'La licencia no permite esta función.' using errcode = '42501', hint = 'feature';
  end if;
  if tg_op = 'UPDATE' then
    if to_jsonb(old) ->> 'org_id' is distinct from v_row ->> 'org_id' then
      raise exception 'No se permite trasladar registros entre empresas.' using errcode = '42501';
    end if;
    v_feature := private.feature_for(tg_table_name, to_jsonb(old));
    if v_feature is not null and not private.has_feature(v_org, v_feature) then
      raise exception 'La licencia no permite modificar esta función.' using errcode = '42501', hint = 'feature';
    end if;
  end if;
  -- Catalog prices remain usable for invoicing; stock mutations require stock explicitly.
  if tg_table_name = 'products' and tg_op <> 'DELETE' then
    if (tg_op = 'INSERT' and (v_row ->> 'stock' is not null or v_row ->> 'reorder_point' is not null))
       or (tg_op = 'UPDATE' and ((to_jsonb(old) -> 'stock') is distinct from (v_row -> 'stock')
         or (to_jsonb(old) -> 'reorder_point') is distinct from (v_row -> 'reorder_point'))) then
      if not private.has_feature(v_org, 'stock') then
        raise exception 'La licencia no permite modificar inventario.' using errcode = '42501', hint = 'feature';
      end if;
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- Additional restrictive SELECT policies: a route cannot be bypassed with a direct table request.
-- Products retain the existing shared catalog policy; conditional column visibility needs a separate API.
do $policy$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname='public'
    and tablename in ('invoices','clients','payments','quotes','jobs','credit_ledger','cash_movements',
      'day_closings','promotions','coupons','recurring_invoices','job_materials','job_milestones')
  loop
    if not exists(select 1 from pg_policies where schemaname='public' and tablename=t and policyname='hub_feature_read_' || t) then
      execute format('create policy %I on public.%I as restrictive for select to authenticated using (private.has_feature(org_id, private.feature_for(%L, to_jsonb(%I))))',
        'hub_feature_read_' || t, t, t, t);
    end if;
  end loop;
end;
$policy$;
commit;
