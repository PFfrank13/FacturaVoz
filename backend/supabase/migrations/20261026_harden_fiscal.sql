-- Corrección de seguridad (ejecutar en Supabase → SQL Editor). Idempotente.
-- 1) Políticas abiertas a todo el mundo en tablas fiscales (cualquiera con la clave anon podía leer/escribir)
drop policy if exists "Permitir todo fiscal" on public.fiscal_documents;
drop policy if exists "Permitir todo notas" on public.fiscal_notes;

-- 2) La app solo LEE tablas fiscales; solo service_role (backend) escribe
revoke all on public.fiscal_documents, public.fiscal_notes, public.fiscal_companies from anon;
revoke all on public.fiscal_documents, public.fiscal_notes, public.fiscal_companies from authenticated;
grant select on public.fiscal_documents, public.fiscal_notes, public.fiscal_companies to authenticated;

-- 3) La API nunca necesita TRUNCATE/TRIGGER/REFERENCES
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
