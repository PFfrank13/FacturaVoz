\set ON_ERROR_STOP 1
-- Verifica la transición local → Hub (20261209) sobre la réplica de producción.
create or replace function pg_temp.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin if not coalesce(p_ok, false) then raise exception 'FALLO: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
select org_id as org from public.organization_members where user_id = 'aaaaaaaa-0000-4000-8000-000000000001' \gset
select pg_temp.chk('respaldo del estado local guardado', (select before ->> 'source' = 'local' and hub_snapshot ->> 'license_code' = 'LIC-PRUEBA-0001' from private.license_v34_backups where org_id = :'org'));
select pg_temp.chk('en cola de reconciliación con el código del Hub', (select license_code = 'LIC-PRUEBA-0001' from private.license_reconcile_pending where org_id = :'org'));
select pg_temp.chk('licencia ya no es local y no tiene token', (select source = 'hub' and token is null and mode = 'blocked' and status = 'pendiente' from public.org_licenses where org_id = :'org'));
select pg_temp.chk('sin acceso comercial hasta verificar con el Hub', private.org_mode(:'org') = 'blocked' and private.effective_features(:'org') = '{}'::jsonb);
select pg_temp.chk('datos preservados', (select count(*) from public.products where org_id = :'org') = 1 and (select count(*) from public.organization_members where org_id = :'org') = 1);
select pg_temp.chk('el control no se puede apagar', private.license_enforced());
do $$ begin
  perform public.license_set_enforced(false);
  raise exception 'FALLO: license_set_enforced(false) no debió funcionar';
exception when insufficient_privilege then raise notice 'ok: license_set_enforced bloqueado';
end $$;
do $$ begin
  update public.org_licenses set source = 'local';
  raise exception 'FALLO: se pudo volver a local';
exception when check_violation then raise notice 'ok: source local rechazado por la base';
end $$;

-- Sesión real del propietario
set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-000000000001', false);
select pg_temp.chk('my_license (propietario): bloqueada y reconciliando', (select (x ->> 'mode') = 'blocked' and (x ->> 'reconciling')::boolean and not (x ->> 'activated')::boolean and (x ->> 'source') = 'hub' and not (x ->> 'dev')::boolean from (select public.my_license(:'org') x) s));
do $$ begin
  insert into public.clients(user_id, org_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', (select org_id from public.organization_members limit 1), 'X');
  raise exception 'FALLO: escribió sin licencia';
exception when insufficient_privilege then raise notice 'ok: escritura bloqueada sin licencia';
end $$;
reset role;

-- El backend verificó la firma y llama con el token del Hub. Tenant equivocado → error.
do $$ begin
  perform public.license_sync_apply((select org_id from public.organization_members limit 1), jsonb_build_object('tenant', gen_random_uuid()::text, 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900000, 'exp', 1795900000, 'mode', 'full'), 'tok');
  raise exception 'FALLO: aceptó tenant ajeno';
exception when insufficient_privilege then raise notice 'ok: tenant ajeno rechazado';
end $$;
-- Código distinto: aplica el estado del Hub pero NO activa (sigue bloqueada).
select pg_temp.chk('código distinto no activa', public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'OTRO-CODIGO', 'iat', 1794900000, 'exp', 1795900000, 'plan', 'BASICO', 'status', 'prueba', 'mode', 'full', 'features', private.all_features(), 'period_end', '2026-11-30T05:00:00Z', 'auto_cut', true), 'tok-otro') = 'ok' and private.org_mode(:'org') = 'blocked');
-- Código correcto (la prueba extendida en el Hub): reconcilia de forma atómica.
select pg_temp.chk('código correcto reconcilia', public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900100, 'exp', 1795900000, 'plan', 'BASICO', 'status', 'prueba', 'mode', 'full', 'features', private.all_features(), 'period_end', '2026-11-30T05:00:00Z', 'auto_cut', true), 'tok-hub') = 'reconciled');
select pg_temp.chk('activación registrada por el propietario y cola vacía', exists (select 1 from private.org_license_activations where org_id = :'org' and license_code = 'LIC-PRUEBA-0001' and activated_by = 'aaaaaaaa-0000-4000-8000-000000000001') and not exists (select 1 from private.license_reconcile_pending where org_id = :'org'));
select pg_temp.chk('auditado', exists (select 1 from public.audit_log where org_id = :'org' and action = 'license.v34_reconciled'));

set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-000000000001', false);
select pg_temp.chk('my_license refleja el Hub: prueba hasta 30-nov, full, activada', (select (x ->> 'mode') = 'full' and (x ->> 'status') = 'prueba' and (x ->> 'activated')::boolean and not (x ->> 'stale')::boolean and (x ->> 'period_end')::timestamptz = '2026-11-30T05:00:00Z' from (select public.my_license(:'org') x) s));
insert into public.clients(user_id, org_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', :'org', 'Cliente tras reconciliar');
reset role;

-- Renovación desde el Hub (token más nuevo)
select pg_temp.chk('renovación aplica', public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900200, 'exp', 1797900000, 'plan', 'PRO', 'status', 'activa', 'mode', 'full', 'features', private.all_features(), 'period_end', '2026-12-31T05:00:00Z', 'auto_cut', true), 'tok-renov') = 'ok');
select pg_temp.chk('renovación: plan y estado del Hub', (select plan = 'PRO' and status = 'activa' and period_end = '2026-12-31T05:00:00Z' from public.org_licenses where org_id = :'org'));
select pg_temp.chk('token viejo no retrocede el estado', public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900150, 'exp', 1795900000, 'plan', 'BASICO', 'status', 'prueba', 'mode', 'full'), 'tok-viejo') = 'stale');
select pg_temp.chk('el estado sigue en PRO', (select plan from public.org_licenses where org_id = :'org') = 'PRO');
-- Suspensión
select public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900300, 'exp', 1797900000, 'plan', 'PRO', 'status', 'suspendida', 'mode', 'restricted', 'features', private.all_features()), 'tok-susp');
set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-000000000001', false);
select pg_temp.chk('suspendida: modo restringido', public.my_license(:'org') ->> 'mode' = 'restricted');
do $$ begin
  insert into public.clients(user_id, org_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', (select org_id from public.organization_members limit 1), 'Y');
  raise exception 'FALLO: escribió suspendida';
exception when insufficient_privilege then raise notice 'ok: suspendida bloquea escrituras';
end $$;
select pg_temp.chk('suspendida: el propietario aún lee sus datos', (select count(*) from public.products) = 1);
reset role;
-- Reactivación
select public.license_sync_apply(:'org', jsonb_build_object('tenant', :'org', 'lic', 'LIC-PRUEBA-0001', 'iat', 1794900400, 'exp', 1797900000, 'plan', 'PRO', 'status', 'activa', 'mode', 'full', 'features', private.all_features()), 'tok-react');
set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-000000000001', false);
insert into public.clients(user_id, org_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', :'org', 'Cliente tras reactivar');
select pg_temp.chk('reactivada: vuelve a escribir', (select count(*) from public.clients where name like 'Cliente tras%') = 2);
reset role;
