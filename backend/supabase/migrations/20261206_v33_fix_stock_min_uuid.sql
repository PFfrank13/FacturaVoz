-- v3.3 · Corrige la salida de stock al emitir (20261128): `min(p.id)` sobre uuid no existe en PostgreSQL
-- ("function min(uuid) does not exist"). Con search_path = '' la función fallaba SIEMPRE que una línea no traía
-- product_id (facturas dictadas o escritas), bloqueando la emisión. Reproducido en PostgreSQL 16 con
-- backend/supabase/tests/test_sunat.sql. Misma lógica; solo cambia cómo se toma el id único.
-- Idempotente. Probar en staging antes de producción.
begin;
create or replace function private.apply_stock_on_issue()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_product uuid;
  v_count integer;
  v_before numeric(14,2);
  v_after numeric(14,2);
begin
  if old.status = 'draft' and new.status <> 'draft' then
    for r in
      select it.id as item_id, it.product_id, it.description, it.quantity
        from public.invoice_items it
        where it.invoice_id = new.id
        -- Stable ordering avoids locks inversions when tills sell same SKUs.
        order by it.product_id nulls last, it.id
    loop
      if r.quantity <= 0 or r.quantity > 100000 then
        raise exception 'Cantidad no válida en una línea de venta' using errcode='22023';
      end if;
      v_product := r.product_id;
      if v_product is null then
        select count(*), (array_agg(p.id order by p.id))[1] into v_count, v_product
          from public.products p
          where p.org_id = new.org_id and p.active
            and lower(btrim(p.name)) = lower(btrim(r.description));
        if v_count > 1 then
          raise exception 'Nombre ambiguo; selecciona el SKU: %', r.description using errcode='22023';
        end if;
        if v_count = 0 then continue; end if;
      end if;
      if exists(
        select 1 from public.retail_sale_stock_events e
        where e.invoice_item_id = r.item_id
      ) then
        raise exception 'La salida de inventario de esta línea ya existe'
          using errcode = '23505';
      end if;
      select p.stock into v_before from public.products p
        where p.org_id = new.org_id and p.id = v_product for update;
      if not found then
        raise exception 'Producto ajeno o inexistente' using errcode='42501';
      end if;
      -- A null stock means this SKU is not stock controlled.
      if v_before is null then continue; end if;
      v_after := v_before - r.quantity;
      if v_after < -10000000 or v_after > 10000000 then
        raise exception 'Stock fuera de límites técnicos' using errcode='22023';
      end if;
      update public.products set stock = v_after
        where id = v_product and org_id = new.org_id;
      insert into public.retail_sale_stock_events(
        org_id, invoice_id, invoice_item_id, product_id,
        quantity_delta, stock_before, stock_after
      ) values (
        new.org_id, new.id, r.item_id, v_product,
        -r.quantity, v_before, v_after
      );
    end loop;
  end if;
  return new;
end $$;
revoke all on function private.apply_stock_on_issue() from public,anon,authenticated;
commit;
