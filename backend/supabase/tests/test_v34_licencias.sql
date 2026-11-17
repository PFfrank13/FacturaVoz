\set ON_ERROR_STOP 1
-- v3.4 (instalación nueva, SIN la licencia sintética del arnés): una empresa nueva no tiene acceso hasta que el Hub lo firma.
create or replace function pg_temp.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin if not coalesce(p_ok,false) then raise exception 'FALLO: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe'),('33333333-3333-3333-3333-333333333333','cajero@a.pe');
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
select pg_temp.chk('empresa nueva: Hub pendiente y bloqueada', (select source='hub' and status='pendiente' and token is null from public.org_licenses where org_id=:'org') and private.org_mode(:'org')='blocked');
select pg_temp.chk('sin configuración no hay acceso total', private.license_enforced() and private.effective_features(:'org') = '{}'::jsonb);
-- Simula una empresa que quedó en la cola (venía de local) y el propietario activa con su código
insert into private.license_reconcile_pending(org_id, license_code) values (:'org', 'COD-1');
do $$ begin
  perform public.license_activate_authorized((select org_id from public.organization_members where user_id='11111111-1111-1111-1111-111111111111'), '33333333-3333-3333-3333-333333333333',
    jsonb_build_object('tenant',(select org_id from public.organization_members where user_id='11111111-1111-1111-1111-111111111111')::text,'lic','COD-1','iat',1,'exp',2000000000,'mode','full'), 't');
  raise exception 'FALLO: un no-miembro activó';
exception when insufficient_privilege then raise notice 'ok: solo propietario/administrador activa';
end $$;
select pg_temp.chk('activación con código', public.license_activate_authorized(:'org','11111111-1111-1111-1111-111111111111',
  jsonb_build_object('tenant',:'org','lic','COD-1','iat',100,'exp',2000000000,'plan','BASICO','status','prueba','mode','full','features',private.all_features(),'period_end','2026-12-01T00:00:00Z'), 'tok') = 'ok');
select pg_temp.chk('acceso total del Hub y cola cerrada', private.org_mode(:'org')='full' and not exists(select 1 from private.license_reconcile_pending where org_id=:'org'));
select pg_temp.chk('el plan Básico del Hub no trae Pro', (private.effective_features(:'org') ->> 'facturar')::boolean);
select pg_temp.chk('authenticated no puede llamar license_sync_apply', not has_function_privilege('authenticated','public.license_sync_apply(uuid,jsonb,text)','execute'));
select pg_temp.chk('authenticated no puede llamar license_activate_authorized', not has_function_privilege('authenticated','public.license_activate_authorized(uuid,uuid,jsonb,text)','execute'));
