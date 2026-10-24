-- FacturaVoz · Migración 001 (producción + app Flutter)
-- Ejecutar DESPUÉS de supabase/schema.sql, completo, en Supabase > SQL Editor > Run.
-- Es idempotente: se puede ejecutar más de una vez sin romper nada.

begin;

-- 1) Ajustes del negocio por usuario (moneda e impuesto elegidos por el usuario, sin valores inventados)
alter table public.profiles
  add column if not exists currency text,
  add column if not exists default_tax_rate numeric(5,2),
  add column if not exists tax_label text;

alter table public.profiles drop constraint if exists profiles_limits_chk;
alter table public.profiles add constraint profiles_limits_chk check (
  (business_name is null or char_length(business_name) <= 120)
  and (tax_id is null or char_length(tax_id) <= 30)
  and (address is null or char_length(address) <= 300)
  and (currency is null or currency ~ '^[A-Z]{3}$')
  and (default_tax_rate is null or default_tax_rate between 0 and 100)
  and (tax_label is null or char_length(tax_label) between 1 and 20)
);

-- 2) Moneda por factura (las anteriores se emitieron en EUR)
alter table public.invoices
  add column if not exists currency text not null default 'EUR';

alter table public.invoices drop constraint if exists invoices_limits_chk;
alter table public.invoices add constraint invoices_limits_chk check (
  currency ~ '^[A-Z]{3}$'
  and (notes is null or char_length(notes) <= 500)
  and (transcript is null or char_length(transcript) <= 5000)
);

alter table public.clients drop constraint if exists clients_limits_chk;
alter table public.clients add constraint clients_limits_chk check (
  (email is null or char_length(email) <= 200)
  and (tax_id is null or char_length(tax_id) <= 30)
  and (address is null or char_length(address) <= 300)
);

-- Orden de las líneas
alter table public.invoice_items add column if not exists position integer not null default 0;

-- 3) Facturas emitidas inmutables (requisito fiscal básico)
create or replace function private.guard_invoice_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id or new.number is distinct from old.number then
    raise exception 'Campos inmutables' using errcode = '42501';
  end if;
  if old.status <> 'draft' then
    if new.issue_date is distinct from old.issue_date
       or new.tax_rate is distinct from old.tax_rate
       or new.currency is distinct from old.currency
       or new.notes is distinct from old.notes
       or new.transcript is distinct from old.transcript
       or (new.client_id is distinct from old.client_id and new.client_id is not null) then
      raise exception 'Una factura emitida no se puede editar' using errcode = '42501';
    end if;
    if not ((old.status = 'sent' and new.status in ('sent', 'paid'))
         or (old.status = 'paid' and new.status = 'paid')) then
      raise exception 'Cambio de estado no permitido' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_invoice_update on public.invoices;
create trigger guard_invoice_update
  before update on public.invoices
  for each row execute function private.guard_invoice_update();

revoke execute on function private.guard_invoice_update() from public, anon, authenticated;

-- Las líneas solo se tocan mientras la factura es borrador
drop policy if exists "items_insert" on public.invoice_items;
drop policy if exists "items_update" on public.invoice_items;
drop policy if exists "items_delete" on public.invoice_items;

create policy "items_insert" on public.invoice_items for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.invoices i
      where i.id = invoice_id and i.user_id = (select auth.uid()) and i.status = 'draft')
  );
create policy "items_update" on public.invoice_items for update to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.invoices i
      where i.id = invoice_id and i.user_id = (select auth.uid()) and i.status = 'draft')
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.invoices i
      where i.id = invoice_id and i.user_id = (select auth.uid()) and i.status = 'draft')
  );
create policy "items_delete" on public.invoice_items for delete to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.invoices i
      where i.id = invoice_id and i.user_id = (select auth.uid()) and i.status = 'draft')
  );

-- 4) Crear factura de forma ATÓMICA (cliente + número correlativo + cabecera + líneas)
--    SECURITY INVOKER: se aplica RLS como al resto de operaciones del usuario.
create or replace function public.create_invoice(
  p_client_name text,
  p_client_tax_id text,
  p_tax_rate numeric,
  p_currency text,
  p_notes text,
  p_transcript text,
  p_items jsonb
)
returns table (invoice_id uuid, invoice_number text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_client_name, ''));
  v_tax text := nullif(btrim(coalesce(p_client_tax_id, '')), '');
  v_client uuid;
  v_next bigint;
  v_id uuid;
  v_number text;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '28000';
  end if;
  if char_length(v_name) not between 1 and 120 then
    raise exception 'Cliente no válido' using errcode = '22023';
  end if;
  if v_tax is not null and char_length(v_tax) > 30 then
    raise exception 'Documento del cliente no válido' using errcode = '22023';
  end if;
  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then
    raise exception 'Impuesto no válido' using errcode = '22023';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'Moneda no válida' using errcode = '22023';
  end if;
  if p_notes is not null and char_length(p_notes) > 500 then
    raise exception 'Notas demasiado largas' using errcode = '22023';
  end if;
  if p_transcript is not null and char_length(p_transcript) > 5000 then
    raise exception 'Transcripción demasiado larga' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 50 then
    raise exception 'Líneas no válidas' using errcode = '22023';
  end if;

  -- Serializa la numeración por usuario
  perform pg_advisory_xact_lock(hashtextextended('invoice-number:' || v_uid::text, 0));

  insert into public.profiles (id) values (v_uid) on conflict (id) do nothing;

  select c.id into v_client
  from public.clients c
  where c.user_id = v_uid and lower(c.name) = lower(v_name)
  order by c.created_at
  limit 1;

  if v_client is null then
    insert into public.clients (user_id, name, tax_id)
    values (v_uid, v_name, v_tax)
    returning clients.id into v_client;
  elsif v_tax is not null then
    update public.clients set tax_id = v_tax where clients.id = v_client and clients.tax_id is null;
  end if;

  select coalesce(max((substring(i.number from '(\d+)$'))::bigint), 0) + 1
  into v_next
  from public.invoices i
  where i.user_id = v_uid and i.number ~ '\d+$';

  v_number := 'F-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next::text, 4, '0');

  insert into public.invoices (user_id, client_id, number, tax_rate, currency, notes, transcript)
  values (v_uid, v_client, v_number, p_tax_rate, p_currency, p_notes, p_transcript)
  returning invoices.id into v_id;

  insert into public.invoice_items (user_id, invoice_id, description, quantity, unit_price, position)
  select v_uid, v_id, btrim(e.item ->> 'description'),
         (e.item ->> 'quantity')::numeric, (e.item ->> 'unit_price')::numeric, e.ord::integer
  from jsonb_array_elements(p_items) with ordinality as e(item, ord);

  return query select v_id, v_number;
end;
$$;

revoke execute on function public.create_invoice(text, text, numeric, text, text, text, jsonb) from public, anon;
grant execute on function public.create_invoice(text, text, numeric, text, text, text, jsonb) to authenticated;

-- 5) Cuota de uso atómica (anti-abuso de la API de IA). Cuenta y registra en una sola operación.
create or replace function public.consume_api_quota(p_per_minute integer, p_per_day integer)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_min integer;
  v_day integer;
begin
  if v_uid is null then
    return false;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('api-quota:' || v_uid::text, 0));
  select count(*) filter (where u.created_at >= now() - interval '1 minute'), count(*)
  into v_min, v_day
  from public.api_usage u
  where u.user_id = v_uid and u.created_at >= now() - interval '1 day';
  if v_min >= p_per_minute or v_day >= p_per_day then
    return false;
  end if;
  insert into public.api_usage (user_id) values (v_uid);
  return true;
end;
$$;

revoke execute on function public.consume_api_quota(integer, integer) from public, anon;
grant execute on function public.consume_api_quota(integer, integer) to authenticated;

-- 6) Derecho de supresión (obligatorio en App Store / Google Play): el usuario borra su propia cuenta.
--    ÚNICA función SECURITY DEFINER pública: solo puede borrar auth.uid(), search_path vacío.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '28000';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

commit;
