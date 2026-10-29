\set ON_ERROR_STOP 1
-- A3: 10 000 comprobantes (≈ 25 000 líneas, 6 000 cobros) en una empresa. Mide antes/después.
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
select set_config('facturavoz.bypass_license','on',false);
insert into public.clients(user_id, org_id, name) select '11111111-1111-1111-1111-111111111111', :'org', 'Cliente ' || g from generate_series(1,500) g;
insert into public.invoices(id, user_id, org_id, client_id, number, issue_date, tax_rate, status, currency)
select gen_random_uuid(), '11111111-1111-1111-1111-111111111111', :'org',
       (select id from public.clients where org_id = :'org' order by id offset (g % 500) limit 1),
       'B-' || g, private.today_pe() - (g % 540), 18, case when g % 10 < 6 then 'paid' else 'sent' end, 'PEN'
from generate_series(1,10000) g;
insert into public.invoice_items(user_id, invoice_id, description, quantity, unit_price, position)
select i.user_id, i.id, 'Item ' || k, 1 + (k % 3), 10 + (k * 7 % 90), k
from public.invoices i, generate_series(1, 1 + (abs(hashtext(i.number)) % 4)) k where i.org_id = :'org';
insert into public.payments(org_id, invoice_id, user_id, amount, paid_on, method)
select i.org_id, i.id, i.user_id, 10, i.issue_date, 'efectivo' from public.invoices i where i.org_id = :'org' and i.status = 'paid';
analyze;
select count(*) as invoices, (select count(*) from public.invoice_items) as items from public.invoices;

set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
\timing on
\echo '--- ANTES: fórmula anterior (suma de líneas por cada comprobante en cada consulta) ---'
select count(*), sum((select sum(round(round(round(it.quantity, 2) * round(it.unit_price, 2), 2) * 1.18, 2)) from public.invoice_items it where it.invoice_id = i.id))
from public.invoices i where i.org_id = :'org' and i.issue_date >= date_trunc('month', private.today_pe()) and i.status <> 'draft';
select count(*), sum((select sum(round(round(round(it.quantity, 2) * round(it.unit_price, 2), 2) * 1.18, 2)) from public.invoice_items it where it.invoice_id = i.id))
from public.invoices i where i.org_id = :'org' and i.status <> 'draft';
\echo '--- DESPUÉS: sales_summary mes / año completo / business_snapshot / página de 50 ---'
select public.sales_summary(:'org', date_trunc('month', private.today_pe())::date, '2100-01-01', 'PEN')->>'sales_total' as month_total;
select public.sales_summary(:'org', '2000-01-01', '2100-01-01', 'PEN')->>'sales_total' as all_total;
select length(public.business_snapshot(:'org')::text) as snapshot_bytes;
select count(*) from public.invoice_page(:'org', 50);
select count(*) from public.sales_series(:'org', private.today_pe() - 365, private.today_pe() + 1, 'PEN', 'month');
\timing off
reset role;
