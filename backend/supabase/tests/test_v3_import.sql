\set ON_ERROR_STOP 1
-- Prueba A1/A2: importa el libro sintético de 1500 comprobantes por bloques, compara con lo esperado,
-- repite (idempotente), verifica la regla única de ventas, seguridad y "deshacer".
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe') on conflict do nothing;
insert into auth.users(id,email) values ('22222222-2222-2222-2222-222222222222','otro@b.pe') on conflict do nothing;
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
drop table if exists wbp;
create table wbp(j jsonb);
\copy wbp(j) from '/tmp/pg/wb_payload.json' with (format csv, quote e'\x01', delimiter e'\x02')
grant select on wbp to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.wb_import_begin(:'org', 'migracion_1500_sintetico.xlsx', '{"documents":1500}'::jsonb) as job \gset
select public.wb_import_clients(:'job', (select j->'clients' from wbp)) as clients_res;
select public.wb_import_products(:'job', (select j->'products' from wbp)) as products_res;
\timing on
select sum((public.wb_import_docs(:'job', (select jsonb_agg(e) from jsonb_array_elements((select j->'docs' from wbp)) with ordinality x(e,n) where n > g*300 and n <= (g+1)*300))->>'imported')::int) as imported
from generate_series(0,4) g;
\timing off
select public.wb_import_finish(:'job') as result \gset
select :'result'::jsonb - 'net' - 'collected' as counts;
select (:'result'::jsonb->'net') as net, (:'result'::jsonb->'collected') as collected;

-- A2: la MISMA cifra en Inicio (sales_summary), gráficos (sales_series) y Copiloto (business_snapshot)
select (public.sales_summary(:'org', '2000-01-01', '2100-01-01', 'PEN')->>'sales_total')::numeric as summary_pen_all,
       (select sum(total) from public.sales_series(:'org', '2000-01-01', '2100-01-01', 'PEN', 'month')) as series_pen_all;
select (public.sales_summary(:'org', date_trunc('month', private.today_pe())::date, '2100-01-01', 'PEN')->>'sales_total')::numeric
       = (public.business_snapshot(:'org')->'sales_this_month'->>'total')::numeric as home_equals_copilot,
       (public.sales_summary(:'org', date_trunc('month', private.today_pe())::date, '2100-01-01', 'PEN')->>'sales_total')::numeric as this_month;
select (public.business_snapshot(:'org')->>'receivable_total')::numeric as receivable_pen;
select public.sales_summary(:'org', '2000-01-01', '2100-01-01', 'PEN') - 'rule' as summary;

-- Idempotente: el mismo archivo otra vez no duplica nada
select public.wb_import_begin(:'org', 'otra vez.xlsx', '{}'::jsonb) as job2 \gset
select public.wb_import_clients(:'job2', (select j->'clients' from wbp)) as clients_again;
select sum((public.wb_import_docs(:'job2', (select jsonb_agg(e) from jsonb_array_elements((select j->'docs' from wbp)) with ordinality x(e,n) where n > g*300 and n <= (g+1)*300))->>'duplicates')::int) as duplicates
from generate_series(0,4) g;
select (public.wb_import_finish(:'job2'))->>'documents' as second_import_docs;

-- Seguridad: el cliente no puede falsear totales ni marcar anulados
select id as one_inv from public.invoices where import_job_id = :'job' and voided_at is null limit 1 \gset
update public.invoices set amt_total = 1, voided_at = now(), totals_locked = false where id = :'one_inv';
select amt_total > 1 as total_kept, voided_at is null as not_voided, totals_locked from public.invoices where id = :'one_inv';
insert into public.invoices(user_id, org_id, number, issue_date, tax_rate, status, currency, amt_total, totals_locked, doc_kind)
values (auth.uid(), :'org', 'X-1', current_date, 18, 'draft', 'PEN', 999, true, 'nota_credito') returning amt_total, totals_locked, doc_kind;
insert into public.invoice_items(user_id, invoice_id, description, quantity, unit_price)
select auth.uid(), id, 'Prueba', 2, 50 from public.invoices where number='X-1';
select amt_base, amt_tax, amt_total from public.invoices where number='X-1';

-- Otra empresa no ve ni toca la importación
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',false);
select count(*) as other_sees_jobs from public.wb_imports;
do $$ begin
  perform public.wb_import_undo((select id from public.wb_imports limit 1));
  raise notice 'MAL: pudo deshacer';
exception when others then raise notice 'OK bloqueado: %', sqlerrm; end $$;
select set_config('x.job', :'job', false);
do $$ begin perform public.wb_import_docs(current_setting('x.job')::uuid, '[]'); exception when others then raise notice 'OK docs bloqueado: %', sqlerrm; end $$;

-- Deshacer (dueño)
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
select public.wb_import_undo(:'job') as undo;
select count(*) as invoices_left from public.invoices where import_job_id = :'job';
select count(*) as clients_left from public.clients where org_id = :'org';
select count(*) as trash_rows from public.trash where org_id = :'org';
reset role;
drop table wbp;
