\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.invite_member(:'org','caja@a.pe','cajero',false,'Lucía');
select public.my_license(:'org') ->> 'mode' as mode_dev, public.my_license(:'org') ->> 'dev' as dev;
reset role;
insert into auth.users(id,email) values ('44444444-4444-4444-4444-444444444444','caja@a.pe');
set role service_role;
select public.license_set_enforced(true);
-- token de plan BASICO activo
select public.license_apply(:'org', '{"iat":100,"exp":9999999999,"lic":"LIC-00001","plan":"BASICO","status":"activa","mode":"full","features":{"cotizaciones":false,"max_users":2},"period_end":"2099-01-01T00:00:00Z","grace_end":"2099-01-05T00:00:00Z"}'::jsonb, 'tok1');
select public.license_apply(:'org', '{"iat":50}'::jsonb, 'old') as older;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.my_license(:'org') ->> 'mode' as mode, public.my_license(:'org') ->> 'plan' as plan;
select invoice_id is not null as can_invoice from public.create_invoice('A', null, 18, 'PEN', null, null, '[{"description":"X","quantity":1,"unit_price":10}]'::jsonb, :'org');
\set ON_ERROR_STOP 0
select * from public.create_quote(:'org'::uuid, 'A', null, 18, 'PEN', null, null, '[{"description":"X","quantity":1,"unit_price":10}]'::jsonb);
select public.invite_member(:'org','tres@a.pe','cajero',false,null);
\set ON_ERROR_STOP 1
-- corte: grace pasada → restricted
reset role;
set role service_role;
select public.license_apply(:'org', '{"iat":200,"exp":9999999999,"plan":"BASICO","status":"gracia","mode":"warning","auto_cut":true,"features":{},"grace_end":"2020-01-01T00:00:00Z","pay_url":"https://hub.solvex.pe/p/abc"}'::jsonb, 'tok2');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.my_license(:'org') ->> 'mode' as mode_after_cut, public.my_license(:'org') ->> 'pay_url' as pay;
select count(*) as owner_can_read from public.invoices;
\set ON_ERROR_STOP 0
insert into public.clients(user_id,org_id,name) values (auth.uid(),:'org','Nuevo');
\set ON_ERROR_STOP 1
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',false);
select count(*) as cajero_can_read from public.invoices;
select public.my_license(:'org') ->> 'mode' as cajero_mode, public.my_license(:'org') ->> 'pay_url' as cajero_pay;
-- nueva empresa: prueba local
reset role;
insert into auth.users(id,email) values ('55555555-5555-5555-5555-555555555555','nuevo@b.pe');
select l.source, l.status, (l.period_end > now() + interval '2 days') as three_days from public.org_licenses l join public.organization_members m on m.org_id=l.org_id where m.user_id='55555555-5555-5555-5555-555555555555';
