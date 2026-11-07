-- Local proposal. Requires the existing v31 checkout migration.
-- Preserve signed Hub contracts; apply only after restored-database tests.
create or replace function public.fast_checkout_atomic(
  p_org_id uuid, p_request_id uuid, p_items jsonb,
  p_tax_rate numeric, p_currency text, p_method text,
  p_notes text default null
)
returns table (invoice_id uuid, charged numeric, reused boolean)
language plpgsql security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.fast_checkout_requests%rowtype;
  v_invoice uuid;
  v_amount numeric(14,2);
  r record;
  v_currency text;
  v_tax numeric;
  v_catalog public.products%rowtype;
begin
  if v_uid is null or p_org_id is null or not private.is_org_member(p_org_id) then
    raise exception 'Empresa o sesión no válida' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Falta identificador de venta' using errcode = '22023'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Líneas de venta no válidas' using errcode = '22023';
  end if;
  if p_method not in ('efectivo','yape','plin','tarjeta','transferencia') then
    raise exception 'Método de pago no admitido' using errcode = '22023';
  end if;
  -- All fast POS items must have an ID; descriptions are NOT an inventory key.
  if exists (
    select 1 from jsonb_array_elements(p_items) as x(item)
    where nullif(x.item->>'product_id', '') is null
  ) then raise exception 'Una línea no tiene product_id' using errcode = '22023'; end if;
  insert into public.fast_checkout_requests(org_id, request_id, user_id)
    values (p_org_id, p_request_id, v_uid)
    on conflict (org_id, request_id) do nothing;
  select * into v_row from public.fast_checkout_requests f
   where f.org_id = p_org_id and f.request_id = p_request_id for update;
  if v_row.user_id <> v_uid then
    raise exception 'Identificador de venta reservado por otro usuario' using errcode = '42501';
  end if;
  if v_row.invoice_id is not null then
    select coalesce(sum(p.amount), 0) into v_amount from public.payments p where p.invoice_id = v_row.invoice_id;
    return query select v_row.invoice_id, v_amount, true;
    return;
  end if;
  -- Recovery above must survive later catalogue changes. New sales lock the
  -- organization and every SKU in a stable order before validating snapshots.
  select coalesce(nullif(currency,''),'PEN'), coalesce(default_tax_rate,18) into v_currency, v_tax
    from public.organizations where id=p_org_id for share;
  if p_currency is distinct from v_currency or p_tax_rate is distinct from v_tax then
    raise exception 'Cambió la moneda o el impuesto; revisa el ticket' using errcode='P2001';
  end if;
  if (select count(distinct x->>'product_id') from jsonb_array_elements(p_items) x)
      <> jsonb_array_length(p_items) then
    raise exception 'Producto duplicado en el ticket' using errcode='P2001';
  end if;
  for r in select e.value as item from jsonb_array_elements(p_items) e
      order by (e.value->>'product_id')::uuid loop
    select * into v_catalog from public.products
      where org_id=p_org_id and id=(r.item->>'product_id')::uuid and active for update;
    if not found then raise exception 'Producto no válido para esta empresa' using errcode='42501'; end if;
    if (r.item->>'quantity')::numeric is null or (r.item->>'quantity')::numeric <= 0
       or (r.item->>'quantity')::numeric > 100000
       or round((r.item->>'quantity')::numeric,2) <> (r.item->>'quantity')::numeric then
      raise exception 'Cantidad no válida' using errcode='P2001';
    end if;
    if (r.item->>'unit_price')::numeric is distinct from v_catalog.unit_price then
      raise exception 'Cambió un precio del catálogo; revisa el ticket' using errcode='P2001';
    end if;
  end loop;
  select ci.invoice_id into v_invoice from public.create_invoice(
     'Cliente final', null, p_tax_rate, p_currency, p_notes, 'Venta rápida', p_items, p_org_id
  ) ci;
  if v_invoice is null then raise exception 'No se pudo registrar la venta'; end if;
  update public.invoice_items it
    set product_id = (p_items->(it.position - 1)->>'product_id')::uuid
    where it.invoice_id = v_invoice;
  select round(coalesce(i.amt_total, 0), 2) into v_amount
    from public.invoices i where i.id = v_invoice;
  if v_amount <= 0 then raise exception 'Importe de venta no válido' using errcode = '22023'; end if;
  update public.invoices set status = 'sent' where id = v_invoice and org_id = p_org_id and status = 'draft';
  if not found then raise exception 'La venta no pudo confirmarse'; end if;
  insert into public.payments(org_id, invoice_id, user_id, amount, method)
    values(p_org_id, v_invoice, v_uid, v_amount, p_method);
  update public.fast_checkout_requests set invoice_id = v_invoice
    where org_id = p_org_id and request_id = p_request_id;
  return query select v_invoice, v_amount, false;
end $$;
revoke all on function public.fast_checkout_atomic(uuid,uuid,jsonb,numeric,text,text,text) from public,anon;
grant execute on function public.fast_checkout_atomic(uuid,uuid,jsonb,numeric,text,text,text) to authenticated;

