-- Execute only against isolated STAGING after migrations 26, 27 and 28.
-- Read-only checks. Zero is expected for all "failures" columns.

-- 1. A delayed payment must reconcile with exactly one receipt and expense.
select 'settlement_receipt_mismatch' as metric, count(*) as failures
from public.retail_purchase_settlements s
left join public.retail_receipts r on r.id = s.receipt_id
left join public.expenses e on e.id = s.expense_id
where r.id is null or r.org_id <> s.org_id
   or r.payment_method <> s.method or r.expense_id <> s.expense_id
   or s.currency <> r.currency or s.paid_cents <> r.total_cents
   or e.id is null or e.org_id <> s.org_id
   or round(e.total * 100)::bigint <> s.paid_cents;

-- 2. Every PAID cash receipt created upfront has one matching cash movement.
select 'immediate_cash_purchase_mismatch' as metric, count(*) as failures
from public.retail_receipts r
left join public.cash_movements c on c.id = r.cash_move_id
where (r.payment_method = 'efectivo'
       and not exists (select 1 from public.retail_purchase_settlements s
                       where s.receipt_id = r.id)
       and (c.id is null or c.org_id <> r.org_id or c.kind <> 'egreso'
            or round(c.amount * 100)::bigint <> r.total_cents))
   or (r.payment_method <> 'efectivo' and r.cash_move_id is not null);

-- 3. Every deferred cash payment matches its cash entry. Noncash must not
-- touch a physical cash movement.
select 'deferred_cash_purchase_mismatch' as metric, count(*) as failures
from public.retail_purchase_settlements s
left join public.cash_movements c on c.id = s.cash_move_id
where (s.method = 'efectivo'
       and (c.id is null or c.org_id <> s.org_id or c.kind <> 'egreso'
            or round(c.amount * 100)::bigint <> s.paid_cents))
   or (s.method <> 'efectivo' and s.cash_move_id is not null);

-- 4. Credit purchases cannot appear paid without a settlement.
select 'credit_purchase_state_mismatch' as metric, count(*) as failures
from public.retail_receipts r
where (r.payment_method = 'pendiente'
       and (r.expense_id is not null or r.cash_move_id is not null))
   or (r.payment_method not in ('pendiente', 'efectivo')
       and r.cash_move_id is not null);

-- 5. Inventory sale events correspond to the right company, invoice,
-- product and line. Quantity must equal the immutable invoice item.
select 'sale_event_mismatch' as metric, count(*) as failures
from public.retail_sale_stock_events e
left join public.invoice_items it on it.id = e.invoice_item_id
left join public.invoices inv on inv.id = e.invoice_id
left join public.products p on p.id = e.product_id
where it.id is null or inv.id is null or p.id is null
   or it.invoice_id <> e.invoice_id or inv.org_id <> e.org_id
   or p.org_id <> e.org_id
   or it.quantity <> -e.quantity_delta
   or e.stock_after <> e.stock_before + e.quantity_delta;

-- 6. Negative stock is visible; buyer can continue trading while owner
-- inspects products requiring a purchase/regularization.
select 'negative_stock_products' as metric, count(*) as products_to_regularize
from public.products p
join public.org_settings s on s.org_id = p.org_id
where s.business_type in ('bodega','mayorista')
  and p.stock < 0;

-- 7. Ensure RLS protects every newly exposed financial record and view.
select relname as relation, relrowsecurity as rls_enabled
from pg_class
where oid in ('public.retail_receipts'::regclass,
              'public.retail_receipt_items'::regclass,
              'public.retail_inventory_events'::regclass,
              'public.retail_sale_stock_events'::regclass,
              'public.retail_purchase_settlements'::regclass)
order by relname;

-- E2E acceptance NOT supplied by these queries: two organization identities,
-- concurrent clients paying same receipt, independent request IDs with same
-- receipt, disconnection after COMMIT, stock at zero, fiscal note reversals,
-- and limited-license denies MUST be exercised in staging.
