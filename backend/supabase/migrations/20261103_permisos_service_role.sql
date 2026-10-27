-- FacturaVoz · Migración 12 · Permisos del servidor (service_role)
-- Corrige el error 42501 "permission denied for table …" en /api/cron/collections, la tienda, los pagos y el webhook.
--
-- Por qué pasa: los proyectos nuevos de Supabase ya NO dan acceso automático a las tablas nuevas; cada permiso debe
-- declararse. Las migraciones anteriores los declaraban para la app (authenticated) pero no para el servidor (service_role).
-- service_role es la clave secreta que vive SOLO en Vercel (SUPABASE_SERVICE_ROLE_KEY); nunca llega a la app ni a anon.
--
-- Idempotente: se puede ejecutar las veces que quieras. Ejecutar después de 20261101 y 20261102.
begin;

-- Esquemas
grant usage on schema public to service_role;
grant usage on schema private to service_role;

-- Todas las tablas, secuencias y funciones actuales del esquema public (igual que un proyecto clásico de Supabase)
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Utilidades del esquema private que usan las funciones del servidor
grant execute on function
  private.invoice_total(uuid),
  private.invoice_paid(uuid),
  private.today_pe(),
  private.new_token(),
  private.settle_invoice(uuid),
  private.next_month_day(date, integer)
to service_role;

-- Y para lo que se cree en el futuro (tablas, secuencias y funciones nuevas en public)
alter default privileges in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

commit;

-- Que la API de Supabase vea los permisos al instante.
notify pgrst, 'reload schema';
