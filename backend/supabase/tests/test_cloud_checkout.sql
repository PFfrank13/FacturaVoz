-- Synthetic users/licenses only, rollback-only isolated PostgreSQL runner.
insert into auth.users(id,email) values
 ('11111111-1111-4111-8111-111111111111','owner-a@lab.invalid'),
 ('22222222-2222-4222-8222-222222222222','owner-b@lab.invalid');
update public.org_licenses set source='hub', token='SYNTHETIC-NOT-A-SIGNED-LICENSE',
 license_code='LAB-ONLY', mode='full', features=private.all_features();
insert into private.org_license_activations(org_id,license_code,activated_by)
 select org_id,'LAB-ONLY',user_id from public.organization_members where role='owner';
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
do $$
declare org uuid; product uuid; first_sale record; recovered record; before_count int; remaining numeric;
begin
 select org_id into org from public.organization_members where user_id=auth.uid() limit 1;
 if org is null then raise exception 'Missing synthetic company'; end if;
 insert into public.products(org_id,user_id,name,unit_price,stock)
 values(org,auth.uid(),'Synthetic rice',10,10) returning id into product;
 select * into first_sale from public.fast_checkout_atomic(org,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   jsonb_build_array(jsonb_build_object('product_id',product,'description','Synthetic rice','quantity',2,'unit_price',10)),18,'PEN','efectivo');
 if first_sale.invoice_id is null or first_sale.charged <> 23.60 or first_sale.reused then raise exception 'Incorrect initial receipt'; end if;
 select * into recovered from public.fast_checkout_atomic(org,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   jsonb_build_array(jsonb_build_object('product_id',product,'description','Synthetic rice','quantity',2,'unit_price',10)),18,'PEN','efectivo');
 if recovered.invoice_id <> first_sale.invoice_id or not recovered.reused then raise exception 'Idempotency failed'; end if;
 if (select count(*) from public.payments where invoice_id=first_sale.invoice_id) <> 1 then raise exception 'Duplicate payment'; end if;
 select stock into remaining from public.products where id=product;
 if remaining <> 8 then raise exception 'Stock applied more than once: %',remaining; end if;
 if (public.day_summary(org,(now() at time zone 'America/Lima')::date)->>'expected_cash')::numeric is distinct from 23.60 then
   raise exception 'Cash summary does not reconcile with the one recorded payment';
 end if;
 select count(*) into before_count from public.invoices where org_id=org;
 begin
   perform public.fast_checkout_atomic(org,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
     jsonb_build_array(jsonb_build_object('product_id',product,'description','Synthetic rice','quantity',100,'unit_price',10)),18,'PEN','efectivo');
   raise exception 'Oversell unexpectedly accepted';
 exception when sqlstate '22023' then null;
 end;
 if (select count(*) from public.invoices where org_id=org) <> before_count then raise exception 'Failed sale left invoice'; end if;
 if exists(select 1 from public.fast_checkout_requests where request_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then raise exception 'Failed sale left request'; end if;
 if (select stock from public.products where id=product) <> 8 then raise exception 'Failed sale changed stock'; end if;
 raise notice 'PASS: authenticated sale, idempotent recovery, one payment, stock deduction and atomic oversell rollback';
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$ begin
 if exists(select 1 from public.fast_checkout_requests where request_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then raise exception 'Cross-company request visible'; end if;
 if exists(select 1 from public.products where name='Synthetic rice') then raise exception 'Cross-company product visible'; end if;
 raise notice 'PASS: company B cannot read company A ticket or product';
end $$;
reset role;
