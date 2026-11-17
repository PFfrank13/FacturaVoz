-- Fix restrictive SELECT policies that previously passed a NULL feature key
-- because private.feature_for does not define clients, invoices or payments.
-- These were blocking INSERT ... RETURNING and POS checkout even for valid tenants.
-- Preserve original restrictive membership/license policies and role checks.
begin;
drop policy if exists hub_feature_read_clients on public.clients;
create policy hub_feature_read_clients on public.clients
  as restrictive for select to authenticated
  using (private.has_feature(org_id,'clientes'));

drop policy if exists hub_feature_read_invoices on public.invoices;
create policy hub_feature_read_invoices on public.invoices
  as restrictive for select to authenticated
  using (private.has_feature(org_id,'facturar'));

drop policy if exists hub_feature_read_payments on public.payments;
create policy hub_feature_read_payments on public.payments
  as restrictive for select to authenticated
  using (private.has_feature(org_id,'cobros'));
commit;
notify pgrst, 'reload schema';
