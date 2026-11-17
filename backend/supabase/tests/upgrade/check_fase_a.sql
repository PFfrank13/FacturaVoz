\set ON_ERROR_STOP 1
-- Verifica la transición local → Hub (20261209) sobre la réplica de producción.
create or replace function pg_temp.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin if not coalesce(p_ok, false) then raise exception 'FALLO: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
select org_id as org from public.organization_members where user_id = 'aaaaaaaa-0000-4000-8000-000000000001' \gset

-- ───── FASE A: sin corte de servicio ─────
select pg_temp.chk('respaldo del estado local guardado', (select before ->> 'source' = 'local' and hub_snapshot ->> 'license_code' = 'LIC-PRUEBA-0001' from private.license_v34_backups where org_id = :'org'));
select pg_temp.chk('en cola de reconciliación con el código del Hub', (select license_code = 'LIC-PRUEBA-0001' from private.license_reconcile_pending where org_id = :'org'));
select pg_temp.chk('FASE A no cambia la licencia (sigue local, full)', (select source = 'local' and mode = 'full' from public.org_licenses where org_id = :'org') and private.org_mode(:'org') = 'full');
select pg_temp.chk('preflight lee el estado sin exponer más', (public.license_preflight_state(:'org') ->> 'pending_code') = 'LIC-PRUEBA-0001' and (public.license_preflight_state(:'org') ->> 'source') = 'local');
select pg_temp.chk('datos preservados', (select count(*) from public.products where org_id = :'org') = 1 and (select count(*) from public.organization_members where org_id = :'org') = 1);
set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-000000000001', false);
select pg_temp.chk('my_license (propietario) sigue operando durante la FASE A', (select (x ->> 'mode') = 'full' and (x ->> 'reconciling')::boolean from (select public.my_license(:'org') x) s));
insert into public.clients(user_id, org_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', :'org', 'Venta durante la FASE A');
select pg_temp.chk('se puede seguir escribiendo durante la FASE A', (select count(*) from public.clients where name = 'Venta durante la FASE A') = 1);
select pg_temp.chk('authenticated NO puede leer el estado de preflight', not has_function_privilege('authenticated', 'public.license_preflight_state(uuid)', 'execute'));
reset role;

do $$ begin
  perform public.license_sync_apply((select org_id from public.organization_members limit 1), jsonb_build_object('tenant', gen_random_uuid()::text, 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900000, 'exp', 1795900000, 'mode', 'full'), 'tok');
  raise exception 'FALLO: aceptó tenant ajeno';
exception when insufficient_privilege then raise notice 'ok: tenant ajeno rechazado';
end $$;
-- Código distinto: NO toca nada (la empresa sigue operando).
select pg_temp.chk('código distinto: no cambia nada', public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'OTRO-CODIGO', 'iat', 1794900000, 'exp', 1795900000, 'plan', 'BASICO', 'status', 'prueba', 'mode', 'full', 'features', private.all_features(), 'period_end', '2026-11-30T05:00:00Z', 'auto_cut', true), 'tok-otro') = 'pending_code_mismatch');
select pg_temp.chk('…y la empresa sigue local y operando', (select source = 'local' and token <> 'tok-otro' from public.org_licenses where org_id = :'org') and private.org_mode(:'org') = 'full');
-- Código correcto (la prueba extendida en el Hub): pasa al Hub en UNA transacción, sin corte.
select pg_temp.chk('código correcto reconcilia', public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900100, 'exp', 1795900000, 'plan', 'BASICO', 'status', 'prueba', 'mode', 'full', 'features', private.all_features(), 'period_end', '2026-11-30T05:00:00Z', 'auto_cut', true), 'tok-hub') = 'reconciled');
select pg_temp.chk('ahora es Hub con token y sigue en full (sin corte)', (select source = 'hub' and token = 'tok-hub' from public.org_licenses where org_id = :'org') and private.org_mode(:'org') = 'full');
select pg_temp.chk('activación registrada por el propietario y cola vacía', exists (select 1 from private.org_license_activations where org_id = :'org' and license_code = 'LIC-PRUEBA-0001' and activated_by = 'aaaaaaaa-0000-4000-8000-000000000001') and not exists (select 1 from private.license_reconcile_pending where org_id = :'org'));
select pg_temp.chk('auditado', exists (select 1 from public.audit_log where org_id = :'org' and action = 'license.v34_reconciled'));
