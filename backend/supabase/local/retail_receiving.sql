-- LOCAL LAB PROPOSAL, after all existing migrations. Not a production migration.
-- Receipts are immutable. A receipt records merchandise, never a supplier payment.
create table public.retail_suppliers (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations(id),
 name text not null check(length(name) between 1 and 120)
);
create unique index retail_supplier_name on public.retail_suppliers(org_id,lower(btrim(name)));
create table public.retail_receipts (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations(id),
 request_id uuid not null, user_id uuid not null references auth.users(id),
 supplier_id uuid not null references public.retail_suppliers(id), supplier_name text not null,
 reference text not null check(length(reference) between 1 and 80),
 currency text not null, total numeric(14,2) not null, created_at timestamptz not null default now(),
 unique(org_id,request_id), unique(org_id,supplier_id,reference)
);
create table public.retail_receipt_lines (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations(id),
 receipt_id uuid not null references public.retail_receipts(id), product_id uuid not null references public.products(id),
 quantity numeric(14,2) not null check(quantity>0), unit_cost numeric(14,2) not null check(unit_cost>=0),
 unique(receipt_id,product_id)
);
create table public.retail_stock_ledger (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations(id),
 product_id uuid not null references public.products(id), user_id uuid references auth.users(id),
 before_stock numeric, after_stock numeric, delta numeric,
 created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['retail_suppliers','retail_receipts','retail_receipt_lines','retail_stock_ledger'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy retail_read on public.%I for select to authenticated using (private.is_org_member(org_id) and private.can_finance(org_id) and private.has_feature(org_id,''stock'') and private.license_write_ok(org_id))',t);
 end loop;
end $$;
create function private.retail_stock_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
   if new.stock is not null then
     insert into public.retail_stock_ledger(org_id,product_id,user_id,before_stock,after_stock,delta)
     values(new.org_id,new.id,auth.uid(),null,new.stock,new.stock);
   end if;
 elsif old.stock is distinct from new.stock then
   insert into public.retail_stock_ledger(org_id,product_id,user_id,before_stock,after_stock,delta)
   values(new.org_id,new.id,auth.uid(),old.stock,new.stock,coalesce(new.stock,0)-coalesce(old.stock,0));
 end if;
 return new;
end $$;
revoke all on function private.retail_stock_audit() from public,anon,authenticated;
create trigger retail_stock_audit after insert or update of stock on public.products for each row execute function private.retail_stock_audit();
-- Opening snapshot, not reconstructed historical movements. Existing records stay intact.
insert into public.retail_stock_ledger(org_id,product_id,user_id,before_stock,after_stock,delta)
select org_id,id,null,null,stock,stock from public.products where stock is not null;

create function private.retail_receive_impl(p_org uuid,p_request uuid,p_supplier text,p_reference text,p_lines jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); receipt uuid; supplier uuid; line record; total numeric:=0; cur text; previous_user uuid;
begin
 if uid is null or not private.is_org_member(p_org) or not private.can_finance(p_org)
   or not private.has_feature(p_org,'stock') or not private.license_write_ok(p_org) then
   raise exception 'No tienes permiso para recibir mercadería' using errcode='42501';
 end if;
 if p_request is null then raise exception 'Falta identificador' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||p_request::text,0));
 select id,user_id into receipt,previous_user from public.retail_receipts where org_id=p_org and request_id=p_request;
 if receipt is not null then
   if previous_user<>uid then raise exception 'Operación de otro usuario' using errcode='42501'; end if;
   return receipt;
 end if;
 if coalesce(length(btrim(p_supplier)),0) not between 1 and 120 or coalesce(length(btrim(p_reference)),0) not between 1 and 80
   or p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 1 and 50 then
   raise exception 'Revisa proveedor, referencia y productos' using errcode='22023';
 end if;
 if (select count(distinct x->>'product_id') from jsonb_array_elements(p_lines) x) <> jsonb_array_length(p_lines) then
   raise exception 'Productos duplicados o sin identificador' using errcode='22023';
 end if;
 -- All receivers lock products in the same order. Null stock is not silently enabled.
 for line in select * from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity numeric,unit_cost numeric) order by product_id loop
   if line.quantity is null or line.quantity<=0 or line.quantity>100000 or line.quantity<>round(line.quantity,2)
     or line.unit_cost is null or line.unit_cost<0 or line.unit_cost>10000000 or line.unit_cost<>round(line.unit_cost,2) then
     raise exception 'Cantidad o costo inválido' using errcode='22023'; end if;
   perform 1 from public.products where id=line.product_id and org_id=p_org and active and stock is not null for update;
   if not found then raise exception 'Producto ajeno, inactivo o sin control de stock' using errcode='22023'; end if;
   total:=total+round(line.quantity*line.unit_cost,2);
 end loop;
 select coalesce(currency,'PEN') into cur from public.organizations where id=p_org;
 insert into public.retail_suppliers(org_id,name) values(p_org,btrim(p_supplier)) on conflict(org_id,lower(btrim(name))) do update set name=public.retail_suppliers.name returning id into supplier;
 insert into public.retail_receipts(org_id,request_id,user_id,supplier_id,supplier_name,reference,currency,total)
 values(p_org,p_request,uid,supplier,btrim(p_supplier),upper(btrim(p_reference)),cur,total) returning id into receipt;
 for line in select * from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity numeric,unit_cost numeric) order by product_id loop
   insert into public.retail_receipt_lines(org_id,receipt_id,product_id,quantity,unit_cost) values(p_org,receipt,line.product_id,line.quantity,line.unit_cost);
   update public.products set stock=stock+line.quantity,unit_cost=line.unit_cost where id=line.product_id and org_id=p_org;
 end loop;
 return receipt;
end $$;
revoke all on function private.retail_receive_impl(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function private.retail_receive_impl(uuid,uuid,text,text,jsonb) to authenticated;
create function public.retail_receive(p_org uuid,p_request uuid,p_supplier text,p_reference text,p_lines jsonb)
returns uuid language sql security invoker set search_path='' as $$ select private.retail_receive_impl(p_org,p_request,p_supplier,p_reference,p_lines) $$;
revoke all on function public.retail_receive(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.retail_receive(uuid,uuid,text,text,jsonb) to authenticated;
