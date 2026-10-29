\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','a@a.pe') on conflict do nothing;
select org_id as org from public.organization_members limit 1 \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select invoice_id as inv from public.create_invoice('Juan', '20100070970', 18, 'PEN', null, null, '[{"description":"Corte","quantity":1,"unit_price":100}]'::jsonb, :'org') \gset
reset role;
set role service_role;
select * from public.fiscal_reserve(:'org','11111111-1111-1111-1111-111111111111',:'inv','01','F001','{}'::jsonb,'{}'::jsonb,'SON','gravado','beta');
select public.fiscal_record(:'org',:'inv','rejected','2017','RUC no valido',null,null,null,null);
select out_series, out_correlative, out_status from public.fiscal_reserve(:'org','11111111-1111-1111-1111-111111111111',:'inv','01','F001','{}'::jsonb,'{}'::jsonb,'SON','gravado','beta');
select series, correlative, sunat_code from public.fiscal_rejections;
select series, correlative, status from public.fiscal_documents;
-- reintento sin rechazo conserva número
select out_correlative from public.fiscal_reserve(:'org','11111111-1111-1111-1111-111111111111',:'inv','01','F001','{}'::jsonb,'{}'::jsonb,'SON','gravado','beta');
reset role;
-- storage
insert into auth.users(id,email) values ('22222222-2222-2222-2222-222222222222','b@b.pe') on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
insert into storage.objects(bucket_id,name) values ('org-media', :'org' || '/logo/logo.png');
insert into storage.objects(bucket_id,name) values ('org-media', :'org' || '/productos/a.jpg');
select count(*) as own_visible from storage.objects;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',false);
select count(*) as other_visible from storage.objects;
\set ON_ERROR_STOP 0
insert into storage.objects(bucket_id,name) values ('org-media', :'org' || '/productos/hack.jpg');
insert into storage.objects(bucket_id,name) values ('org-media', 'no-uuid/x.jpg');
