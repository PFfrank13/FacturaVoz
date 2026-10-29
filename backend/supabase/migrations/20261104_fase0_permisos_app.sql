-- FacturaVoz · Migración 13 · FASE 0 (urgente): permisos de la app + definición única de "venta"
--
-- 1) ERROR "Sin permiso para esta operación (42501)" AL IMPORTAR
--    Causa: la importación empieza creando una fila en public.import_jobs desde la app (rol authenticated).
--    La migración 20261031 creó la tabla y sus políticas RLS, pero NO le dio a la app el permiso de tabla
--    (GRANT). En los proyectos nuevos de Supabase las tablas ya no reciben permisos automáticos, así que
--    Postgres responde "permission denied for table import_jobs" (código 42501) ANTES de mirar las políticas.
--    No era un problema de Storage: la importación no usa Storage (las filas viajan por RPC en bloques).
--    Corrección: permisos explícitos y mínimos para la app en todas las tablas que lo necesitaban.
--    RLS sigue decidiendo QUÉ filas ve cada usuario; el GRANT solo habilita el tipo de operación.
--
-- 2) "Facturado este mes" (Inicio) ≠ "Ventas" (Negocio)
--    Inicio sumaba también BORRADORES (y con IGV); Negocio excluía borradores (y mostraba sin IGV).
--    Desde ahora una VENTA es: comprobante emitido (estado 'sent' o 'paid'), no rechazado por SUNAT y no
--    anulado con nota de crédito aceptada. Los borradores se muestran aparte. Ambas pantallas usan sales_summary().
--
-- Idempotente y aditiva (sin DROP). Ejecutar después de 20261103.
begin;

-- ───────────── 1) Permisos de tabla para la app (authenticated) ─────────────
grant usage on schema public to authenticated;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.clients to authenticated;
grant select, insert, update, delete on public.invoices to authenticated;
grant select, insert, update, delete on public.invoice_items to authenticated;
grant select, insert on public.api_usage to authenticated;
-- Importación: crear el trabajo y ver su progreso (en vivo). Actualizar/borrar sigue prohibido (solo funciones).
grant select, insert on public.import_jobs to authenticated;
-- Columnas identidad (api_usage.id) necesitan la secuencia
grant usage, select on all sequences in schema public to authenticated;

-- El rol anónimo sigue sin acceso directo a nada (la tienda/pagos públicos van por el servidor).
revoke all on public.import_jobs, public.import_rows from anon;

-- ───────────── 2) Definición única de venta ─────────────
-- ¿La factura está anulada con una nota de crédito aceptada por SUNAT?
create or replace function private.invoice_voided(p_invoice uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.fiscal_notes n where n.invoice_id = p_invoice and n.status = 'accepted');
$$;
revoke execute on function private.invoice_voided(uuid) from public, anon;
grant execute on function private.invoice_voided(uuid) to authenticated, service_role;

-- Resumen de ventas de un periodo [p_from, p_to) en una moneda. Usa RLS del usuario (SECURITY INVOKER).
create or replace function public.sales_summary(p_org uuid, p_from date, p_to date, p_currency text default 'PEN')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with inv as (
    select i.id, i.status,
           coalesce(fd.status, '') as fiscal,
           coalesce((select sum(round(round(it.quantity, 2) * round(it.unit_price, 2), 2)) from public.invoice_items it where it.invoice_id = i.id), 0) as base,
           coalesce((select sum(round(round(round(it.quantity, 2) * round(it.unit_price, 2), 2) * i.tax_rate / 100, 2)) from public.invoice_items it where it.invoice_id = i.id), 0) as tax
    from public.invoices i
    left join public.fiscal_documents fd on fd.invoice_id = i.id
    where i.org_id = p_org and i.issue_date >= p_from and i.issue_date < p_to and i.currency = p_currency
  ), cls as (
    select inv.*,
           (inv.status in ('sent', 'paid') and inv.fiscal <> 'rejected' and not private.invoice_voided(inv.id)) as is_sale
    from inv
  )
  select jsonb_build_object(
    'currency', p_currency,
    'sales_count', count(*) filter (where is_sale),
    'sales_base', coalesce(sum(base) filter (where is_sale), 0),
    'sales_tax', coalesce(sum(tax) filter (where is_sale), 0),
    'sales_total', coalesce(sum(base + tax) filter (where is_sale), 0),
    'drafts_count', count(*) filter (where status = 'draft'),
    'drafts_total', coalesce(sum(base + tax) filter (where status = 'draft'), 0),
    'rejected_count', count(*) filter (where fiscal = 'rejected')
  )
  from cls;
$$;
revoke execute on function public.sales_summary(uuid, date, date, text) from public, anon;
grant execute on function public.sales_summary(uuid, date, date, text) to authenticated;

commit;

notify pgrst, 'reload schema';
