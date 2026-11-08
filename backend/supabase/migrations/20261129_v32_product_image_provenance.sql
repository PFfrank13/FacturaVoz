-- FacturaVoz Plan Básico: reversible/additive image provenance.
-- Requires the existing products table. No data, stock, licenses or roles change.
begin;
alter table public.products
  add column if not exists image_original_path text,
  add column if not exists image_clean_path text;
-- A nullable path is never treated as proof of AI processing.
comment on column public.products.image_original_path is
  'Optional private Storage path to the unmodified product photo.';
comment on column public.products.image_clean_path is
  'Optional private Storage path to the accepted PNG with removed background.';
grant update(image_original_path, image_clean_path)
  on public.products to authenticated;
commit;
notify pgrst, 'reload schema';
