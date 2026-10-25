-- FacturaVoz · Migración 5 · Multi-empresa Fase 2: emisor y SUNAT por empresa
-- Ejecutar DESPUÉS de 20261027_multitenant.sql. Idempotente.
-- Datos del emisor (razón social, dirección, series, moneda, impuesto), RUC/certificado y correlativos
-- pasan de ser "del usuario" a ser "de la empresa". Cualquier miembro puede emitir; solo
-- propietario/administrador edita los datos o conecta SUNAT.
begin;

-- 1) Datos del emisor en la empresa -------------------------------------------------------------
alter table public.organizations
  add column if not exists trade_name text,
  add column if not exists address text,
  add column if not exists ubigeo text,
  add column if not exists department text,
  add column if not exists province text,
  add column if not exists district text,
  add column if not exists series_factura text not null default 'F001',
  add column if not exists series_boleta text not null default 'B001',
  add column if not exists currency text,
  add column if not exists tax_label text,
  add column if not exists default_tax_rate numeric(5,2);

alter table public.organizations drop constraint if exists organizations_fiscal_chk;
alter table public.organizations add constraint organizations_fiscal_chk check (
  (trade_name is null or char_length(trade_name) <= 120)
  and (address is null or char_length(address) <= 300)
  and (ubigeo is null or ubigeo ~ '^\d{6}$')
  and (department is null or char_length(department) <= 60)
  and (province is null or char_length(province) <= 60)
  and (district is null or char_length(district) <= 60)
  and series_factura ~ '^F[A-Z0-9]{3}$'
  and series_boleta ~ '^B[A-Z0-9]{3}$'
  and (currency is null or currency ~ '^[A-Z]{3}$')
  and (tax_label is null or char_length(tax_label) between 1 and 20)
  and (default_tax_rate is null or default_tax_rate between 0 and 100)
);

-- Backfill: la empresa personal hereda los datos del perfil de su propietario
update public.organizations o set
  trade_name = p.trade_name, address = p.address, ubigeo = p.ubigeo, department = p.department,
  province = p.province, district = p.district, series_factura = p.series_factura,
  series_boleta = p.series_boleta, currency = p.currency, tax_label = p.tax_label,
  default_tax_rate = p.default_tax_rate
from public.profiles p
where p.id = o.created_by and o.currency is null and o.tax_label is null;

grant update (name, tax_id, trade_name, address, ubigeo, department, province, district,
              series_factura, series_boleta, currency, tax_label, default_tax_rate)
  on public.organizations to authenticated;

-- 2) RUC / certificado por empresa ----------------------------------------------------------------
alter table public.fiscal_companies add column if not exists org_id uuid references public.organizations(id) on delete cascade;
update public.fiscal_companies c set org_id = (
  select m.org_id from public.organization_members m where m.user_id = c.user_id order by m.created_at limit 1)
where c.org_id is null;
alter table public.fiscal_companies alter column org_id set not null;
alter table public.fiscal_companies drop constraint if exists fiscal_companies_user_id_key;
create unique index if not exists fiscal_companies_org_key on public.fiscal_companies(org_id);
drop policy if exists "fiscal_companies_select" on public.fiscal_companies;
create policy "fiscal_companies_select" on public.fiscal_companies for select to authenticated
  using (private.is_org_member(org_id));

-- 3) Correlativos por empresa --------------------------------------------------------------------
alter table public.document_series add column if not exists org_id uuid references public.organizations(id) on delete cascade;
update public.document_series s set org_id = (
  select m.org_id from public.organization_members m where m.user_id = s.user_id order by m.created_at limit 1)
where s.org_id is null;
alter table public.document_series alter column org_id set not null;
alter table public.document_series drop constraint if exists document_series_pkey;
alter table public.document_series add primary key (org_id, series);
alter table public.document_series alter column user_id drop not null;

alter table public.fiscal_documents add column if not exists org_id uuid references public.organizations(id) on delete cascade;
update public.fiscal_documents d set org_id = i.org_id from public.invoices i where i.id = d.invoice_id and d.org_id is null;
alter table public.fiscal_documents alter column org_id set not null;
alter table public.fiscal_documents drop constraint if exists fiscal_documents_user_id_series_correlative_key;
create unique index if not exists fiscal_documents_org_number_key on public.fiscal_documents(org_id, series, correlative);

alter table public.fiscal_notes add column if not exists org_id uuid references public.organizations(id) on delete cascade;
update public.fiscal_notes n set org_id = i.org_id from public.invoices i where i.id = n.invoice_id and n.org_id is null;
alter table public.fiscal_notes alter column org_id set not null;
alter table public.fiscal_notes drop constraint if exists fiscal_notes_user_id_series_correlative_key;
create unique index if not exists fiscal_notes_org_number_key on public.fiscal_notes(org_id, series, correlative);

-- 4) Funciones del servidor (service_role) por empresa -------------------------------------------
drop function if exists public.fiscal_claim_company(uuid, text, text);
drop function if exists public.fiscal_reserve(uuid, uuid, text, text, jsonb, jsonb, text, text, text);
drop function if exists public.fiscal_record(uuid, uuid, text, text, text, text, text, text, text);
drop function if exists public.fiscal_reserve_note(uuid, uuid, text, text, text, jsonb, jsonb, text);
drop function if exists public.fiscal_record_note(uuid, uuid, text, text, text, text, text, text, text);

-- 'ok' | 'ruc_taken' | 'other_ruc'
create or replace function public.fiscal_claim_company(p_org uuid, p_user uuid, p_ruc text, p_env text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_existing text;
  v_n integer;
begin
  select c.ruc into v_existing from public.fiscal_companies c where c.org_id = p_org;
  if v_existing is not null and v_existing <> p_ruc then
    return 'other_ruc';
  end if;
  insert into public.fiscal_companies (ruc, org_id, user_id, env) values (p_ruc, p_org, p_user, p_env)
  on conflict (ruc) do update set env = excluded.env, updated_at = now()
  where public.fiscal_companies.org_id = p_org;
  get diagnostics v_n = row_count;
  return case when v_n = 0 then 'ruc_taken' else 'ok' end;
end;
$$;

create or replace function public.fiscal_reserve(
  p_org uuid, p_user uuid, p_invoice uuid, p_doc_type text, p_series text,
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
  perform pg_advisory_xact_lock(hashtextextended('fiscal:' || p_org::text, 0));

  select * into v_inv from public.invoices i where i.id = p_invoice and i.org_id = p_org;
  if not found then
    raise exception 'Factura no encontrada' using errcode = 'P0002';
  end if;

  select * into v_doc from public.fiscal_documents d where d.invoice_id = p_invoice;
  if found then
    if v_doc.status = 'rejected' then
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

  insert into public.document_series as s (org_id, user_id, series, last_number)
  values (p_org, p_user, p_series, 1)
  on conflict (org_id, series) do update set last_number = s.last_number + 1
  returning s.last_number into v_n;

  v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(p_series)),
                         '{correlativo}', to_jsonb(v_n::text));

  insert into public.fiscal_documents
    (invoice_id, org_id, user_id, doc_type, series, correlative, env, status, afectacion, payload, totals, legend)
  values
    (p_invoice, p_org, p_user, p_doc_type, p_series, v_n, p_env, 'pending', p_afectacion, v_payload, p_totals, p_legend);

  if v_inv.status = 'draft' then
    update public.invoices set status = 'sent' where id = p_invoice;
  end if;

  return query select p_series, v_n, v_payload, 'pending'::text;
end;
$$;

create or replace function public.fiscal_record(
  p_org uuid, p_invoice uuid, p_status text, p_code text, p_message text,
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
    where invoice_id = p_invoice and org_id = p_org and status <> 'accepted';
end;
$$;

create or replace function public.fiscal_reserve_note(
  p_org uuid, p_user uuid, p_invoice uuid, p_series text, p_reason_code text, p_reason_text text,
  p_payload jsonb, p_totals jsonb, p_env text
)
returns table (out_series text, out_correlative integer, out_payload jsonb, out_status text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_doc public.fiscal_documents%rowtype;
  v_note public.fiscal_notes%rowtype;
  v_n integer;
  v_payload jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('fiscal:' || p_org::text, 0));

  select * into v_doc from public.fiscal_documents d where d.invoice_id = p_invoice and d.org_id = p_org;
  if not found or v_doc.status <> 'accepted' then
    raise exception 'Solo se puede anular un comprobante aceptado por SUNAT' using errcode = 'P0001';
  end if;

  select * into v_note from public.fiscal_notes n where n.invoice_id = p_invoice;
  if found then
    if v_note.status = 'rejected' then
      v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(v_note.series)),
                             '{correlativo}', to_jsonb(v_note.correlative::text));
      update public.fiscal_notes
        set payload = v_payload, totals = p_totals, reason_code = p_reason_code, reason_text = p_reason_text,
            status = 'pending', updated_at = now()
        where invoice_id = p_invoice;
      return query select v_note.series, v_note.correlative, v_payload, 'pending'::text;
    else
      return query select v_note.series, v_note.correlative, v_note.payload, v_note.status;
    end if;
    return;
  end if;

  insert into public.document_series as s (org_id, user_id, series, last_number)
  values (p_org, p_user, p_series, 1)
  on conflict (org_id, series) do update set last_number = s.last_number + 1
  returning s.last_number into v_n;

  v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(p_series)),
                         '{correlativo}', to_jsonb(v_n::text));

  insert into public.fiscal_notes
    (invoice_id, org_id, user_id, series, correlative, env, reason_code, reason_text, status, payload, totals)
  values
    (p_invoice, p_org, p_user, p_series, v_n, p_env, p_reason_code, p_reason_text, 'pending', v_payload, p_totals);

  return query select p_series, v_n, v_payload, 'pending'::text;
end;
$$;

create or replace function public.fiscal_record_note(
  p_org uuid, p_invoice uuid, p_status text, p_code text, p_message text,
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
  update public.fiscal_notes
    set status = p_status,
        sunat_code = left(p_code, 20),
        sunat_message = left(p_message, 1000),
        hash = coalesce(p_hash, hash),
        xml = coalesce(p_xml, xml),
        cdr = coalesce(p_cdr, cdr),
        last_error = left(p_error, 500),
        attempts = attempts + 1,
        updated_at = now()
    where invoice_id = p_invoice and org_id = p_org and status <> 'accepted';
end;
$$;

revoke execute on function public.fiscal_claim_company(uuid, uuid, text, text),
  public.fiscal_reserve(uuid, uuid, uuid, text, text, jsonb, jsonb, text, text, text),
  public.fiscal_record(uuid, uuid, text, text, text, text, text, text, text),
  public.fiscal_reserve_note(uuid, uuid, uuid, text, text, text, jsonb, jsonb, text),
  public.fiscal_record_note(uuid, uuid, text, text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.fiscal_claim_company(uuid, uuid, text, text),
  public.fiscal_reserve(uuid, uuid, uuid, text, text, jsonb, jsonb, text, text, text),
  public.fiscal_record(uuid, uuid, text, text, text, text, text, text, text),
  public.fiscal_reserve_note(uuid, uuid, uuid, text, text, text, jsonb, jsonb, text),
  public.fiscal_record_note(uuid, uuid, text, text, text, text, text, text, text)
  to service_role;

-- 5) Rol propio en una empresa (para que el servidor exija admin al conectar SUNAT) --------------
create or replace function private.my_org_role(p_org uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role from public.organization_members m where m.org_id = p_org and m.user_id = (select auth.uid());
$$;
revoke execute on function private.my_org_role(uuid) from public, anon;
grant execute on function private.my_org_role(uuid) to authenticated;
create or replace function public.my_org_role(p_org uuid)
returns text language sql stable security invoker set search_path = ''
as $$ select private.my_org_role(p_org); $$;
revoke execute on function public.my_org_role(uuid) from public, anon;
grant execute on function public.my_org_role(uuid) to authenticated;

commit;
