\set ON_ERROR_STOP 1
-- v3.3: las políticas hub_feature_read_* siguen negando lo que el plan no trae, ahora sin evaluar por fila.
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe'),('22222222-2222-2222-2222-222222222222','otro@b.pe');
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
select org_id as org2 from public.organization_members where user_id='22222222-2222-2222-2222-222222222222' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
insert into public.clients(user_id,org_id,name) values (auth.uid(),:'org','Cliente A') returning id as ca \gset
insert into public.credit_ledger(org_id,client_id,kind,amount,user_id) values (:'org',:'ca','cargo',10,auth.uid());
insert into public.jobs(org_id,client_id,title,kind) values (:'org',:'ca','Cita','cita'),(:'org',:'ca','Orden','servicio');
create or replace function pg_temp.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin if not p_ok then raise exception 'FALLO: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
select pg_temp.chk('con plan completo ve fiados, citas y órdenes', (select count(*) from public.credit_ledger) = 1 and (select count(*) from public.jobs) = 2);
reset role;
-- El Hub quita fiados y agenda a esta empresa
update public.org_licenses set features = private.all_features() || '{"fiados":false,"agenda":false}'::jsonb where org_id = :'org';
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select pg_temp.chk('sin fiados en el plan: no ve la libreta', (select count(*) from public.credit_ledger) = 0);
select pg_temp.chk('sin agenda: no ve citas pero sí órdenes', (select count(*) from public.jobs where kind='cita') = 0 and (select count(*) from public.jobs where kind='servicio') = 1);
select pg_temp.chk('clientes siguen visibles', (select count(*) from public.clients) = 1);
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',false);
select pg_temp.chk('otra empresa no ve nada', (select count(*) from public.clients) = 0 and (select count(*) from public.jobs) = 0 and (select count(*) from public.credit_ledger) = 0);
