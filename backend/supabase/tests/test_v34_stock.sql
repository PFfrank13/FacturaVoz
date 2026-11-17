\set ON_ERROR_STOP 1
-- v3.4: el stock solo se mueve con product_id explícito; el texto libre jamás descuenta otro producto ni bloquea.
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe'),('22222222-2222-2222-2222-222222222222','otro@b.pe');
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
select org_id as org2 from public.organization_members where user_id='22222222-2222-2222-2222-222222222222' \gset
-- For this test company the business rule is strict Bodega/Tienda stock.
insert into public.org_settings(org_id,business_type) values (:'org','bodega')
  on conflict (org_id) do update set business_type = excluded.business_type;
insert into public.org_settings(org_id,business_type) values (:'org2','salon')
  on conflict (org_id) do update set business_type = excluded.business_type;
create or replace function pg_temp.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin if not coalesce(p_ok,false) then raise exception 'FALLO: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',false);
insert into public.products(org_id,user_id,name,unit_price,unit,stock,active) values (:'org2',auth.uid(),'Ajeno',1,'NIU',9,true) returning id as ajeno \gset
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false);
insert into public.products(org_id,user_id,name,unit_price,unit,stock,active) values (:'org',auth.uid(),'Agua',1,'NIU',10,true) returning id as agua \gset
insert into public.products(org_id,user_id,name,unit_price,unit,stock,active) values (:'org',auth.uid(),'Gaseosa',2,'NIU',5,true) returning id as gas1 \gset
insert into public.products(org_id,user_id,name,unit_price,unit,stock,active) values (:'org',auth.uid(),'Gaseosa 1L',2,'NIU',5,true) returning id as gas2 \gset
insert into public.products(org_id,user_id,name,unit_price,unit,active) values (:'org',auth.uid(),'Servicio',20,'ZZ',true) returning id as serv \gset
-- 1) Producto + texto libre que coincide EXACTO con el nombre de otro producto + producto sin control de stock
select invoice_id as inv from public.create_invoice('Cliente',null,18,'PEN',null,null,
  jsonb_build_array(
    jsonb_build_object('description','Agua','quantity',2,'unit_price',1,'product_id',:'agua'),
    jsonb_build_object('description','Agua','quantity',3,'unit_price',1),
    jsonb_build_object('description','Gaseosa','quantity',1,'unit_price',2),
    jsonb_build_object('description','Servicio','quantity',1,'unit_price',20,'product_id',:'serv')
  ), :'org') \gset
update public.invoices set status='sent' where id=:'inv';
select pg_temp.chk('solo descuenta la línea con product_id (10-2=8)', (select stock from public.products where id=:'agua') = 8);
select pg_temp.chk('texto libre igual al nombre de un producto no descuenta (antes sí)', (select stock from public.products where id=:'gas1') = 5 and (select stock from public.products where id=:'gas2') = 5);
select pg_temp.chk('producto sin control de stock no cambia', (select stock from public.products where id=:'serv') is null);
select pg_temp.chk('trazabilidad: un evento por línea con producto controlado', (select count(*) from public.retail_sale_stock_events where invoice_id=:'inv') = 1);
-- 2) Solo texto libre (emisión por voz o manual sin catálogo)
select invoice_id as inv2 from public.create_invoice('Cliente',null,18,'PEN',null,'dos aguas',
  '[{"description":"Agua","quantity":2,"unit_price":1},{"description":"Instalación","quantity":1,"unit_price":50}]'::jsonb, :'org') \gset
update public.invoices set status='sent' where id=:'inv2';
select pg_temp.chk('emisión solo texto libre funciona y no toca stock', (select status from public.invoices where id=:'inv2') = 'sent' and (select stock from public.products where id=:'agua') = 8);
-- 3) Bodega: venta con inventario insuficiente BLOQUEADA.
-- La factura ya creada en draft no se envía; no hay salida ni pago.
select invoice_id as inv3 from public.create_invoice('Cliente',null,18,'PEN',null,null,
  jsonb_build_array(jsonb_build_object('description','Agua','quantity',20,'unit_price',1,'product_id',:'agua')), :'org') \gset
\set ON_ERROR_STOP 0
update public.invoices set status='sent' where id=:'inv3';
\set ON_ERROR_STOP 1
select pg_temp.chk('venta insuficiente no cambia stock ni estado ni eventos',
  (select stock from public.products where id=:'agua') = 8
  and (select status from public.invoices where id=:'inv3') = 'draft'
  and (select count(*) from public.retail_sale_stock_events where invoice_id=:'inv3') = 0);
-- 4) Venta válida, reintento mismo documento no duplica evento.
select invoice_id as inv5 from public.create_invoice('Cliente',null,18,'PEN',null,null,
  jsonb_build_array(jsonb_build_object('description','Agua','quantity',2,'unit_price',1,'product_id',:'agua')), :'org') \gset
update public.invoices set status='sent' where id=:'inv5';
select pg_temp.chk('venta válida descuenta 2 y deja stock 6',
  (select stock from public.products where id=:'agua') = 6
  and (select count(*) from public.retail_sale_stock_events where invoice_id=:'inv5') = 1);
update public.invoices set status='sent' where id=:'inv5';
select pg_temp.chk('reintentar transición no descuenta dos veces',
  (select stock from public.products where id=:'agua') = 6
  and (select count(*) from public.retail_sale_stock_events where invoice_id=:'inv5') = 1);
-- 4b) RPC cobro rápido: una sobreventa revierte factura, pago, solicitud y stock.
select set_config('fv.test_org', :'org', false);
select set_config('fv.test_product', :'agua', false);
do $
declare
  v_org uuid := current_setting('fv.test_org')::uuid;
  v_product uuid := current_setting('fv.test_product')::uuid;
  v_request uuid := gen_random_uuid();
  v_invoices integer;
  v_payments integer;
  v_rejected boolean := false;
begin
  select count(*) into v_invoices from public.invoices where org_id = v_org;
  select count(*) into v_payments from public.payments where org_id = v_org;
  begin
    perform * from public.fast_checkout_atomic(
      v_org, v_request,
      jsonb_build_array(jsonb_build_object(
        'description','Agua','quantity',999,'unit_price',1,'product_id',v_product
      )),
      18,'PEN','efectivo','stock insufficient rollback test'
    );
  exception when sqlstate '22023' then
    v_rejected := true;
  end;
  if not v_rejected
    or (select count(*) from public.invoices where org_id = v_org) <> v_invoices
    or (select count(*) from public.payments where org_id = v_org) <> v_payments
    or (select count(*) from public.fast_checkout_requests
          where org_id = v_org and request_id = v_request) <> 0
    or (select stock from public.products where id = v_product) <> 6 then
      raise exception 'FALLO: cobro rapido insuficiente tuvo efectos parciales';
  end if;
end $;
-- 5) Producto de otra empresa: rechazado
\set ON_ERROR_STOP 0
select invoice_id as inv4 from public.create_invoice('Cliente',null,18,'PEN',null,null,
  jsonb_build_array(jsonb_build_object('description','Ajeno','quantity',1,'unit_price',1,'product_id',:'ajeno')), :'org') \gset
\set ON_ERROR_STOP 1
reset role;
select pg_temp.chk('el producto ajeno no se tocó', (select stock from public.products where id=:'ajeno') = 9);
-- 6) Ni siquiera una actualización SQL directa puede dejar un SKU de bodega negativo.
\set ON_ERROR_STOP 0
update public.products set stock=-2 where id=:'agua';
\set ON_ERROR_STOP 1
select pg_temp.chk('modificación directa bloqueada; saldo anterior intacto',
  (select stock from public.products where id=:'agua') = 6);
-- 7) Stock nulo significa SKU sin seguimiento: permite servicios sin descontar existencias.
select pg_temp.chk('servicio sin seguimiento conserva stock NULL',
  (select stock from public.products where id=:'serv') is null);
-- 8) Otros rubros mantienen su política anterior (no cambiar nueve rubros).
update public.products set stock=-1 where id=:'ajeno';
select pg_temp.chk('salon no recibe restricción exclusiva de Bodega',
  (select stock from public.products where id=:'ajeno') = -1);

