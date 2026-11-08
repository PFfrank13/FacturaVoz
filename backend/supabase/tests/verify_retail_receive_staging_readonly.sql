-- Run only in a STAGING database after deploying the receipt migration.
-- All result counts below MUST be zero unless the statement is a descriptive metric.
-- Read-only; does not modify live orders, users, licenses or inventory.

-- 1. A committed receipt must have a completed amount.
select 'pending_or_zero_receipts' as metric, count(*) as failures
from public.retail_receipts
where total_cents <= 0;

-- 2. Every received SKU and inventory movement must match its receipt org.
select 'cross_tenant_receipt_items' as metric, count(*) as failures
from public.retail_receipt_items ri
join public.retail_receipts r on r.id = ri.receipt_id
join public.products p on p.id = ri.product_id
where ri.org_id <> r.org_id or ri.org_id <> p.org_id;

-- 3. Each line must reconcile with the corresponding append-only receipt event.
select 'receipt_event_mismatch' as metric, count(*) as failures
from public.retail_receipt_items ri
left join public.retail_inventory_events e
  on e.receipt_id = ri.receipt_id and e.product_id = ri.product_id
where e.id is null or e.org_id <> ri.org_id
   or e.quantity_delta <> ri.quantity
   or e.stock_before <> ri.stock_before or e.stock_after <> ri.stock_after;

-- 4. Total amount equals the sum of line costs in integer cents.
select 'receipt_amount_mismatch' as metric, count(*) as failures
from public.retail_receipts r
left join lateral (
  select coalesce(sum(i.line_total_cents),0) as sum_cents
  from public.retail_receipt_items i where i.receipt_id = r.id
) t on true
where r.total_cents <> t.sum_cents;

-- 5. Paid purchases must have one matching expense, unpaid purchases none.
select 'expense_mismatch' as metric, count(*) as failures
from public.retail_receipts r
left join public.expenses e on e.id = r.expense_id
where (r.payment_method = 'pendiente' and r.expense_id is not null)
   or (r.payment_method <> 'pendiente' and
      (e.id is null or e.org_id <> r.org_id
       or round(e.total * 100)::bigint <> r.total_cents));

-- 6. Cash purchases must have one matching cash outflow, by immutable receipt reference.
-- This diagnostic requires manual reconciliation of historical cash movement notes;
-- amounts alone cannot prove one-to-one causality without cash_move receipt FK.
select 'cash_purchase_receipts_to_review' as metric, count(*) as receipts
from public.retail_receipts where payment_method = 'efectivo';

-- 7. At minimum tables must have RLS on and only authenticated SELECT grants.
select relname, relrowsecurity
from pg_class
where oid in ('public.retail_receipts'::regclass,
              'public.retail_receipt_items'::regclass,
              'public.retail_inventory_events'::regclass)
order by relname;

-- 8. Check the RPC and scope with two real STAGING users: owner A, user B from another
-- org. B must fail any org A request and cannot read org A receipts, even with UUID.
-- Check two concurrent attempts with the same (org_id, request_id), and with different
-- requests for the same SKU. A PASS here alone is NOT a security certification.
