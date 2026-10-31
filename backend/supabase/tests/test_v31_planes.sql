\set ON_ERROR_STOP 1
-- v3.1: planes por rubro + tareas del Copiloto agente
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
insert into public.org_settings(org_id, business_type) values (:'org', 'bodega') on conflict (org_id) do update set business_type = 'bodega';
set role service_role;
select public.license_set_enforced(true);
reset role;

create or replace function pg_temp.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin if not p_ok then raise exception 'FALLO: %', p_name; end if; raise notice 'ok: %', p_name; end $$;

-- 1) BASICO · bodega: esenciales sí, estrella y copiloto no
set role service_role;
select public.license_apply(:'org', '{"iat":100,"exp":9999999999,"plan":"BASICO","status":"activa","mode":"full","features":{"max_users":1},"period_end":"2099-01-01T00:00:00Z","grace_end":"2099-01-05T00:00:00Z"}'::jsonb, 't1');
reset role;
select pg_temp.chk('basico bodega fiados', private.has_feature(:'org','fiados'));
select pg_temp.chk('basico bodega stock', private.has_feature(:'org','stock'));
select pg_temp.chk('basico bodega NO fidelizacion', not private.has_feature(:'org','fidelizacion'));
select pg_temp.chk('basico bodega NO copiloto', not private.has_feature(:'org','copiloto'));
select pg_temp.chk('basico bodega NO tienda', not private.has_feature(:'org','tienda'));
-- 2) PRO · bodega: estrella = fidelizacion + copiloto; sin agente, sin tienda
set role service_role;
select public.license_apply(:'org', '{"iat":200,"exp":9999999999,"plan":"PRO","status":"activa","mode":"full","features":{"max_users":5},"period_end":"2099-01-01T00:00:00Z","grace_end":"2099-01-05T00:00:00Z"}'::jsonb, 't2');
reset role;
select pg_temp.chk('pro bodega fidelizacion', private.has_feature(:'org','fidelizacion'));
select pg_temp.chk('pro bodega copiloto', private.has_feature(:'org','copiloto'));
select pg_temp.chk('pro bodega NO agente', not private.has_feature(:'org','copiloto_agente'));
select pg_temp.chk('pro bodega NO tienda', not private.has_feature(:'org','tienda'));
-- 3) mismo PRO pero rubro salón: estrella distinta
update public.org_settings set business_type = 'salon' where org_id = :'org';
select pg_temp.chk('pro salon comisiones', private.has_feature(:'org','comisiones'));
select pg_temp.chk('pro salon NO fidelizacion', not private.has_feature(:'org','fidelizacion'));
select pg_temp.chk('pro salon agenda (nucleo)', private.has_feature(:'org','agenda'));
-- 4) Complemento: el Hub activa "tienda" en BASICO (no es de ningún BASICO) → se respeta; en PRO salón (tienda es de PRO mayorista) no
set role service_role;
select public.license_apply(:'org', '{"iat":300,"exp":9999999999,"plan":"BASICO","status":"activa","mode":"full","features":{"tienda":true},"period_end":"2099-01-01T00:00:00Z","grace_end":"2099-01-05T00:00:00Z"}'::jsonb, 't3');
reset role;
select pg_temp.chk('addon tienda en basico', private.has_feature(:'org','tienda'));
set role service_role;
select public.license_apply(:'org', '{"iat":400,"exp":9999999999,"plan":"PRO","status":"activa","mode":"full","features":{"tienda":true},"period_end":"2099-01-01T00:00:00Z","grace_end":"2099-01-05T00:00:00Z"}'::jsonb, 't4');
reset role;
select pg_temp.chk('tienda en pro salon NO (no es complemento)', not private.has_feature(:'org','tienda'));
-- 5) my_license devuelve lo ya resuelto
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select pg_temp.chk('my_license efectivo comisiones', (public.my_license(:'org') -> 'features' ->> 'comisiones')::boolean);
select pg_temp.chk('my_license efectivo fidelizacion=false', (public.my_license(:'org') -> 'features' ->> 'fidelizacion')::boolean = false);
-- 6) Agente: PRO no puede crear tareas
\set ON_ERROR_STOP 0
insert into public.agent_tasks(org_id, prompt, title) values (:'org', 'cobra a los morosos', 'Cobranza');
\set ON_ERROR_STOP 1
select pg_temp.chk('pro no crea tareas del agente', (select count(*) from public.agent_tasks) = 0);
reset role;
-- 7) EMPRESA: todo, y el agente funciona con su flujo de estados
set role service_role;
select public.license_apply(:'org', '{"iat":500,"exp":9999999999,"plan":"EMPRESA","status":"activa","mode":"full","features":{"max_users":20},"period_end":"2099-01-01T00:00:00Z","grace_end":"2099-01-05T00:00:00Z"}'::jsonb, 't5');
reset role;
select pg_temp.chk('empresa agente', private.has_feature(:'org','copiloto_agente'));
select pg_temp.chk('empresa tienda', private.has_feature(:'org','tienda'));
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
insert into public.agent_tasks(org_id, prompt, title, plan) values (:'org', 'cobra a los morosos', 'Cobranza', '{"steps":[]}') returning id as task \gset
update public.agent_tasks set status = 'approved' where id = :'task';
select pg_temp.chk('aprobada registra quién', (select decided_by is not null from public.agent_tasks where id = :'task'));
update public.agent_tasks set status = 'done', result = '{"ok":true}' where id = :'task';
\set ON_ERROR_STOP 0
update public.agent_tasks set status = 'proposed' where id = :'task';
update public.agent_tasks set prompt = 'otro' where id = :'task';
\set ON_ERROR_STOP 1
select pg_temp.chk('tarea cerrada no se reabre', (select status from public.agent_tasks where id = :'task') = 'done');
-- no se puede saltar la aprobación
insert into public.agent_tasks(org_id, prompt, title) values (:'org', 'x', 'y') returning id as t2 \gset
\set ON_ERROR_STOP 0
update public.agent_tasks set status = 'done' where id = :'t2';
\set ON_ERROR_STOP 1
select pg_temp.chk('no se ejecuta sin aprobar', (select status from public.agent_tasks where id = :'t2') = 'proposed');
-- otro usuario de otra empresa no ve tareas
reset role;
insert into auth.users(id,email) values ('22222222-2222-2222-2222-222222222222','otro@b.pe') on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',false);
select pg_temp.chk('otra empresa no ve tareas', (select count(*) from public.agent_tasks) = 0);
\echo TODO OK
