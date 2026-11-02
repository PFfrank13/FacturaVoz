-- FacturaVoz · v3.1 · Tiempo real en más pantallas
-- La app escucha cambios de la empresa activa (clientes, productos, gastos, recordatorios, tareas del Copiloto,
-- facturas recurrentes). Para eso las tablas deben estar en la publicación de Supabase Realtime.
-- Aditiva e idempotente: no cambia datos ni permisos (Realtime respeta las políticas RLS de cada tabla).
-- Ejecutar después de 20261118.
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['clients', 'products', 'expenses', 'service_reminders', 'agent_tasks', 'recurring_invoices'] loop
      if to_regclass('public.' || t) is not null
         and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
