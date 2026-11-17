\set ON_ERROR_STOP 1
-- v3.4: el stock solo se mueve con product_id explícito; el texto libre jamás descuenta otro producto ni bloquea.
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','dueno@a.pe'),('22222222-2222-2222-2222-222222222222','otro@b.pe');
select org_id as org from public.organization_members where user_id='11111111-1111-1111-1111-111111111111' \gset
select org_id as org2 from public.organization_members where user_id='22222222-2222-2222-2222-222222222222' \gset
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
-- 3) Stock insuficiente: se permite (venta de mostrador), queda negativo y trazado
select invoice_id as inv3 from public.create_invoice('Cliente',null,18,'PEN',null,null,
  jsonb_build_array(jsonb_build_object('description','Agua','quantity',20,'unit_price',1,'product_id',:'agua')), :'org') \gset
update public.invoices set status='sent' where id=:'inv3';
select pg_temp.chk('stock insuficiente queda negativo y trazado', (select stock from public.products where id=:'agua') = -12 and (select stock_before from public.retail_sale_stock_events where invoice_id=:'inv3') = 8);
-- 4) Reintento / transición repetida: no vuelve a descontar
update public.invoices set status='sent' where id=:'inv3';
select pg_temp.chk('repetir la transición no descuenta dos veces', (select stock from public.products where id=:'agua') = -12 and (select count(*) from public.retail_sale_stock_events where invoice_id=:'inv3') = 1);
-- 5) Producto de otra empresa: rechazado
\set ON_ERROR_STOP 0
select invoice_id as inv4 from public.create_invoice('Cliente',null,18,'PEN',null,null,
  jsonb_build_array(jsonb_build_object('description','Ajeno','quantity',1,'unit_price',1,'product_id',:'ajeno')), :'org') \gset
\set ON_ERROR_STOP 1
reset role;
select pg_temp.chk('el producto ajeno no se tocó', (select stock from public.products where id=:'ajeno') = 9);
