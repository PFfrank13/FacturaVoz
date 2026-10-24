-- FacturaVoz · Migración 002 · Facturación electrónica SUNAT (vía Lycet/Greenter)
-- Ejecutar DESPUÉS de 20261023_mobile_prod.sql. Idempotente.
--
-- Principio: lo fiscal (series, correlativos, resultados de SUNAT) solo lo escribe el SERVIDOR con la
-- clave service_role. El usuario únicamente LEE sus documentos (RLS), así nadie puede falsificar
-- un estado "aceptado" ni alterar su numeración desde la app.

begin;

-- 1) Datos fiscales del emisor (se completan en la app) y del cliente
alter table public.profiles
  add column if not exists trade_name text,
  add column if not exists ubigeo text,
  add column if not exists department text,
  add column if not exists province text,
  add column if not exists district text,
  add column if not exists series_factura text not null default 'F001',
  add column if not exists series_boleta text not null default 'B001';

alter table public.profiles drop constraint if exists profiles_fiscal_chk;
alter table public.profiles add constraint profiles_fiscal_chk check (
  (trade_name is null or char_length(trade_name) <= 120)
  and (ubigeo is null or ubigeo ~ '^\d{6}$')
  and (department is null or char_length(department) <= 60)
  and (province is null or char_length(province) <= 60)
  and (district is null or char_length(district) <= 60)
  and series_factura ~ '^F[A-Z0-9]{3}$'
  and series_boleta ~ '^B[A-Z0-9]{3}$'
);

-- Tipo de documento del cliente (catálogo SUNAT 06): 6 RUC, 1 DNI, 4 carnet extranjería, 7 pasaporte, 0 sin documento
alter table public.clients add column if not exists doc_type text;
alter table public.clients drop constraint if exists clients_doc_type_chk;
alter table public.clients add constraint clients_doc_type_chk check (doc_type is null or doc_type in ('6','1','4','7','0'));

-- 2) Empresas habilitadas para emitir (RUC reclamado por UN usuario; solo escribe el servidor)
create table if not exists public.fiscal_companies (
  ruc text primary key check (ruc ~ '^\d{11}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  env text not null default 'beta' check (env in ('beta', 'prod')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.fiscal_companies enable row level security;
drop policy if exists "fiscal_companies_select" on public.fiscal_companies;
create policy "fiscal_companies_select" on public.fiscal_companies for select to authenticated
  using ((select auth.uid()) = user_id);

-- 3) Contadores de correlativo por serie (sin acceso desde la app)
create table if not exists public.document_series (
  user_id uuid not null references auth.users(id) on delete cascade,
  series text not null check (series ~ '^[FB][A-Z0-9]{3}$'),
  last_number integer not null default 0,
  primary key (user_id, series)
);
alter table public.document_series enable row level security; -- sin políticas: denegado a authenticated/anon

-- 4) Comprobantes electrónicos
create table if not exists public.fiscal_documents (
  invoice_id uuid primary key references public.invoices(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  doc_type text not null check (doc_type in ('01', '03')),
  series text not null check (series ~ '^[FB][A-Z0-9]{3}$'),
  correlative integer not null check (correlative between 1 and 99999999),
  env text not null check (env in ('beta', 'prod')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'error')),
  afectacion text not null check (afectacion in ('gravado', 'exonerado', 'inafecto')),
  payload jsonb not null,
  totals jsonb not null,
  legend text not null,
  sunat_code text,
  sunat_message text,
  hash text,
  xml text,
  cdr text,
  attempts integer not null default 0,
  last_error text,
  issued_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, series, correlative)
);
create index if not exists idx_fiscal_documents_user_id on public.fiscal_documents(user_id);
alter table public.fiscal_documents enable row level security;
drop policy if exists "fiscal_documents_select" on public.fiscal_documents;
create policy "fiscal_documents_select" on public.fiscal_documents for select to authenticated
  using ((select auth.uid()) = user_id);

-- La app solo LEE (los permisos por defecto de Supabase dan escritura; se retiran)
revoke insert, update, delete on public.fiscal_companies, public.document_series, public.fiscal_documents from authenticated, anon;
revoke all on public.document_series from authenticated, anon;
revoke all on public.fiscal_companies, public.fiscal_documents from anon;

-- 5) Funciones SOLO para el servidor (service_role). SECURITY INVOKER.

-- Reclama un RUC para un usuario. 'ok' | 'ruc_taken' | 'other_ruc'
create or replace function public.fiscal_claim_company(p_user uuid, p_ruc text, p_env text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_existing text;
  v_n integer;
begin
  select c.ruc into v_existing from public.fiscal_companies c where c.user_id = p_user;
  if v_existing is not null and v_existing <> p_ruc then
    return 'other_ruc';
  end if;
  insert into public.fiscal_companies (ruc, user_id, env) values (p_ruc, p_user, p_env)
  on conflict (ruc) do update set env = excluded.env, updated_at = now()
  where public.fiscal_companies.user_id = p_user;
  get diagnostics v_n = row_count;
  return case when v_n = 0 then 'ruc_taken' else 'ok' end;
end;
$$;

-- Reserva serie+correlativo de forma atómica e idempotente.
-- Si el comprobante ya existe devuelve el mismo número (reintentos no consumen correlativos).
create or replace function public.fiscal_reserve(
  p_user uuid, p_invoice uuid, p_doc_type text, p_series text,
  p_payload jsonb, p_totals jsonb, p_legend text, p_afectacion text, p_env text
)
returns table (out_series text, out_correlative integer, out_payload jsonb, out_status text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
  v_inv public.invoices%rowtype;
  v_n integer;
  v_payload jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('fiscal:' || p_user::text, 0));

  select * into v_inv from public.invoices i where i.id = p_invoice and i.user_id = p_user;
  if not found then
    raise exception 'Factura no encontrada' using errcode = 'P0002';
  end if;

  select * into v_doc from public.fiscal_documents d where d.invoice_id = p_invoice;
  if found then
    if v_doc.status = 'rejected' then
      -- SUNAT rechazó: se reenvía con la MISMA numeración y datos corregidos
      v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(v_doc.series)),
                             '{correlativo}', to_jsonb(v_doc.correlative::text));
      update public.fiscal_documents
        set payload = v_payload, totals = p_totals, legend = p_legend, status = 'pending',
            afectacion = p_afectacion, updated_at = now()
        where invoice_id = p_invoice;
      return query select v_doc.series, v_doc.correlative, v_payload, 'pending'::text;
    else
      return query select v_doc.series, v_doc.correlative, v_doc.payload, v_doc.status;
    end if;
    return;
  end if;

  insert into public.document_series as s (user_id, series, last_number)
  values (p_user, p_series, 1)
  on conflict (user_id, series) do update set last_number = s.last_number + 1
  returning s.last_number into v_n;

  v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(p_series)),
                         '{correlativo}', to_jsonb(v_n::text));

  insert into public.fiscal_documents
    (invoice_id, user_id, doc_type, series, correlative, env, status, afectacion, payload, totals, legend)
  values
    (p_invoice, p_user, p_doc_type, p_series, v_n, p_env, 'pending', p_afectacion, v_payload, p_totals, p_legend);

  if v_inv.status = 'draft' then
    update public.invoices set status = 'sent' where id = p_invoice;
  end if;

  return query select p_series, v_n, v_payload, 'pending'::text;
end;
$$;

-- Guarda el resultado de SUNAT. Un comprobante ACEPTADO ya no cambia.
create or replace function public.fiscal_record(
  p_user uuid, p_invoice uuid, p_status text, p_code text, p_message text,
  p_hash text, p_xml text, p_cdr text, p_error text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_status not in ('accepted', 'rejected', 'error') then
    raise exception 'Estado no válido' using errcode = '22023';
  end if;
  update public.fiscal_documents
    set status = p_status,
        sunat_code = left(p_code, 20),
        sunat_message = left(p_message, 1000),
        hash = coalesce(p_hash, hash),
        xml = coalesce(p_xml, xml),
        cdr = coalesce(p_cdr, cdr),
        last_error = left(p_error, 500),
        attempts = attempts + 1,
        updated_at = now()
    where invoice_id = p_invoice and user_id = p_user and status <> 'accepted';
end;
$$;

revoke execute on function public.fiscal_claim_company(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.fiscal_reserve(uuid, uuid, text, text, jsonb, jsonb, text, text, text) from public, anon, authenticated;
revoke execute on function public.fiscal_record(uuid, uuid, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fiscal_claim_company(uuid, text, text) to service_role;
grant execute on function public.fiscal_reserve(uuid, uuid, text, text, jsonb, jsonb, text, text, text) to service_role;
grant execute on function public.fiscal_record(uuid, uuid, text, text, text, text, text, text, text) to service_role;

-- 6) Supresión de cuenta compatible con la obligación de conservar comprobantes de PRODUCCIÓN.
--    (Reemplaza la función de la migración 001.) Sin comprobantes reales, borra todo como antes.
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
  if exists (select 1 from public.fiscal_documents d where d.user_id = v_uid and d.env = 'prod') then
    raise exception 'Tienes comprobantes electrónicos que debes conservar por ley; contacta a soporte para cerrar tu cuenta'
      using errcode = 'P0001';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

commit;
