\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','a@a.pe'),('22222222-2222-2222-2222-222222222222','b@b.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
select org_id as org2 from public.organization_members where user_id='22222222-2222-2222-2222-222222222222' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
insert into public.org_settings(org_id,business_type,job_statuses) values (:'org','servicios_tecnicos','[{"key":"nuevo","label":"Interesado"},{"key":"instalado","label":"Instalado","done":true}]');
insert into public.clients(user_id,org_id,name,phone,tags,birthday) values (auth.uid(),:'org','Ana WiFi','987654321','{vip}', (now() at time zone 'America/Lima')::date - interval '30 years') returning id as cli \gset
insert into public.products(org_id,user_id,name,unit_price,unit,stock) values (:'org',auth.uid(),'Router',100,'NIU',10) returning id as prod \gset
insert into public.jobs(org_id,client_id,title,kind,scheduled_at,assigned_to) values (:'org',:'cli','Instalación WiFi','instalacion', now() + interval '1 day', auth.uid()) returning id as job \gset
insert into public.job_materials(job_id,org_id,product_id,description,quantity) values (:'job',:'org',:'prod','Router',2);
update public.jobs set status='instalado' where id=:'job';
select status, done_at is not null as done from public.jobs where id=:'job';
select count(*) as events from public.job_events where job_id=:'job';
select public.job_consume_materials(:'job');
select public.job_consume_materials(:'job') as again;
select stock from public.products where id=:'prod';
insert into public.client_notes(org_id,client_id,body) values (:'org',:'cli','Llamé para ofrecer upgrade');
select last_contact_at is not null as touched from public.clients where id=:'cli';
select jsonb_array_length(public.daily_alerts(:'org')) as alerts, public.daily_alerts(:'org');
\set ON_ERROR_STOP 0
-- cross org: client of org in a job of org2 (user 2)
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',false);
insert into public.jobs(org_id,client_id,title) values (:'org2',:'cli','hack');
select count(*) as seen_by_other from public.jobs;
insert into public.org_settings(org_id) values (:'org');
