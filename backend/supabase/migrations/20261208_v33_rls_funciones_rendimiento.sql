-- v3.3 · Rendimiento de RLS (Prompt Maestro §15). Las políticas hub_feature_read_* (20261125) llamaban a
-- private.has_feature(org_id, …) POR FILA; has_feature recorre todas las funciones del plan en cada llamada.
-- Medido en PostgreSQL 16 con 10 000 comprobantes, 2 000 movimientos de fiado y 500 clientes (tests/bench_v33_inicio_rol.sql):
-- day_summary ≈ 0,41–0,47 s y credit_balances ≈ 0,29–0,31 s antes de este cambio.
-- Ahora: un arreglo con las empresas del usuario que tienen la función, calculado UNA vez por consulta (initPlan).
-- Misma regla: las filas de empresas donde el usuario no es miembro ya las excluyen las políticas license_read_* (restrictivas).
-- Idempotente. Probar en staging antes de producción.
begin;

create or replace function private.my_feature_org_ids(p_key text)
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(m.org_id), '{}') from public.organization_members m
   where m.user_id = (select auth.uid()) and private.has_feature(m.org_id, p_key)
$$;
revoke all on function private.my_feature_org_ids(text) from public, anon;
grant execute on function private.my_feature_org_ids(text) to authenticated;

alter policy hub_feature_read_invoices on public.invoices using (org_id = any ((select private.my_feature_org_ids('facturar'))::uuid[]));
alter policy hub_feature_read_payments on public.payments using (org_id = any ((select private.my_feature_org_ids('cobros'))::uuid[]));
alter policy hub_feature_read_clients on public.clients using (org_id = any ((select private.my_feature_org_ids('clientes'))::uuid[]));
alter policy hub_feature_read_recurring_invoices on public.recurring_invoices using (org_id = any ((select private.my_feature_org_ids('recurrentes'))::uuid[]));
alter policy hub_feature_read_job_materials on public.job_materials using (org_id = any ((select private.my_feature_org_ids('trabajos'))::uuid[]));
alter policy hub_feature_read_job_milestones on public.job_milestones using (org_id = any ((select private.my_feature_org_ids('trabajos'))::uuid[]));
alter policy hub_feature_read_credit_ledger on public.credit_ledger using (org_id = any ((select private.my_feature_org_ids('fiados'))::uuid[]));
alter policy hub_feature_read_cash_movements on public.cash_movements using (org_id = any ((select private.my_feature_org_ids('caja'))::uuid[]));
alter policy hub_feature_read_day_closings on public.day_closings using (org_id = any ((select private.my_feature_org_ids('caja'))::uuid[]));
alter policy hub_feature_read_promotions on public.promotions using (org_id = any ((select private.my_feature_org_ids('precios'))::uuid[]));
alter policy hub_feature_read_coupons on public.coupons using (org_id = any ((select private.my_feature_org_ids('precios'))::uuid[]));
alter policy hub_feature_read_quotes on public.quotes using (case when source = 'store' then (org_id = any ((select private.my_feature_org_ids('tienda'))::uuid[])) else (org_id = any ((select private.my_feature_org_ids('cotizaciones'))::uuid[])) end);
alter policy hub_feature_read_jobs on public.jobs using (case when kind = 'cita' then (org_id = any ((select private.my_feature_org_ids('agenda'))::uuid[])) else (org_id = any ((select private.my_feature_org_ids('trabajos'))::uuid[])) end);
commit;
