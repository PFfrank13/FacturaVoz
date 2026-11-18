-- v3.5 · Bodega/Tienda: impedir stock negativo para productos controlados.
-- Política: stock NULL = SKU sin control de existencias; no bloquear servicios.
-- Solo business_type='bodega'; no modificar inventarios, facturas ni eventos históricos.
-- Se ejecuta dentro de la misma transacción del checkout: una salida insuficiente
-- revierte la emisión, el pago y los movimientos, también con dos cajas en paralelo.
-- Guardar como migración para una única aplicación después de v34b.
begin;

create or replace function private.bodega_stock_nonnegative_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.stock is not null and new.stock < 0 and exists (
    select 1
      from public.org_settings s
     where s.org_id = new.org_id
       and s.business_type = 'bodega'
  ) then
    raise exception 'Stock insuficiente para %. Registra una compra o corrige existencias antes de vender.', new.name
      using errcode = '22023';
  end if;
  return new;
end
$$;

revoke all on function private.bodega_stock_nonnegative_guard()
from public, anon, authenticated;

drop trigger if exists trg_bodega_stock_nonnegative on public.products;
create trigger trg_bodega_stock_nonnegative
  before insert or update of stock, org_id on public.products
  for each row execute function private.bodega_stock_nonnegative_guard();

comment on function private.bodega_stock_nonnegative_guard() is
  'Bodega: prohibe inventario negativo SOLO en SKU con stock numerico. NULL=sin seguimiento. Operaciones y cobros se revierten atomically si la venta deja saldo negativo. No altera el stock historico.';

commit;
