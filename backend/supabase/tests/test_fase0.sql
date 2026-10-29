\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','a@a.pe') on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select org_id as org from public.organization_members limit 1 \gset
insert into public.import_jobs(org_id,user_id,file_name) values (:'org','11111111-1111-1111-1111-111111111111','x.xlsx') returning id as job \gset
select public.import_add_rows(:'job', '[{"client":"ACME","amount":"118","date":"2026-10-01","number":"F001-1"},{"client":"B","amount":"x"}]'::jsonb);
select public.import_start(:'job', 18);
select public.import_step(:'job', 500);
select public.import_step(:'job', 500);
select status, imported, skipped from public.import_jobs where id = :'job';
-- ventas: una emitida (importada, paid) + un borrador
select * from public.create_invoice('Juan', null, 18, 'PEN', null, null, '[{"description":"Corte","quantity":1,"unit_price":100}]'::jsonb, :'org');
select public.sales_summary(:'org', '2026-01-01', '2027-01-01', 'PEN');
