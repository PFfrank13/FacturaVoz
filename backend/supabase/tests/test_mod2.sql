\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select invoice_id as inv from public.create_invoice('Cliente Portal', '20100070970', 18, 'PEN', null, null, '[{"description":"X","quantity":2,"unit_price":50}]'::jsonb, :'org') \gset
update public.invoices set status='sent' where id=:'inv';
select public.invoice_portal_link(:'inv') as tok \gset
select public.survey_link(:'inv') as stok \gset
insert into public.org_store(org_id, slug, enabled, booking) values (:'org','mi-barberia',true,true);
select public.create_api_key(:'org','Shopify',null) as key \gset
insert into public.org_webhooks(org_id,url) values (:'org','https://example.com/hook');
insert into public.clients(user_id,org_id,name) values (auth.uid(),:'org','Obra SAC') returning id as cli \gset
insert into public.jobs(org_id,client_id,title,kind) values (:'org',:'cli','Ampliación','obra') returning id as job \gset
insert into public.job_milestones(job_id,org_id,title,amount) values (:'job',:'org','Adelanto 50%',1180) returning id as ms \gset
select public.milestone_invoice(:'ms') is not null as invoiced;
select status from public.job_milestones where id=:'ms';
reset role;
set role service_role;
select (public.portal_get(:'tok') -> 'history' -> 0 ->> 'total') as portal_total;
select public.survey_answer(:'stok', 2, 'Demoró');
select * from public.store_book('mi-barberia','Carlos','987654321','Corte', now() + interval '1 day', null);
select org_id = :'org' as auth_ok from public.api_key_auth(encode(sha256(convert_to(:'key','UTF8')),'hex'), 'orders:write');
select quote_number from public.api_create_order(:'org','Tienda Shopify','', '987000111', 'Pedido #1001', '[{"description":"Polo","quantity":2,"unit_price":30}]');
select event, count(*) from public.webhook_outbox group by event order by 1;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select string_agg(kind, ',' order by kind) as alerts from public.owner_alerts;
select jsonb_array_length(public.daily_alerts(:'org')) as daily;
