-- ROLLBACK de 20261209_v34_licencias_solo_hub.sql (solo si la verificación posterior falla).
-- Restaura EXACTAMENTE el estado de licencias anterior desde private.license_v34_backups y la lógica previa de
-- org_mode/effective_features/license_enforced que tenía producción. No toca datos de negocio.
-- Probado en PostgreSQL 17 sobre la réplica de producción (tests/upgrade/run_upgrade.sh --rollback).
begin;
alter table public.org_licenses drop constraint if exists org_licenses_source_check;
alter table public.org_licenses add constraint org_licenses_source_check check (source = any (array['local','hub','dev']));

update public.org_licenses l set
  source = b.before ->> 'source', license_code = b.before ->> 'license_code', plan = b.before ->> 'plan',
  status = b.before ->> 'status', mode = b.before ->> 'mode', features = coalesce(b.before -> 'features', '{}'::jsonb),
  message = b.before ->> 'message', pay_url = b.before ->> 'pay_url',
  period_end = (b.before ->> 'period_end')::timestamptz, grace_end = (b.before ->> 'grace_end')::timestamptz,
  cut_at = (b.before ->> 'cut_at')::timestamptz, auto_cut = (b.before ->> 'auto_cut')::boolean,
  token = b.before ->> 'token', token_iat = (b.before ->> 'token_iat')::bigint, token_exp = (b.before ->> 'token_exp')::timestamptz,
  last_sync_at = (b.before ->> 'last_sync_at')::timestamptz, last_error = b.before ->> 'last_error', updated_at = now()
from private.license_v34_backups b
where b.org_id = l.org_id;
delete from private.license_reconcile_pending;

create or replace function private.license_enforced()
returns boolean language sql stable set search_path = '' as $$
  select coalesce((select (value)::text = 'true' from private.app_config where key = 'license_enforced'), false)
$$;

-- org_mode tal como estaba en producción el 2026-11-17 (acepta local/dev).
create or replace function private.org_mode(p_org uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
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
end $$;

-- effective_features con la rama local (20261201 / producción 20261108223032).
create or replace function private.effective_features(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  l public.org_licenses; v_rubro text; k text; v jsonb; out jsonb := '{}'::jsonb; allowed text[];
begin
  if not private.license_enforced() then return private.all_features(); end if;
  select * into l from public.org_licenses where org_id=p_org;
  if not found then return '{}'::jsonb; end if;
  if l.source='dev' then return private.all_features(); end if;
  select business_type into v_rubro from public.org_settings where org_id=p_org;
  if l.source='local' then
    allowed := private.plan_matrix(v_rubro,l.plan);
    for k,v in select * from jsonb_each(private.all_features()) loop
      if jsonb_typeof(v)='boolean' then out := out || jsonb_build_object(k,k=any(allowed));
      else out := out || jsonb_build_object(k,case k
          when 'max_users' then to_jsonb(case l.plan when 'BASICO' then 1 when 'PRO' then 5 else 20 end)
          when 'max_branches' then to_jsonb(case when l.plan='EMPRESA' then 5 else 1 end)
          else v end);
      end if;
    end loop;
    return out;
  end if;
  for k,v in select * from jsonb_each(private.all_features()) loop
    if jsonb_typeof(v)='boolean' then
      out := out || jsonb_build_object(k,private.plan_allows(v_rubro,l.plan,coalesce(l.features,'{}'::jsonb),k));
    else out := out || jsonb_build_object(k,coalesce(l.features->k,v));
    end if;
  end loop;
  return coalesce(l.features,'{}'::jsonb) || out;
end $$;
-- apply_stock_on_issue y license_sync_apply se dejan: son correcciones (la primera evita "min(uuid)") y no dan acceso.
commit;
notify pgrst, 'reload schema';
