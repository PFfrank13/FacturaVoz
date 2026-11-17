\set ON_ERROR_STOP 1
-- v3.3: solo el PROPIETARIO recibe el enlace de pago y can.license; el administrador no (decide la base, no la app).
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe');
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
update public.org_licenses set pay_url='https://pagos.example/plan' where org_id=:'org';
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.invite_member(:'org','admin@a.pe','cajero',true,'Ana');
reset role;
insert into auth.users(id,email) values ('22222222-2222-2222-2222-222222222222','admin@a.pe');
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',false);
select public.claim_invites();
create or replace function pg_temp.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin if not p_ok then raise exception 'FALLO: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
select pg_temp.chk('admin es administrador', (public.my_access(:'org')->>'is_admin')::boolean);
select pg_temp.chk('admin SIN enlace de pago', public.my_license(:'org')->>'pay_url' is null);
select pg_temp.chk('admin SIN can.license', not (public.my_access(:'org')->'can'->>'license')::boolean);
select pg_temp.chk('admin conserva equipo y ajustes', (public.my_access(:'org')->'can'->>'team')::boolean and (public.my_access(:'org')->'can'->>'settings')::boolean);
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select pg_temp.chk('propietario CON enlace de pago', public.my_license(:'org')->>'pay_url' = 'https://pagos.example/plan');
select pg_temp.chk('propietario CON can.license', (public.my_access(:'org')->'can'->>'license')::boolean);
