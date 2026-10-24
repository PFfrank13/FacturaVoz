-- FacturaVoz · Notas de crédito electrónicas (SUNAT tipo 07) y endurecimiento de delete_my_account.
-- Ejecutar DESPUÉS de 20261023_mobile_prod.sql y 20261024_fiscal_sunat.sql. Idempotente.
begin;

-- 1) Notas de crédito: una por comprobante (anulación total). Solo escribe el servidor.
create table if not exists public.fiscal_notes (
  invoice_id uuid primary key references public.invoices(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  series text not null check (series ~ '^[FB][A-Z0-9]{3}$'),
  correlative integer not null check (correlative between 1 and 99999999),
  env text not null check (env in ('beta', 'prod')),
  reason_code text not null check (reason_code in ('01', '06')),
  reason_text text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'error')),
  payload jsonb not null,
  totals jsonb not null,
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
create index if not exists idx_fiscal_notes_user_id on public.fiscal_notes(user_id);
alter table public.fiscal_notes enable row level security;
drop policy if exists "fiscal_notes_select" on public.fiscal_notes;
create policy "fiscal_notes_select" on public.fiscal_notes for select to authenticated
  using ((select auth.uid()) = user_id);
revoke insert, update, delete on public.fiscal_notes from authenticated, anon;
revoke all on public.fiscal_notes from anon;

-- 2) Reserva idempotente de la nota (misma numeración en reintentos; si SUNAT la rechaza se reenvía con el mismo número)
create or replace function public.fiscal_reserve_note(
  p_user uuid, p_invoice uuid, p_series text, p_reason_code text, p_reason_text text,
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
  perform pg_advisory_xact_lock(hashtextextended('fiscal:' || p_user::text, 0));

  select * into v_doc from public.fiscal_documents d where d.invoice_id = p_invoice and d.user_id = p_user;
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

  insert into public.document_series as s (user_id, series, last_number)
  values (p_user, p_series, 1)
  on conflict (user_id, series) do update set last_number = s.last_number + 1
  returning s.last_number into v_n;

  v_payload := jsonb_set(jsonb_set(p_payload, '{serie}', to_jsonb(p_series)),
                         '{correlativo}', to_jsonb(v_n::text));

  insert into public.fiscal_notes
    (invoice_id, user_id, series, correlative, env, reason_code, reason_text, status, payload, totals)
  values
    (p_invoice, p_user, p_series, v_n, p_env, p_reason_code, p_reason_text, 'pending', v_payload, p_totals);

  return query select p_series, v_n, v_payload, 'pending'::text;
end;
$$;

create or replace function public.fiscal_record_note(
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
    where invoice_id = p_invoice and user_id = p_user and status <> 'accepted';
end;
$$;

revoke execute on function public.fiscal_reserve_note(uuid, uuid, text, text, text, jsonb, jsonb, text) from public, anon, authenticated;
revoke execute on function public.fiscal_record_note(uuid, uuid, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fiscal_reserve_note(uuid, uuid, text, text, text, jsonb, jsonb, text) to service_role;
grant execute on function public.fiscal_record_note(uuid, uuid, text, text, text, text, text, text, text) to service_role;

-- 3) SECURITY DEFINER solo en el esquema private (regla del proyecto).
--    La función pública pasa a ser SECURITY INVOKER y delega en private.delete_account_impl().
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.delete_account_impl()
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
  if exists (select 1 from public.fiscal_documents d where d.user_id = v_uid and d.env = 'prod')
     or exists (select 1 from public.fiscal_notes n where n.user_id = v_uid and n.env = 'prod') then
    raise exception 'Tienes comprobantes electrónicos que debes conservar por ley; contacta a soporte para cerrar tu cuenta'
      using errcode = 'P0001';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;
revoke execute on function private.delete_account_impl() from public, anon;
grant execute on function private.delete_account_impl() to authenticated;

create or replace function public.delete_my_account()
returns void
language sql
security invoker
set search_path = ''
as $$ select private.delete_account_impl(); $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

commit;
