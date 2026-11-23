-- v3.7 · Productos por kilo (docs/INVESTIGACION_RETAIL.md, fila 2: venta suelta y por peso en el plan Básico).
-- Solo AMPLÍA la regla de unidad: NIU (unidad) y ZZ (servicio) siguen igual; se añade KGM (kilogramo,
-- catálogo 03 de SUNAT). No cambia ningún dato. El stock ya admite 2 decimales (numeric(14,2)) y la
-- recepción de compras acepta KGM desde v3.6.
begin;
alter table public.products drop constraint if exists products_unit_check;
alter table public.products add constraint products_unit_check check (unit in ('NIU', 'ZZ', 'KGM'));
comment on column public.products.unit is 'NIU unidad, KGM kilogramo (venta por peso o por monto), ZZ servicio.';
commit;
notify pgrst, 'reload schema';
