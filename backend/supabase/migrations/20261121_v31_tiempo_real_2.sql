-- FacturaVoz · v3.1 · Tiempo real (parte 2): equipo, papelera, encuestas, promociones, cupones y puntos.
-- Aditiva e idempotente; Realtime respeta las políticas RLS de cada tabla. Ejecutar después de 20261120.
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['org_invites', 'trash', 'surveys', 'promotions', 'coupons', 'loyalty_ledger'] loop
      if to_regclass('public.' || t) is not null
         and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
