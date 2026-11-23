-- v3.8b · Impuesto al consumo de bolsas plásticas (ICBPER, S/ 0.50 por bolsa desde 2023; Ley 30884).
-- docs/INVESTIGACION_RETAIL.md, fila 13. Solo AÑADE una marca al producto: «es bolsa plástica».
-- El comprobante electrónico separa del precio de la bolsa el ICBPER (código 7152) sin cambiar el total cobrado.
begin;
alter table public.products add column if not exists icbper boolean not null default false;
comment on column public.products.icbper is 'Bolsa plástica afecta al ICBPER: el comprobante declara S/ 0.50 por unidad dentro del precio.';
grant update (icbper) on public.products to authenticated;
commit;
notify pgrst, 'reload schema';
