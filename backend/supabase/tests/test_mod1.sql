\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.invite_member(:'org','caja@a.pe','cajero',false,'Lucía');
insert into public.org_settings(org_id, loyalty_rate) values (:'org', 1);
insert into public.clients(user_id,org_id,name,phone) values (auth.uid(),:'org','Doña Rosa','987654321') returning id as cli \gset
insert into public.products(org_id,user_id,name,unit_price,unit) values (:'org',auth.uid(),'Arroz 5kg',30,'NIU');
-- fiados
insert into public.credit_ledger(org_id,client_id,kind,amount,description) values (:'org',:'cli','cargo',50,'Arroz y aceite'),(:'org',:'cli','abono',20,'A cuenta');
select client_name, balance from public.credit_balances(:'org');
-- caja
insert into public.cash_movements(org_id,kind,amount) values (:'org','apertura',100);
select invoice_id as inv from public.create_invoice('Doña Rosa', null, 18, 'PEN', null, null, '[{"description":"Arroz 5kg","quantity":1,"unit_price":30}]'::jsonb, :'org') \gset
update public.invoices set status='sent' where id=:'inv';
insert into public.payments(org_id,invoice_id,user_id,amount,method) values (:'org',:'inv',auth.uid(),35.40,'efectivo') returning id as pay \gset
select public.day_summary(:'org', (now() at time zone 'America/Lima')::date) ->> 'expected_cash' as expected;
select points from public.loyalty_balances(:'org');
-- pin
select public.set_admin_pin(:'org','1234');
reset role;
insert into auth.users(id,email) values ('44444444-4444-4444-4444-444444444444','caja@a.pe');
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',false);
-- cajero vende con descuento alto
select invoice_id as inv2 from public.create_invoice('Juan', null, 18, 'PEN', null, null, '[{"description":"arroz 5kg","quantity":1,"unit_price":10}]'::jsonb, :'org') \gset
delete from public.payments where id=:'pay';
select count(*) as pay_still_there from public.payments where id=:'pay';
select public.verify_admin_pin(:'org','9999') as wrong;
select public.verify_admin_pin(:'org','1234') as right;
delete from public.payments where id=:'pay';
select count(*) as pay_deleted from public.payments where id=:'pay';
insert into public.day_closings(org_id, day, summary, expected_cash, counted_cash) values (:'org', (now() at time zone 'America/Lima')::date, '{}', 135.40, 120);
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
delete from public.payments where id=:'pay';
select kind, title from public.owner_alerts order by created_at;
select id as tid from public.trash where table_name='payments' \gset
select public.restore_trash(:'tid');
select count(*) as restored from public.payments where id=:'pay';
select points from public.loyalty_balances(:'org');
select public.audit_verify(:'org') as broken_row;
select count(*) as audit_rows from public.audit_log;
reset role;
update public.audit_log set data='{"hack":1}' where id = 3;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.audit_verify(:'org') as broken_after_tamper;
select * from public.seller_ranking(:'org', '2026-01-01', '2027-01-01');
