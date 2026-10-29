\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.invite_member(:'org','Tecnico@a.pe','tecnico',false,'Pedro');
select public.invite_member(:'org','caja@a.pe','cajero',false,'Lucía');
insert into public.clients(user_id,org_id,name) values (auth.uid(),:'org','Cliente A') returning id as ca \gset
insert into public.clients(user_id,org_id,name) values (auth.uid(),:'org','Cliente B') returning id as cb \gset
insert into public.expenses(org_id,user_id,category,description,total) values (:'org',auth.uid(),'otros','Luz',100);
select invoice_id as inv from public.create_invoice('Cliente B', null, 18, 'PEN', null, null, '[{"description":"X","quantity":1,"unit_price":10}]'::jsonb, :'org') \gset
reset role;
insert into auth.users(id,email) values ('33333333-3333-3333-3333-333333333333','tecnico@a.pe'),('44444444-4444-4444-4444-444444444444','caja@a.pe');
select count(*) as orgs_of_tech from public.organization_members where user_id='33333333-3333-3333-3333-333333333333';
select count(*) as own_orgs_created from public.organizations where created_by in ('33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444');
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
insert into public.jobs(org_id,client_id,title,assigned_to) values (:'org',:'ca','Instalar','33333333-3333-3333-3333-333333333333');
insert into public.jobs(org_id,client_id,title) values (:'org',:'cb','Otro trabajo');
-- técnico
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',false);
select public.my_access(:'org') ->> 'role' as tech_role;
select count(*) as tech_jobs from public.jobs;
select string_agg(name, ',') as tech_clients from public.clients;
select count(*) as tech_invoices from public.invoices;
select count(*) as tech_expenses from public.expenses;
-- cajero
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',false);
select public.my_access(:'org') -> 'can' as cajero_can;
select count(*) as caja_invoices from public.invoices;
select count(*) as caja_expenses from public.expenses;
select count(*) as caja_jobs from public.jobs;
\set ON_ERROR_STOP 0
insert into public.expenses(org_id,user_id,category,description,total) values (:'org',auth.uid(),'otros','Robo',100);
insert into public.products(org_id,user_id,name,unit_price,unit) values (:'org',auth.uid(),'P',1,'NIU');
select public.invite_member(:'org','x@a.pe','cajero',false,null);
-- dueño cambia a cajero → finanzas
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.set_member_role(:'org','44444444-4444-4444-4444-444444444444','finanzas',false,5,1000,'Lucía F');
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',false);
select count(*) as finanzas_expenses from public.expenses;
select role, staff_role, display_name from public.team_members(:'org');
