-- v3.3: cobros, abonos de fiado y movimientos de caja se registran UNA vez aunque la app reintente con el mismo id.
-- Las 3 líneas con ERROR duplicate key son el resultado esperado (el reintento choca con la clave primaria).
\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe');
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select invoice_id as inv from public.create_invoice('Cliente', null, 18, 'PEN', null, null, '[{"description":"X","quantity":1,"unit_price":100}]'::jsonb, :'org') \gset
update public.invoices set status='sent' where id=:'inv';
insert into public.payments(id,org_id,invoice_id,user_id,amount,method) values ('aaaaaaaa-0000-4000-8000-000000000001',:'org',:'inv',auth.uid(),40,'efectivo');
\set ON_ERROR_STOP 0
-- reintento con el MISMO id (la app lo toma como "ya registrado")
insert into public.payments(id,org_id,invoice_id,user_id,amount,method) values ('aaaaaaaa-0000-4000-8000-000000000001',:'org',:'inv',auth.uid(),40,'efectivo');
\set ON_ERROR_STOP 1
select count(*) as cobros, sum(amount) as total from public.payments where invoice_id=:'inv';
insert into public.credit_ledger(id,org_id,client_id,kind,amount,user_id) select 'bbbbbbbb-0000-4000-8000-000000000001',:'org',c.id,'cargo',10,auth.uid() from public.clients c limit 1;
\set ON_ERROR_STOP 0
insert into public.credit_ledger(id,org_id,client_id,kind,amount,user_id) select 'bbbbbbbb-0000-4000-8000-000000000001',:'org',c.id,'cargo',10,auth.uid() from public.clients c limit 1;
insert into public.cash_movements(id,org_id,kind,amount,user_id) values ('cccccccc-0000-4000-8000-000000000001',:'org','ingreso',5,auth.uid());
insert into public.cash_movements(id,org_id,kind,amount,user_id) values ('cccccccc-0000-4000-8000-000000000001',:'org','ingreso',5,auth.uid());
\set ON_ERROR_STOP 1
select (select count(*) from public.credit_ledger) as fiados, (select count(*) from public.cash_movements) as caja;
