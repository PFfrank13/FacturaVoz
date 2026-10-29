-- FacturaVoz · Migración 15 · CRM dentro de la app (Fase 1)
-- Ficha de cliente 360 (contacto, ubicación, etiquetas, notas, equipos, fotos), trabajos con estados
-- configurables por negocio, agenda (visitas, citas, instalaciones), hitos de cobro por avance y
-- avisos del día. Todo con RLS por empresa. Idempotente y aditiva. Ejecutar después de 20261105.
begin;

-- ───────────── Configuración del negocio (tipo, modo simple, módulos, estados, textos) ─────────────
create table if not exists public.org_settings (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  business_type text not null default 'otro',
  simple_mode boolean not null default true,
  modules jsonb not null default '{}'::jsonb,
  job_statuses jsonb not null default '[]'::jsonb,
  client_fields jsonb not null default '[]'::jsonb,
  labels jsonb not null default '{}'::jsonb,
  onboarding_done boolean not null default false,
  loyalty_rate numeric(8,4) not null default 0,
  birthday_greetings boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint org_settings_chk check (
    business_type in ('bodega', 'restaurante', 'servicios_tecnicos', 'salon', 'consultorio', 'taller', 'mayorista',
                      'educacion', 'construccion', 'otro')
    and jsonb_typeof(modules) = 'object' and jsonb_typeof(job_statuses) = 'array'
    and jsonb_typeof(client_fields) = 'array' and jsonb_typeof(labels) = 'object'
    and pg_column_size(job_statuses) < 8000 and pg_column_size(client_fields) < 8000
    and pg_column_size(labels) < 4000 and pg_column_size(modules) < 4000
    and loyalty_rate between 0 and 100)
);
alter table public.org_settings enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'org_settings' and policyname = 'org_settings_select') then
    create policy "org_settings_select" on public.org_settings for select to authenticated using (private.is_org_member(org_id));
    create policy "org_settings_insert" on public.org_settings for insert to authenticated with check (private.is_org_admin(org_id));
    create policy "org_settings_update" on public.org_settings for update to authenticated using (private.is_org_admin(org_id)) with check (private.is_org_admin(org_id));
  end if;
end $$;
revoke all on public.org_settings from anon, authenticated;
grant select on public.org_settings to authenticated;
grant insert (org_id, business_type, simple_mode, modules, job_statuses, client_fields, labels, onboarding_done, loyalty_rate, birthday_greetings, updated_at)
  on public.org_settings to authenticated;
grant update (org_id, business_type, simple_mode, modules, job_statuses, client_fields, labels, onboarding_done, loyalty_rate, birthday_greetings, updated_at)
  on public.org_settings to authenticated;

-- ───────────── Clientes: ficha completa ─────────────
alter table public.clients
  add column if not exists phone text,
  add column if not exists district text,
  add column if not exists reference text,
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists tags text[] not null default '{}',
  add column if not exists source text,
  add column if not exists birthday date,
  add column if not exists notes text,
  add column if not exists credit_limit numeric(14,2),
  add column if not exists extra jsonb not null default '{}'::jsonb,
  add column if not exists last_contact_at timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_crm_chk') then
    alter table public.clients add constraint clients_crm_chk check (
      (phone is null or char_length(phone) <= 30)
      and (district is null or char_length(district) <= 80)
      and (reference is null or char_length(reference) <= 200)
      and (lat is null or lat between -90 and 90) and (lng is null or lng between -180 and 180)
      and cardinality(tags) <= 20
      and (source is null or source in ('whatsapp', 'referido', 'web', 'tienda', 'llamada', 'redes', 'paso', 'otro'))
      and (notes is null or char_length(notes) <= 2000)
      and (credit_limit is null or credit_limit between 0 and 100000000)
      and jsonb_typeof(extra) = 'object' and pg_column_size(extra) < 4000);
  end if;
end $$;
create index if not exists idx_clients_org_name on public.clients(org_id, lower(name));
create index if not exists idx_clients_tags on public.clients using gin(tags);

create table if not exists public.client_notes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  kind text not null default 'nota' check (kind in ('nota', 'llamada', 'whatsapp', 'visita', 'correo')),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists idx_client_notes_client on public.client_notes(client_id, created_at desc);
create index if not exists idx_client_notes_org on public.client_notes(org_id);
create index if not exists idx_client_notes_user on public.client_notes(user_id);

create table if not exists public.client_assets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  job_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  model text check (model is null or char_length(model) <= 120),
  serial text check (serial is null or char_length(serial) <= 120),
  installed_on date,
  warranty_until date,
  notes text check (notes is null or char_length(notes) <= 1000),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_client_assets_client on public.client_assets(client_id);
create index if not exists idx_client_assets_org on public.client_assets(org_id);
create index if not exists idx_client_assets_serial on public.client_assets(org_id, serial);

-- ───────────── Trabajos (visitas, instalaciones, servicios, citas, obras) ─────────────
create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  title text not null check (char_length(btrim(title)) between 1 and 140),
  kind text not null default 'servicio' check (kind in ('visita', 'instalacion', 'servicio', 'reparacion', 'cita', 'obra', 'pedido', 'clase', 'otro')),
  status text not null default 'nuevo' check (status ~ '^[a-z0-9_]{1,30}$'),
  source text check (source is null or source in ('whatsapp', 'referido', 'web', 'tienda', 'llamada', 'redes', 'paso', 'otro')),
  assigned_to uuid references auth.users(id) on delete set null,
  scheduled_at timestamptz,
  duration_min integer check (duration_min is null or duration_min between 5 and 1440),
  address text check (address is null or char_length(address) <= 300),
  lat double precision check (lat is null or lat between -90 and 90),
  lng double precision check (lng is null or lng between -180 and 180),
  contact_phone text check (contact_phone is null or char_length(contact_phone) <= 30),
  notes text check (notes is null or char_length(notes) <= 2000),
  tech_note text check (tech_note is null or char_length(tech_note) <= 2000),
  amount numeric(14,2) check (amount is null or amount between 0 and 100000000),
  quote_id uuid references public.quotes(id) on delete set null,
  invoice_id uuid references public.invoices(id) on delete set null,
  recurring_id uuid references public.recurring_invoices(id) on delete set null,
  extra jsonb not null default '{}'::jsonb check (jsonb_typeof(extra) = 'object' and pg_column_size(extra) < 4000),
  position integer not null default 0,
  reminder_sent_at timestamptz,
  done_at timestamptz,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_jobs_org_status on public.jobs(org_id, status, position);
create index if not exists idx_jobs_org_sched on public.jobs(org_id, scheduled_at);
create index if not exists idx_jobs_client on public.jobs(client_id);
create index if not exists idx_jobs_assigned on public.jobs(assigned_to, scheduled_at);
create index if not exists idx_jobs_quote on public.jobs(quote_id);
create index if not exists idx_jobs_invoice on public.jobs(invoice_id);
create index if not exists idx_jobs_recurring on public.jobs(recurring_id);
create index if not exists idx_jobs_created_by on public.jobs(created_by);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_assets_job_fk') then
    alter table public.client_assets add constraint client_assets_job_fk foreign key (job_id) references public.jobs(id) on delete set null;
  end if;
end $$;
create index if not exists idx_client_assets_job on public.client_assets(job_id);

create table if not exists public.job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.jobs(id) on delete cascade,
  org_id uuid not null references public.organizations(id) on delete cascade,
  from_status text,
  to_status text,
  note text check (note is null or char_length(note) <= 500),
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_job_events_job on public.job_events(job_id, created_at);
create index if not exists idx_job_events_org on public.job_events(org_id);
create index if not exists idx_job_events_user on public.job_events(user_id);

create table if not exists public.job_materials (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  org_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  description text not null check (char_length(btrim(description)) between 1 and 200),
  quantity numeric(12,2) not null check (quantity > 0 and quantity <= 100000),
  unit_price numeric(12,2) not null default 0 check (unit_price >= 0),
  discounted boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_job_materials_job on public.job_materials(job_id);
create index if not exists idx_job_materials_org on public.job_materials(org_id);
create index if not exists idx_job_materials_product on public.job_materials(product_id);

-- Fotos y archivos (antes/después, documentos) de un trabajo o de un cliente. El archivo vive en Storage (org-media).
create table if not exists public.media_files (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid references public.clients(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete cascade,
  kind text not null default 'foto' check (kind in ('foto', 'antes', 'despues', 'documento')),
  path text not null check (char_length(path) between 3 and 300),
  caption text check (caption is null or char_length(caption) <= 200),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (client_id is not null or job_id is not null)
);
create index if not exists idx_media_files_job on public.media_files(job_id);
create index if not exists idx_media_files_client on public.media_files(client_id);
create index if not exists idx_media_files_org on public.media_files(org_id);
create index if not exists idx_media_files_created_by on public.media_files(created_by);

-- Cobro por avance (obras, instalaciones grandes, proyectos): hitos con monto y fecha.
create table if not exists public.job_milestones (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  org_id uuid not null references public.organizations(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 140),
  amount numeric(14,2) not null check (amount > 0 and amount <= 100000000),
  due_date date,
  status text not null default 'pendiente' check (status in ('pendiente', 'listo', 'facturado')),
  invoice_id uuid references public.invoices(id) on delete set null,
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_job_milestones_job on public.job_milestones(job_id, position);
create index if not exists idx_job_milestones_org on public.job_milestones(org_id);
create index if not exists idx_job_milestones_invoice on public.job_milestones(invoice_id);

-- ───────────── RLS (miembros de la empresa; borrar: admin o quien lo creó) ─────────────
alter table public.client_notes enable row level security;
alter table public.client_assets enable row level security;
alter table public.jobs enable row level security;
alter table public.job_events enable row level security;
alter table public.job_materials enable row level security;
alter table public.media_files enable row level security;
alter table public.job_milestones enable row level security;

do $$
declare t text;
begin
  foreach t in array array['client_notes', 'client_assets', 'jobs', 'job_materials', 'media_files', 'job_milestones'] loop
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_select') then
      execute format('create policy %I on public.%I for select to authenticated using (private.is_org_member(org_id))', t || '_select', t);
      execute format('create policy %I on public.%I for insert to authenticated with check (private.is_org_member(org_id))', t || '_insert', t);
      execute format('create policy %I on public.%I for update to authenticated using (private.is_org_member(org_id)) with check (private.is_org_member(org_id))', t || '_update', t);
    end if;
  end loop;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'job_events' and policyname = 'job_events_select') then
    create policy "job_events_select" on public.job_events for select to authenticated using (private.is_org_member(org_id));
  end if;
  -- Borrar
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'client_notes' and policyname = 'client_notes_delete') then
    create policy "client_notes_delete" on public.client_notes for delete to authenticated
      using (private.is_org_admin(org_id) or (user_id = (select auth.uid()) and private.is_org_member(org_id)));
    create policy "client_assets_delete" on public.client_assets for delete to authenticated
      using (private.is_org_admin(org_id) or (created_by = (select auth.uid()) and private.is_org_member(org_id)));
    create policy "jobs_delete" on public.jobs for delete to authenticated
      using (private.is_org_admin(org_id) or (created_by = (select auth.uid()) and private.is_org_member(org_id)));
    create policy "job_materials_delete" on public.job_materials for delete to authenticated
      using (private.is_org_member(org_id) and not discounted);
    create policy "media_files_delete" on public.media_files for delete to authenticated
      using (private.is_org_admin(org_id) or (created_by = (select auth.uid()) and private.is_org_member(org_id)));
    create policy "job_milestones_delete" on public.job_milestones for delete to authenticated
      using (private.is_org_member(org_id) and status <> 'facturado');
  end if;
end $$;

revoke all on public.client_notes, public.client_assets, public.jobs, public.job_events, public.job_materials,
  public.media_files, public.job_milestones from anon, authenticated;
grant select, insert, delete on public.client_notes to authenticated;
grant select, insert, update, delete on public.client_assets, public.media_files to authenticated;
grant select, insert, delete on public.jobs, public.job_materials, public.job_milestones to authenticated;
grant update (client_id, title, kind, status, source, assigned_to, scheduled_at, duration_min, address, lat, lng, contact_phone,
              notes, tech_note, amount, quote_id, invoice_id, recurring_id, extra, position, updated_at)
  on public.jobs to authenticated;
grant update (description, quantity, unit_price) on public.job_materials to authenticated;
grant update (title, amount, due_date, status, position, invoice_id) on public.job_milestones to authenticated;
grant select on public.job_events to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- ───────────── Disparadores: historial de estados y "último contacto" ─────────────
create or replace function private.jobs_track()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.job_events (job_id, org_id, from_status, to_status, user_id) values (new.id, new.org_id, null, new.status, (select auth.uid()));
    return new;
  end if;
  if new.org_id is distinct from old.org_id then
    raise exception 'No se puede mover un trabajo a otra empresa' using errcode = '42501';
  end if;
  new.updated_at := now();
  if new.status is distinct from old.status then
    insert into public.job_events (job_id, org_id, from_status, to_status, user_id) values (new.id, new.org_id, old.status, new.status, (select auth.uid()));
    -- "terminado" según los estados configurados del negocio (o claves estándar)
    if exists (
      select 1 from public.org_settings s, jsonb_array_elements(s.job_statuses) e
      where s.org_id = new.org_id and e ->> 'key' = new.status and coalesce((e ->> 'done')::boolean, false)
    ) or new.status in ('terminado', 'instalado', 'entregado', 'cobrado', 'atendido', 'listo') then
      new.done_at := coalesce(new.done_at, now());
    else
      new.done_at := null;
    end if;
  end if;
  return new;
end;
$$;
create or replace trigger jobs_track_ins after insert on public.jobs for each row execute function private.jobs_track();
create or replace trigger jobs_track_upd before update on public.jobs for each row execute function private.jobs_track();

create or replace function private.client_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.clients set last_contact_at = now() where id = new.client_id and org_id = new.org_id;
  return new;
end;
$$;
create or replace trigger client_notes_touch after insert on public.client_notes for each row execute function private.client_touch();

-- Coherencia: el cliente/trabajo referenciado debe ser de la misma empresa.
create or replace function private.same_org_refs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_org uuid := (v_new ->> 'org_id')::uuid;
  v_client uuid := (v_new ->> 'client_id')::uuid;
  v_job uuid := (v_new ->> 'job_id')::uuid;
  v_product uuid := (v_new ->> 'product_id')::uuid;
  v_assigned uuid := (v_new ->> 'assigned_to')::uuid;
  v_ref uuid;
begin
  if v_client is not null then
    select c.org_id into v_ref from public.clients c where c.id = v_client;
    if v_ref is distinct from v_org then raise exception 'Cliente de otra empresa' using errcode = '42501'; end if;
  end if;
  if v_job is not null then
    select j.org_id into v_ref from public.jobs j where j.id = v_job;
    if v_ref is distinct from v_org then raise exception 'Trabajo de otra empresa' using errcode = '42501'; end if;
  end if;
  if v_product is not null then
    select p.org_id into v_ref from public.products p where p.id = v_product;
    if v_ref is distinct from v_org then raise exception 'Producto de otra empresa' using errcode = '42501'; end if;
  end if;
  if v_assigned is not null
     and not exists (select 1 from public.organization_members m where m.org_id = v_org and m.user_id = v_assigned) then
    raise exception 'La persona asignada no es del equipo' using errcode = '42501';
  end if;
  return new;
end;
$$;
do $$
declare t text;
begin
  foreach t in array array['client_notes', 'client_assets', 'jobs', 'job_materials', 'media_files', 'job_milestones'] loop
    execute format('create or replace trigger %I before insert or update on public.%I for each row execute function private.same_org_refs()', t || '_same_org', t);
  end loop;
end $$;

-- ───────────── Descontar materiales del stock al terminar una instalación ─────────────
create or replace function private.job_consume_impl(p_job uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.jobs;
  v_n integer := 0;
  m record;
begin
  select * into j from public.jobs where id = p_job;
  if not found or not private.is_org_member(j.org_id) then raise exception 'Trabajo no encontrado' using errcode = '42501'; end if;
  for m in select * from public.job_materials where job_id = p_job and not discounted for update loop
    if m.product_id is not null then
      update public.products set stock = stock - m.quantity where id = m.product_id and org_id = j.org_id and stock is not null;
    end if;
    update public.job_materials set discounted = true where id = m.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
revoke execute on function private.job_consume_impl(uuid) from public, anon;
grant execute on function private.job_consume_impl(uuid) to authenticated;
create or replace function public.job_consume_materials(p_job uuid)
returns integer language sql security invoker set search_path = '' as $$ select private.job_consume_impl(p_job) $$;
revoke execute on function public.job_consume_materials(uuid) from public, anon;
grant execute on function public.job_consume_materials(uuid) to authenticated;

-- ───────────── Avisos del día (recordatorios inteligentes de seguimiento) ─────────────
-- Devuelve una lista de avisos: visitas de hoy/mañana, trabajos atrasados, clientes a los que no se les escribe
-- hace 30+ días (que sí compran), cumpleaños de hoy. Lo usa la pantalla de Inicio (y el Copiloto).
create or replace function public.daily_alerts(p_org uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'America/Lima')::date;
  v_out jsonb := '[]'::jsonb;
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;

  -- Agenda de hoy y mañana
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object(
      'kind', case when (j.scheduled_at at time zone 'America/Lima')::date = v_today then 'visit_today' else 'visit_tomorrow' end,
      'job_id', j.id, 'title', j.title, 'client', c.name, 'phone', coalesce(j.contact_phone, c.phone),
      'at', j.scheduled_at, 'address', j.address) order by j.scheduled_at)
    from public.jobs j left join public.clients c on c.id = j.client_id
    where j.org_id = p_org and j.done_at is null
      and (j.scheduled_at at time zone 'America/Lima')::date between v_today and v_today + 1), '[]'::jsonb);

  -- Trabajos atrasados (agenda pasada y sin terminar)
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'job_late', 'job_id', j.id, 'title', j.title, 'client', c.name, 'at', j.scheduled_at) order by j.scheduled_at)
    from (select * from public.jobs where org_id = p_org and done_at is null
            and (scheduled_at at time zone 'America/Lima')::date < v_today
            and scheduled_at > now() - interval '60 days' order by scheduled_at limit 10) j
    left join public.clients c on c.id = j.client_id), '[]'::jsonb);

  -- Clientes que compran pero a quienes no se les escribe hace 30+ días
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'no_contact', 'client_id', x.id, 'client', x.name, 'phone', x.phone, 'days', x.days) order by x.days desc)
    from (
      select c.id, c.name, c.phone,
             (v_today - greatest(coalesce((c.last_contact_at at time zone 'America/Lima')::date, '1900-01-01'), max(i.issue_date))) as days
      from public.clients c join public.invoices i on i.client_id = c.id and i.status <> 'draft'
      where c.org_id = p_org
      group by c.id
      having count(i.id) >= 2
         and v_today - greatest(coalesce((c.last_contact_at at time zone 'America/Lima')::date, '1900-01-01'), max(i.issue_date)) between 30 and 365
      order by 4 desc limit 5) x), '[]'::jsonb);

  -- Cumpleaños de hoy
  v_out := v_out || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'birthday', 'client_id', c.id, 'client', c.name, 'phone', c.phone))
    from public.clients c
    where c.org_id = p_org and c.birthday is not null
      and extract(month from c.birthday) = extract(month from v_today) and extract(day from c.birthday) = extract(day from v_today)), '[]'::jsonb);

  return v_out;
end;
$$;
revoke execute on function public.daily_alerts(uuid) from public, anon;
grant execute on function public.daily_alerts(uuid) to authenticated;

-- ───────────── Tiempo real ─────────────
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['jobs', 'client_notes', 'org_settings'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

grant select, insert, update, delete on public.org_settings, public.client_notes, public.client_assets, public.jobs,
  public.job_events, public.job_materials, public.media_files, public.job_milestones to service_role;

commit;

notify pgrst, 'reload schema';
