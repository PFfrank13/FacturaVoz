-- FacturaVoz · Migración 14 · Validez SUNAT (numeración tras rechazo) + marca del emisor (logo, plantilla, ticket)
--
-- a) Numeración tras un RECHAZO de SUNAT
--    Un comprobante rechazado (códigos 2000–3999) no tiene validez y SUNAT no admite volver a enviar la misma
--    serie-número (responde 1032: "comprobante ya informado ... anulado o rechazado"). Antes se reenviaba con el
--    mismo número. Ahora: el intento rechazado queda archivado (fiscal_rejections) y el reenvío corregido toma un
--    NUEVO correlativo de la misma serie. Los estados 'error' (sin respuesta) conservan su número: SUNAT pudo
--    haberlo recibido y se recupera su CDR (código 1033 / consulta de estado).
-- b) Logo y preferencias de impresión de cada empresa + almacenamiento privado de archivos por empresa.
--
-- Idempotente y aditiva. Ejecutar después de 20261104.
begin;

-- ───────────── a) Archivo de rechazos ─────────────
create table if not exists public.fiscal_rejections (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  kind text not null default 'invoice' check (kind in ('invoice', 'note')),
  doc_type text,
  series text not null,
  correlative integer not null,
  sunat_code text,
  sunat_message text,
  rejected_at timestamptz not null default now()
);
create index if not exists idx_fiscal_rejections_org on public.fiscal_rejections(org_id, rejected_at desc);
create index if not exists idx_fiscal_rejections_invoice on public.fiscal_rejections(invoice_id);
alter table public.fiscal_rejections enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'fiscal_rejections' and policyname = 'fiscal_rejections_select') then
    create policy "fiscal_rejections_select" on public.fiscal_rejections for select to authenticated using (private.is_org_member(org_id));
  end if;
end $$;
revoke all on public.fiscal_rejections from anon, authenticated;
grant select on public.fiscal_rejections to authenticated;
grant select, insert, update, delete on public.fiscal_rejections to service_role;

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
  v_has_doc boolean;
  v_n integer;
  v_payload jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('fiscal:' || p_org::text, 0));

  select * into v_inv from public.invoices i where i.id = p_invoice and i.org_id = p_org;
  if not found then
    raise exception 'Factura no encontrada' using errcode = 'P0002';
  end if;

  select * into v_doc from public.fiscal_documents d where d.invoice_id = p_invoice;
  v_has_doc := found;
  if v_has_doc and v_doc.status <> 'rejected' then
    return query select v_doc.series, v_doc.correlative, v_doc.payload, v_doc.status;
    return;
  end if;

  -- Número nuevo (primer envío, o reenvío corregido después de un rechazo)
  insert into public.document_series as s (org_id, user_id, series, last_number)
  values (p_org, p_user, p_series, 1)
  on conflict (org_id, series) do update set last_number = s.last_number + 1
  returning s.last_number into v_n;

  v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(p_series)),
                         '{correlativo}', to_jsonb(v_n::text));

  if v_has_doc then
    insert into public.fiscal_rejections (org_id, invoice_id, kind, doc_type, series, correlative, sunat_code, sunat_message)
    values (p_org, p_invoice, 'invoice', v_doc.doc_type, v_doc.series, v_doc.correlative, v_doc.sunat_code, v_doc.sunat_message);
    update public.fiscal_documents
      set doc_type = p_doc_type, series = p_series, correlative = v_n, env = p_env, payload = v_payload, totals = p_totals,
          legend = p_legend, afectacion = p_afectacion, status = 'pending', sunat_code = null, sunat_message = null,
          hash = null, xml = null, cdr = null, last_error = null, updated_at = now(), issued_at = now()
      where invoice_id = p_invoice;
  else
    insert into public.fiscal_documents
      (invoice_id, org_id, user_id, doc_type, series, correlative, env, status, afectacion, payload, totals, legend)
    values
      (p_invoice, p_org, p_user, p_doc_type, p_series, v_n, p_env, 'pending', p_afectacion, v_payload, p_totals, p_legend);
  end if;

  if v_inv.status = 'draft' then
    update public.invoices set status = 'sent' where id = p_invoice;
  end if;

  return query select p_series, v_n, v_payload, 'pending'::text;
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
  v_has_note boolean;
  v_n integer;
  v_payload jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('fiscal:' || p_org::text, 0));

  select * into v_doc from public.fiscal_documents d where d.invoice_id = p_invoice and d.org_id = p_org;
  if not found or v_doc.status <> 'accepted' then
    raise exception 'Solo se puede anular un comprobante aceptado por SUNAT' using errcode = 'P0001';
  end if;

  select * into v_note from public.fiscal_notes n where n.invoice_id = p_invoice;
  v_has_note := found;
  if v_has_note and v_note.status <> 'rejected' then
    return query select v_note.series, v_note.correlative, v_note.payload, v_note.status;
    return;
  end if;

  insert into public.document_series as s (org_id, user_id, series, last_number)
  values (p_org, p_user, p_series, 1)
  on conflict (org_id, series) do update set last_number = s.last_number + 1
  returning s.last_number into v_n;

  v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(p_series)),
                         '{correlativo}', to_jsonb(v_n::text));

  if v_has_note then
    insert into public.fiscal_rejections (org_id, invoice_id, kind, doc_type, series, correlative, sunat_code, sunat_message)
    values (p_org, p_invoice, 'note', '07', v_note.series, v_note.correlative, v_note.sunat_code, v_note.sunat_message);
    update public.fiscal_notes
      set series = p_series, correlative = v_n, env = p_env, payload = v_payload, totals = p_totals,
          reason_code = p_reason_code, reason_text = p_reason_text, status = 'pending', sunat_code = null,
          sunat_message = null, hash = null, xml = null, cdr = null, last_error = null, updated_at = now()
      where invoice_id = p_invoice;
  else
    insert into public.fiscal_notes
      (invoice_id, org_id, user_id, series, correlative, env, reason_code, reason_text, status, payload, totals)
    values
      (p_invoice, p_org, p_user, p_series, v_n, p_env, p_reason_code, p_reason_text, 'pending', v_payload, p_totals);
  end if;

  return query select p_series, v_n, v_payload, 'pending'::text;
end;
$$;

revoke execute on function public.fiscal_reserve(uuid, uuid, uuid, text, text, jsonb, jsonb, text, text, text),
  public.fiscal_reserve_note(uuid, uuid, uuid, text, text, text, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.fiscal_reserve(uuid, uuid, uuid, text, text, jsonb, jsonb, text, text, text),
  public.fiscal_reserve_note(uuid, uuid, uuid, text, text, text, jsonb, jsonb, text) to service_role;

-- ───────────── b) Marca del emisor ─────────────
alter table public.organizations
  add column if not exists logo_path text,
  add column if not exists pdf_template text not null default 'clasico',
  add column if not exists ticket_width smallint not null default 80,
  add column if not exists brand_color text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'organizations_brand_chk') then
    alter table public.organizations add constraint organizations_brand_chk check (
      (logo_path is null or char_length(logo_path) <= 300)
      and pdf_template in ('clasico', 'moderno', 'minimal')
      and ticket_width in (58, 80)
      and (brand_color is null or brand_color ~ '^#[0-9A-Fa-f]{6}$'));
  end if;
end $$;
grant update (logo_path, pdf_template, ticket_width, brand_color) on public.organizations to authenticated;

-- Convierte texto a uuid sin fallar (para leer el id de empresa desde la ruta de un archivo).
create or replace function private.try_uuid(p text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p::uuid;
exception when others then
  return null;
end;
$$;
revoke execute on function private.try_uuid(text) from public, anon;
grant execute on function private.try_uuid(text) to authenticated, service_role;

-- Archivos privados por empresa: org-media/{org_id}/{logo|productos|trabajos|clientes}/archivo
-- Solo miembros de esa empresa leen o suben; el logo solo lo cambia propietario/administrador.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('org-media', 'org-media', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do nothing;

    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'org_media_select') then
      create policy "org_media_select" on storage.objects for select to authenticated
        using (bucket_id = 'org-media' and private.is_org_member(private.try_uuid((storage.foldername(name))[1])));
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'org_media_insert') then
      create policy "org_media_insert" on storage.objects for insert to authenticated
        with check (bucket_id = 'org-media'
          and private.is_org_member(private.try_uuid((storage.foldername(name))[1]))
          and ((storage.foldername(name))[2] is distinct from 'logo' or private.is_org_admin(private.try_uuid((storage.foldername(name))[1]))));
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'org_media_update') then
      create policy "org_media_update" on storage.objects for update to authenticated
        using (bucket_id = 'org-media' and private.is_org_member(private.try_uuid((storage.foldername(name))[1]))
          and ((storage.foldername(name))[2] is distinct from 'logo' or private.is_org_admin(private.try_uuid((storage.foldername(name))[1]))))
        with check (bucket_id = 'org-media' and private.is_org_member(private.try_uuid((storage.foldername(name))[1])));
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'org_media_delete') then
      create policy "org_media_delete" on storage.objects for delete to authenticated
        using (bucket_id = 'org-media' and private.is_org_member(private.try_uuid((storage.foldername(name))[1]))
          and ((storage.foldername(name))[2] is distinct from 'logo' or private.is_org_admin(private.try_uuid((storage.foldername(name))[1]))));
    end if;
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
