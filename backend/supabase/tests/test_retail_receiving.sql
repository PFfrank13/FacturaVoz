set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
do $$ declare org uuid; product uuid; second_product uuid; receipt uuid; again uuid; payload jsonb; balance numeric; begin
 select org_id,id into org,product from public.products where name='Synthetic rice';
 insert into public.products(org_id,user_id,name,unit_price,stock) values(org,auth.uid(),'Synthetic milk',4,0) returning id into second_product;
 payload:=jsonb_build_array(jsonb_build_object('product_id',product,'quantity',5,'unit_cost',6),jsonb_build_object('product_id',second_product,'quantity',4,'unit_cost',2));
 receipt:=public.retail_receive(org,'cccccccc-cccc-4ccc-8ccc-cccccccccccc','Proveedor QA','QA-001',payload);
 again:=public.retail_receive(org,'cccccccc-cccc-4ccc-8ccc-cccccccccccc','Proveedor QA','QA-001',payload);
 if receipt<>again then raise exception 'Duplicate receipt'; end if;
 if (select stock from public.products where id=product)<>13 then raise exception 'Receipt stock mismatch'; end if;
 if (select unit_cost from public.products where id=product)<>6 then raise exception 'Cost not updated'; end if;
 if (select total from public.retail_receipts where id=receipt)<>38 then raise exception 'Cost total incorrect'; end if;
 if (select stock from public.products where id=second_product)<>4 or (select count(*) from public.retail_receipt_lines where receipt_id=receipt)<>2 then raise exception 'Multi-product receipt incomplete'; end if;
 if (select sum(delta) from public.retail_stock_ledger where product_id=product)<>13 then raise exception 'Ledger balance incorrect'; end if;
 begin
   perform public.retail_receive(org,'dddddddd-dddd-4ddd-8ddd-dddddddddddd','Proveedor QA','QA-001',payload);
   raise exception 'Duplicate supplier document accepted';
 exception when unique_violation then null; end;
 if (select stock from public.products where id=product)<>13 then raise exception 'Duplicate document modified stock'; end if;
 begin
   update public.retail_stock_ledger set delta=999 where product_id=product;
   raise exception 'Ledger can be edited by authenticated role';
 exception when insufficient_privilege then null; end;
 begin
   perform public.retail_receive(org,'dddddddd-aaaa-4ddd-8ddd-dddddddddddd','Proveedor QA','QA-INVALID',jsonb_build_array(
     jsonb_build_object('product_id',product,'quantity',1,'unit_cost',6),
     jsonb_build_object('product_id','00000000-0000-4000-8000-000000000000','quantity',2,'unit_cost',6)));
   raise exception 'Unknown product accepted';
 exception when sqlstate '22023' then null; end;
 if exists(select 1 from public.retail_receipts where reference='QA-INVALID') or (select stock from public.products where id=product)<>13 then raise exception 'Invalid batch partially applied'; end if;
 perform public.fast_checkout_atomic(org,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',jsonb_build_array(jsonb_build_object('product_id',product,'description','Synthetic rice','quantity',3,'unit_price',10)),18,'PEN','efectivo');
 select stock into balance from public.products where id=product;
 if balance<>10 or (select sum(delta) from public.retail_stock_ledger where product_id=product)<>balance then raise exception 'Receipt-sale-ledger mismatch'; end if;
 if (public.day_summary(org,(now() at time zone 'America/Lima')::date)->>'expected_cash')::numeric<>59 then raise exception 'Cash reconciliation mismatch'; end if;
 raise notice 'PASS: supplier -> receipt -> cost -> inventory -> sale -> payment -> cash; retry and duplicate document protected';
end $$;
select set_config('lab.target_org',(select org_id::text from public.products where name='Synthetic rice'),true);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$ begin
 if exists(select 1 from public.retail_receipts where reference='QA-001') or exists(select 1 from public.retail_stock_ledger) then raise exception 'Cross-company receiving data exposed'; end if;
 begin
   perform public.retail_receive(current_setting('lab.target_org')::uuid,'dddddddd-bbbb-4ddd-8ddd-dddddddddddd','Intruder','FORBIDDEN','[]');
   raise exception 'Cross-company RPC accepted';
 exception when insufficient_privilege then null; end;
 raise notice 'PASS: immutable ledger, invalid batch rollback and receiving tenant isolation';
end $$;
reset role;
