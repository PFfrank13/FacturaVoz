-- FacturaVoz v3.2: indexes for new Plan Básico retail relations.
-- Additive only. The new tables are empty on initial rollout.
begin;
create index if not exists idx_fast_checkout_requests_user_id
  on public.fast_checkout_requests(user_id);
create index if not exists idx_retail_inventory_events_product_id
  on public.retail_inventory_events(product_id);
create index if not exists idx_retail_inventory_events_user_id
  on public.retail_inventory_events(user_id);
create index if not exists idx_retail_purchase_settlements_expense_id
  on public.retail_purchase_settlements(expense_id);
create index if not exists idx_retail_purchase_settlements_user_id
  on public.retail_purchase_settlements(user_id);
create index if not exists idx_retail_receipt_items_product_id
  on public.retail_receipt_items(product_id);
create index if not exists idx_retail_receipts_user_id
  on public.retail_receipts(user_id);
create index if not exists idx_retail_sale_stock_events_invoice_id
  on public.retail_sale_stock_events(invoice_id);
create index if not exists idx_retail_sale_stock_events_product_id
  on public.retail_sale_stock_events(product_id);
commit;
