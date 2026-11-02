-- SAFE, READ-ONLY audit for staging after load tests. Does NOT seed data.
-- 1) Idempotency table should have no missing invoice once transactions are committed.
select 'pending_requests' as metric, count(*) as count
from public.fast_checkout_requests where invoice_id is null;

-- 2) Links to another organization/user must be zero.
select 'cross_org_checkout_links' as metric, count(*) as count
from public.fast_checkout_requests r
join public.invoices i on i.id = r.invoice_id
where r.org_id <> i.org_id or r.user_id <> i.user_id;

-- 3) Products linked across organizations must be zero.
select 'cross_org_product_links' as metric, count(*) as count
from public.invoice_items it
join public.invoices i on it.invoice_id = i.id
join public.products p on p.id = it.product_id
where i.org_id <> p.org_id;

-- 4) For fast checkout, count invoices with no payment or over-/under-payments.
select 'incorrect_payment_totals' as metric, count(*) as count
from public.fast_checkout_requests r
join public.invoices i on i.id = r.invoice_id
left join lateral (select coalesce(sum(p.amount),0) as total
  from public.payments p where p.invoice_id = i.id) paid on true
where i.amt_total <> paid.total;

-- 5) Tracked stock must not be negative after concurrent cashier transactions.
select 'negative_stock_skus' as metric, count(*) as count
from public.products where stock is not null and stock < 0;

-- 6) Show RLS and key authorization structure in staging.
select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname='public' and tablename in ('fast_checkout_requests', 'invoice_items', 'products', 'payments', 'invoices')
order by tablename, policyname;

-- A PASS does not prove full RLS security. Also test with user B JWT attempting org A IDs.
