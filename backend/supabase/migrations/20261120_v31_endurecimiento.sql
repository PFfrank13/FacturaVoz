-- FacturaVoz · v3.1 · Endurecimiento tras revisión de producción (asesores de Supabase)
-- 1) La función auxiliar rls_auto_enable() no debe poder llamarse desde la API (anon / authenticated).
-- 2) Índices en claves foráneas que no tenían uno (regla: índice en cada FK).
-- Aditiva e idempotente. Ejecutar después de 20261119.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;

create index if not exists idx_client_assets_created_by on public.client_assets (created_by);
create index if not exists idx_document_series_user on public.document_series (user_id);
create index if not exists idx_fiscal_companies_user on public.fiscal_companies (user_id);
create index if not exists idx_organizations_created_by on public.organizations (created_by);
