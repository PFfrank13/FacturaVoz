-- Importación masiva de facturas históricas (miles de filas) SIN timeouts:
--   1) la app sube las filas en bloques pequeños a una tabla de paso (import_rows),
--   2) la base de datos las convierte en facturas por lotes (import_step / worker pg_cron),
--   3) la app muestra el progreso en vivo (Realtime sobre import_jobs).
-- Nada de esto pasa por una petición web larga. Seguro de ejecutar varias veces. Requiere 20261027 y 20261030.

create table if not exists public.import_jobs (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  source       text not null default 'file' check (source in ('file', 'sire')),
  file_name    text check (file_name is null or char_length(file_name) <= 200),
  status       text not null default 'uploading'
               check (status in ('uploading', 'queued', 'processing', 'done', 'failed', 'cancelled')),
  tax_rate     numeric(5,2) not null default 18 check (tax_rate between 0 and 100),
  total        integer not null default 0 check (total >= 0),      -- filas aceptadas para procesar
  uploaded     integer not null default 0 check (uploaded >= 0),
  processed    integer not null default 0 check (processed >= 0),
  imported     integer not null default 0 check (imported >= 0),   -- facturas creadas
  skipped      integer not null default 0 check (skipped >= 0),    -- filas rechazadas o repetidas
  error        text check (error is null or char_length(error) <= 500),
  notified_at  timestamptz,
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index if not exists idx_import_jobs_org on public.import_jobs(org_id, created_at desc);
create index if not exists idx_import_jobs_user on public.import_jobs(user_id);
create index if not exists idx_import_jobs_active on public.import_jobs(status) where status in ('queued', 'processing');

create table if not exists public.import_rows (
  id           bigint generated always as identity primary key,
  job_id       uuid not null references public.import_jobs(id) on delete cascade,
  row_no       integer not null,
  client_name  text not null default '',
  client_tax_id text,
  description  text,
  amount       numeric(14,2) not null check (amount >= 0 and amount <= 100000000),
  currency     text not null default 'PEN' check (currency ~ '^[A-Z]{3}$'),
  issue_date   date,
  doc_number   text,
  state        text not null default 'pending' check (state in ('pending', 'done', 'skipped'))
);
create index if not exists idx_import_rows_pending on public.import_rows(job_id, id) where state = 'pending';

alter table public.import_jobs enable row level security;
alter table public.import_rows enable row level security;

drop policy if exists "import_jobs_select" on public.import_jobs;
create policy "import_jobs_select" on public.import_jobs for select to authenticated
  using (private.is_org_member(org_id));
drop policy if exists "import_jobs_insert" on public.import_jobs;
create policy "import_jobs_insert" on public.import_jobs for insert to authenticated
  with check ((select auth.uid()) = user_id and private.is_org_member(org_id) and status = 'uploading'
              and total = 0 and uploaded = 0 and processed = 0 and imported = 0 and skipped = 0);
-- Sin policies de update/delete ni acceso directo a import_rows: todo pasa por las funciones de abajo.
revoke all on public.import_rows from authenticated, anon;
revoke update, delete on public.import_jobs from authenticated, anon;

-- Número del comprobante importado: el original, o uno sintético estable por trabajo y fila.
create or replace function private.import_number(p_job uuid, p_row integer, p_doc text)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(coalesce(nullif(btrim(p_doc), ''), 'IMP-' || substr(p_job::text, 1, 6) || '-' || lpad(p_row::text, 6, '0')), 60)
$$;

-- 1) Subir un bloque (máx. 1000 filas). Valida cada fila; las no válidas se cuentan como omitidas.
create or replace function private.import_add_rows_impl(p_job uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  j public.import_jobs;
  v_n integer;
  v_ok integer;
begin
  select * into j from public.import_jobs where id = p_job;
  if not found or j.user_id is distinct from v_uid or not private.is_org_member(j.org_id) then
    raise exception 'Importación no encontrada' using errcode = '42501';
  end if;
  if j.status <> 'uploading' then raise exception 'La importación ya no acepta filas' using errcode = '22023'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Formato no válido' using errcode = '22023'; end if;
  v_n := jsonb_array_length(p_rows);
  if v_n > 1000 then raise exception 'Máximo 1000 filas por bloque' using errcode = '22023'; end if;
  if j.uploaded + v_n > 200000 then raise exception 'Máximo 200 000 filas por importación' using errcode = '22023'; end if;

  with parsed as (
    select e.ord,
           left(btrim(coalesce(e.r ->> 'client', '')), 120) as client_name,
           left(nullif(btrim(coalesce(e.r ->> 'tax_id', '')), ''), 30) as client_tax_id,
           left(nullif(btrim(coalesce(e.r ->> 'description', '')), ''), 200) as description,
           case when (e.r ->> 'amount') ~ '^[0-9]{1,9}(\.[0-9]{1,4})?$' then (e.r ->> 'amount')::numeric(14,2) end as amount,
           case when upper(coalesce(e.r ->> 'currency', 'PEN')) ~ '^[A-Z]{3}$' then upper(coalesce(e.r ->> 'currency', 'PEN')) else 'PEN' end as currency,
           case when (e.r ->> 'date') ~ '^\d{4}-\d{2}-\d{2}$' then (e.r ->> 'date')::date end as issue_date,
           left(nullif(btrim(coalesce(e.r ->> 'number', '')), ''), 60) as doc_number
    from jsonb_array_elements(p_rows) with ordinality as e(r, ord)
  ), ins as (
    insert into public.import_rows (job_id, row_no, client_name, client_tax_id, description, amount, currency, issue_date, doc_number)
    select p_job, j.uploaded + p.ord::integer, p.client_name, p.client_tax_id, p.description, p.amount, p.currency, p.issue_date, p.doc_number
    from parsed p
    where p.amount is not null and p.amount > 0
    returning 1
  )
  select count(*) into v_ok from ins;

  update public.import_jobs
     set uploaded = uploaded + v_n, skipped = skipped + (v_n - v_ok), total = total + v_ok
   where id = p_job;
  return jsonb_build_object('accepted', v_ok, 'rejected', v_n - v_ok);
end;
$$;

-- 2) Terminada la subida: pasa a la cola. A partir de aquí la app puede cerrarse.
create or replace function private.import_start_impl(p_job uuid, p_tax_rate numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  j public.import_jobs;
begin
  select * into j from public.import_jobs where id = p_job for update;
  if not found or j.user_id is distinct from v_uid or not private.is_org_member(j.org_id) then
    raise exception 'Importación no encontrada' using errcode = '42501';
  end if;
  if j.status <> 'uploading' then return; end if;
  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then raise exception 'Tasa no válida' using errcode = '22023'; end if;
  if j.total = 0 then
    update public.import_jobs set status = 'failed', error = 'No hay filas válidas en el archivo', finished_at = now() where id = p_job;
    return;
  end if;
  update public.import_jobs set status = 'queued', tax_rate = p_tax_rate where id = p_job;
end;
$$;

-- 3) Un lote: convierte hasta p_batch filas en clientes + facturas (estado "paid": son históricas, no cuentas por cobrar).
create or replace function private.import_run_batch(p_job uuid, p_batch integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.import_jobs;
  v_ids bigint[];
  v_n integer;
  v_done integer := 0;
  v_nums text[] := '{}';
begin
  select * into j from public.import_jobs where id = p_job and status in ('queued', 'processing') for update skip locked;
  if not found then return null; end if;

  select coalesce(array_agg(s.id), '{}') into v_ids
  from (select id from public.import_rows
        where job_id = p_job and state = 'pending'
        order by id limit greatest(1, least(coalesce(p_batch, 500), 2000))
        for update skip locked) s;
  v_n := coalesce(array_length(v_ids, 1), 0);

  if v_n = 0 then
    delete from public.import_rows where job_id = p_job;  -- libera espacio: las facturas ya existen
    update public.import_jobs set status = 'done', finished_at = now(), processed = total where id = p_job;
    return jsonb_build_object('status', 'done', 'processed', j.total, 'total', j.total);
  end if;

  update public.import_jobs set status = 'processing' where id = p_job;

  -- Clientes nuevos (uno por nombre, sin repetir los que ya existen en la empresa)
  insert into public.clients (user_id, org_id, name, tax_id)
  select distinct on (lower(coalesce(nullif(r.client_name, ''), 'Cliente sin nombre')))
         j.user_id, j.org_id, coalesce(nullif(r.client_name, ''), 'Cliente sin nombre'), r.client_tax_id
  from public.import_rows r
  where r.id = any(v_ids)
    and not exists (select 1 from public.clients c
                    where c.org_id = j.org_id
                      and lower(btrim(c.name)) = lower(coalesce(nullif(r.client_name, ''), 'Cliente sin nombre')))
  order by lower(coalesce(nullif(r.client_name, ''), 'Cliente sin nombre')), r.id
  on conflict do nothing;

  with src as (
    select distinct on (private.import_number(p_job, r.row_no, r.doc_number))
           r.id, r.row_no, r.amount, r.currency, r.issue_date, r.description,
           coalesce(nullif(r.client_name, ''), 'Cliente sin nombre') as cname,
           private.import_number(p_job, r.row_no, r.doc_number) as number
    from public.import_rows r
    where r.id = any(v_ids)
    order by private.import_number(p_job, r.row_no, r.doc_number), r.id
  ), ins as (
    insert into public.invoices (user_id, org_id, client_id, number, issue_date, tax_rate, status, currency, notes)
    select j.user_id, j.org_id,
           (select c.id from public.clients c where c.org_id = j.org_id and lower(btrim(c.name)) = lower(s.cname) order by c.created_at limit 1),
           s.number, coalesce(s.issue_date, current_date), j.tax_rate, 'paid', s.currency, 'Importada'
    from src s
    on conflict (org_id, number) do nothing
    returning id, number
  ), items as (
    insert into public.invoice_items (user_id, invoice_id, description, quantity, unit_price, position)
    select j.user_id, ins.id, coalesce(s.description, 'Servicio importado'), 1,
           round(s.amount / (1 + j.tax_rate / 100), 2), 0
    from ins join src s on s.number = ins.number
    returning 1
  )
  select count(*), coalesce(array_agg(ins.number), '{}') into v_done, v_nums from ins;

  update public.import_rows r
     set state = case when private.import_number(p_job, r.row_no, r.doc_number) = any(v_nums) then 'done' else 'skipped' end
   where r.id = any(v_ids);

  update public.import_jobs
     set processed = processed + v_n, imported = imported + v_done, skipped = skipped + (v_n - v_done)
   where id = p_job;

  return jsonb_build_object('status', 'processing', 'processed', j.processed + v_n, 'total', j.total);
end;
$$;

-- Worker de fondo: sigue las importaciones aunque la app esté cerrada (lo llama pg_cron cada minuto).
create or replace function private.import_worker()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job uuid;
  v_started timestamptz := clock_timestamp();
  v_batches integer := 0;
  v_res jsonb;
begin
  for v_job in
    select id from public.import_jobs where status in ('queued', 'processing') order by created_at limit 5
  loop
    loop
      begin
        v_res := private.import_run_batch(v_job, 1000);
      exception when others then
        update public.import_jobs set status = 'failed', error = left(sqlerrm, 400), finished_at = now() where id = v_job;
        exit;
      end;
      v_batches := v_batches + 1;
      exit when v_res is null or v_res ->> 'status' = 'done' or clock_timestamp() - v_started > interval '40 seconds';
    end loop;
    exit when clock_timestamp() - v_started > interval '40 seconds';
  end loop;
  return v_batches;
end;
$$;

-- Envoltorios públicos (SECURITY INVOKER) que llama la app
create or replace function public.import_add_rows(p_job uuid, p_rows jsonb)
returns jsonb language sql security invoker set search_path = '' as $$ select private.import_add_rows_impl(p_job, p_rows) $$;

create or replace function public.import_start(p_job uuid, p_tax_rate numeric)
returns void language sql security invoker set search_path = '' as $$ select private.import_start_impl(p_job, p_tax_rate) $$;

-- La app puede acelerar su propia importación mientras está abierta (el worker cubre el resto).
create or replace function private.import_step_impl(p_job uuid, p_batch integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  j public.import_jobs;
begin
  select * into j from public.import_jobs where id = p_job;
  if not found or j.user_id is distinct from v_uid or not private.is_org_member(j.org_id) then
    raise exception 'Importación no encontrada' using errcode = '42501';
  end if;
  return private.import_run_batch(p_job, p_batch);
end;
$$;
create or replace function public.import_step(p_job uuid, p_batch integer default 500)
returns jsonb language sql security invoker set search_path = '' as $$ select private.import_step_impl(p_job, p_batch) $$;

create or replace function private.import_cancel_impl(p_job uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  update public.import_jobs set status = 'cancelled', finished_at = now()
   where id = p_job and user_id = v_uid and status in ('uploading', 'queued', 'processing');
  delete from public.import_rows where job_id = p_job
    and exists (select 1 from public.import_jobs where id = p_job and user_id = v_uid and status = 'cancelled');
end;
$$;
create or replace function public.import_cancel(p_job uuid)
returns void language sql security invoker set search_path = '' as $$ select private.import_cancel_impl(p_job) $$;

revoke execute on function private.import_add_rows_impl(uuid, jsonb), private.import_start_impl(uuid, numeric),
  private.import_step_impl(uuid, integer), private.import_cancel_impl(uuid), private.import_run_batch(uuid, integer),
  private.import_worker(), private.import_number(uuid, integer, text) from public, anon;
grant execute on function private.import_add_rows_impl(uuid, jsonb), private.import_start_impl(uuid, numeric),
  private.import_step_impl(uuid, integer), private.import_cancel_impl(uuid), private.import_number(uuid, integer, text) to authenticated;
revoke execute on function public.import_add_rows(uuid, jsonb), public.import_start(uuid, numeric),
  public.import_step(uuid, integer), public.import_cancel(uuid) from public, anon;
grant execute on function public.import_add_rows(uuid, jsonb), public.import_start(uuid, numeric),
  public.import_step(uuid, integer), public.import_cancel(uuid) to authenticated;

-- Tiempo real: la barra de progreso y los totales se actualizan solos.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'import_jobs') then
      alter publication supabase_realtime add table public.import_jobs;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'invoices') then
      alter publication supabase_realtime add table public.invoices;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'payments') then
      alter publication supabase_realtime add table public.payments;
    end if;
  end if;
end $$;

-- Worker cada minuto con pg_cron (actívalo en Supabase: Integrations → Cron). Si no está disponible, no pasa nada:
-- la app igual avanza la importación mientras está abierta.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'facturavoz-import-worker';
    perform cron.schedule('facturavoz-import-worker', '* * * * *', 'select private.import_worker()');
  else
    raise notice 'pg_cron no está activado: activa la extensión y vuelve a ejecutar este archivo para el procesamiento en segundo plano.';
  end if;
exception when others then
  raise notice 'No se pudo programar el worker: %', sqlerrm;
end $$;
