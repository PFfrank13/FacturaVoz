\set ON_ERROR_STOP 1
-- v3.3: lo que consulta el Inicio por rol (role_home.dart) con un negocio grande: 10 000 comprobantes de hoy y del
-- mes, 2 000 movimientos de fiado, 1 000 productos. Mide day_summary, day_closings, credit_balances y productos.
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
insert into public.clients(user_id, org_id, name) select '11111111-1111-1111-1111-111111111111', :'org', 'Cliente ' || g from generate_series(1,500) g;
insert into public.invoices(id, user_id, org_id, client_id, number, issue_date, tax_rate, status, currency)
select gen_random_uuid(), '11111111-1111-1111-1111-111111111111', :'org', null, 'B-' || g, private.today_pe() - (g % 30), 18, 'paid', 'PEN' from generate_series(1,10000) g;
insert into public.invoice_items(user_id, invoice_id, description, quantity, unit_price, position)
select i.user_id, i.id, 'Item', 2, 15, 1 from public.invoices i where i.org_id = :'org';
insert into public.payments(org_id, invoice_id, user_id, amount, paid_on, method)
select i.org_id, i.id, i.user_id, 35.4, i.issue_date, case when random() < 0.6 then 'efectivo' else 'yape' end from public.invoices i where i.org_id = :'org';
insert into public.credit_ledger(org_id, client_id, kind, amount, user_id)
select :'org', c.id, case when g % 3 = 0 then 'abono' else 'cargo' end, 5 + g % 20, '11111111-1111-1111-1111-111111111111'
from (select id, row_number() over () rn from public.clients where org_id = :'org') c, generate_series(1,4) g;
insert into public.products(org_id, user_id, name, unit_price, unit, stock, reorder_point, active)
select :'org', '11111111-1111-1111-1111-111111111111', 'Producto ' || g, 3, 'NIU', g % 25, 5, true from generate_series(1,1000) g;
analyze;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
\timing on
select (public.day_summary(:'org', private.today_pe())->'sales'->>'sales_total') as ventas_hoy;
select count(*) from public.day_closings where org_id = :'org' and day = private.today_pe();
select count(*) as clientes_con_fiado from public.credit_balances(:'org') where balance > 0;
select count(*) as stock_bajo from (select id, name, unit_price, unit, active, stock, reorder_point, unit_cost, in_store from public.products where org_id = :'org' and active order by name limit 1000) p where stock <= coalesce(reorder_point, 0);
