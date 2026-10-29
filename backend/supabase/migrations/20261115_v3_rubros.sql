-- FacturaVoz v3 · B Rubros: tablas para las funciones propias de cada tipo de negocio.
--   service_packages  · paquetes/sesiones prepagadas (salón, consultorio, academia)
--   service_reminders · recordatorios de volver (mantenimiento del taller, control del consultorio, retoque del salón)
--   private_notes     · historial PRIVADO por cliente/paciente (solo quien lo escribe y el dueño/admin; dato sensible)
--   expenses.job_id   · gastos y subcontratistas por obra (margen por obra en construcción)
-- Aditiva e idempotente. Requiere 20261114.
begin;

-- Gastos por obra / trabajo
alter table public.expenses add column if not exists job_id uuid references public.jobs(id) on delete set null;
create index if not exists idx_expenses_job on public.expenses(job_id) where job_id is not null;
grant update (job_id) on public.expenses to authenticated;

-- ───────────── Paquetes y sesiones ─────────────
create table if not exists public.service_packages (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations(id) on delete cascade,
  client_id      uuid not null references public.clients(id) on delete cascade,
  name           text not null check (char_length(btrim(name)) between 1 and 120),
  sessions_total integer not null check (sessions_total between 1 and 500),
  sessions_used  integer not null default 0 check (sessions_used >= 0),
  price          numeric(14,2) check (price is null or price between 0 and 10000000),
  invoice_id     uuid references public.invoices(id) on delete set null,
  expires_on     date,
  created_by     uuid default auth.uid() references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  constraint service_packages_used_chk check (sessions_used <= sessions_total)
);
create index if not exists idx_service_packages_org on public.service_packages(org_id, created_at desc);
create index if not exists idx_service_packages_client on public.service_packages(client_id);
create index if not exists idx_service_packages_invoice on public.service_packages(invoice_id);
create index if not exists idx_service_packages_created_by on public.service_packages(created_by);
alter table public.service_packages enable row level security;
drop policy if exists "service_packages_select" on public.service_packages;
create policy "service_packages_select" on public.service_packages for select to authenticated
  using (org_id = any ((select private.my_org_ids())::uuid[]));
drop policy if exists "service_packages_insert" on public.service_packages;
create policy "service_packages_insert" on public.service_packages for insert to authenticated
  with check (org_id = any ((select private.my_org_ids())::uuid[]) and sessions_used = 0
              and exists (select 1 from public.clients c where c.id = client_id and c.org_id = service_packages.org_id));
drop policy if exists "service_packages_delete" on public.service_packages;
create policy "service_packages_delete" on public.service_packages for delete to authenticated
  using (org_id = any ((select private.my_admin_org_ids())::uuid[]));
revoke all on public.service_packages from anon, authenticated;
grant select, insert, delete on public.service_packages to authenticated;
grant update (name, expires_on, price, invoice_id) on public.service_packages to authenticated;
drop policy if exists "service_packages_update" on public.service_packages;
create policy "service_packages_update" on public.service_packages for update to authenticated
  using (org_id = any ((select private.my_org_ids())::uuid[])) with check (org_id = any ((select private.my_org_ids())::uuid[]));

-- Usar una sesión (atómico; nunca pasa del total; nadie puede "devolver" sesiones a mano). Devuelve las que quedan.
create or replace function private.use_package_session_impl(p_package uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer;
  v_org uuid;
begin
  select org_id into v_org from public.service_packages where id = p_package;
  if v_org is null or not private.is_org_member(v_org) then raise exception 'Paquete no encontrado' using errcode = '42501'; end if;
  update public.service_packages set sessions_used = sessions_used + 1
   where id = p_package and sessions_used < sessions_total and (expires_on is null or expires_on >= private.today_pe())
  returning sessions_total - sessions_used into v_left;
  if v_left is null then raise exception 'Este paquete ya no tiene sesiones disponibles o venció' using errcode = '22023'; end if;
  perform private.audit(v_org, 'paquete.sesion', 'service_packages', p_package::text, jsonb_build_object('quedan', v_left));
  return v_left;
end;
$$;
create or replace function public.use_package_session(p_package uuid)
returns integer language sql security invoker set search_path = '' as $$ select private.use_package_session_impl(p_package) $$;
revoke execute on function private.use_package_session_impl(uuid), public.use_package_session(uuid) from public, anon;
grant execute on function private.use_package_session_impl(uuid), public.use_package_session(uuid) to authenticated;

-- ───────────── Recordatorios de volver ─────────────
create table if not exists public.service_reminders (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  client_id  uuid not null references public.clients(id) on delete cascade,
  asset_id   uuid references public.client_assets(id) on delete set null,   -- vehículo o equipo
  due_on     date not null,
  title      text not null check (char_length(btrim(title)) between 1 and 140),
  note       text check (note is null or char_length(note) <= 500),
  done_at    timestamptz,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_service_reminders_due on public.service_reminders(org_id, due_on) where done_at is null;
create index if not exists idx_service_reminders_client on public.service_reminders(client_id);
create index if not exists idx_service_reminders_asset on public.service_reminders(asset_id);
create index if not exists idx_service_reminders_created_by on public.service_reminders(created_by);
alter table public.service_reminders enable row level security;
drop policy if exists "service_reminders_select" on public.service_reminders;
create policy "service_reminders_select" on public.service_reminders for select to authenticated
  using (org_id = any ((select private.my_org_ids())::uuid[]));
drop policy if exists "service_reminders_write" on public.service_reminders;
create policy "service_reminders_write" on public.service_reminders for insert to authenticated
  with check (org_id = any ((select private.my_org_ids())::uuid[])
              and exists (select 1 from public.clients c where c.id = client_id and c.org_id = service_reminders.org_id));
drop policy if exists "service_reminders_update" on public.service_reminders;
create policy "service_reminders_update" on public.service_reminders for update to authenticated
  using (org_id = any ((select private.my_org_ids())::uuid[])) with check (org_id = any ((select private.my_org_ids())::uuid[]));
drop policy if exists "service_reminders_delete" on public.service_reminders;
create policy "service_reminders_delete" on public.service_reminders for delete to authenticated
  using (created_by = (select auth.uid()) or org_id = any ((select private.my_admin_org_ids())::uuid[]));
revoke all on public.service_reminders from anon, authenticated;
grant select, insert, delete on public.service_reminders to authenticated;
grant update (due_on, title, note, done_at) on public.service_reminders to authenticated;

-- ───────────── Historial privado (dato sensible: Ley 29733) ─────────────
-- Solo lo ve quien lo escribió y el dueño/administrador. NO lo lee el Copiloto ni sale en reportes ni exportaciones.
create table if not exists public.private_notes (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  client_id  uuid not null references public.clients(id) on delete cascade,
  author_id  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists idx_private_notes_client on public.private_notes(client_id, created_at desc);
create index if not exists idx_private_notes_org on public.private_notes(org_id);
create index if not exists idx_private_notes_author on public.private_notes(author_id);
alter table public.private_notes enable row level security;
drop policy if exists "private_notes_select" on public.private_notes;
create policy "private_notes_select" on public.private_notes for select to authenticated
  using (org_id = any ((select private.my_org_ids())::uuid[])
         and (author_id = (select auth.uid()) or org_id = any ((select private.my_admin_org_ids())::uuid[])));
drop policy if exists "private_notes_insert" on public.private_notes;
create policy "private_notes_insert" on public.private_notes for insert to authenticated
  with check (author_id = (select auth.uid()) and org_id = any ((select private.my_org_ids())::uuid[])
              and org_id <> all ((select private.my_tech_org_ids())::uuid[])
              and exists (select 1 from public.clients c where c.id = client_id and c.org_id = private_notes.org_id));
drop policy if exists "private_notes_delete" on public.private_notes;
create policy "private_notes_delete" on public.private_notes for delete to authenticated
  using (author_id = (select auth.uid()) or org_id = any ((select private.my_admin_org_ids())::uuid[]));
revoke all on public.private_notes from anon, authenticated;
grant select, insert, delete on public.private_notes to authenticated;  -- sin UPDATE: una nota no se reescribe (se agrega otra)

-- ───────────── Planes × rubro (C) ─────────────
-- Núcleo del rubro: lo que TODO plan incluye para ese tipo de negocio (sin esto el rubro no funciona).
-- Ej.: un salón en plan Básico tiene agenda; un taller tiene órdenes de trabajo. La app usa la misma tabla (rubros.dart).
create or replace function private.rubro_core(p_type text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case p_type
    when 'bodega' then array['stock', 'fiados', 'caja', 'avisos_pago']
    when 'restaurante' then array['carta_qr', 'caja', 'stock']
    when 'servicios_tecnicos' then array['trabajos', 'agenda', 'recurrentes']
    when 'salon' then array['agenda', 'caja']
    when 'consultorio' then array['agenda']
    when 'taller' then array['trabajos', 'cotizaciones', 'stock']
    when 'mayorista' then array['cotizaciones', 'stock', 'precios']
    when 'educacion' then array['recurrentes', 'agenda']
    when 'construccion' then array['trabajos', 'cotizaciones']
    else array[]::text[] end
$$;

create or replace function private.has_feature(p_org uuid, p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
  f jsonb;
  v_src text;
begin
  if not private.license_enforced() then return true; end if;
  if p_key in ('facturar', 'clientes', 'cobros', 'voz') then return true; end if;
  select l.features, l.source into f, v_src from public.org_licenses l where l.org_id = p_org;
  if f is null then return false; end if;
  if v_src in ('local', 'dev') then return true; end if; -- prueba local: acceso total
  -- Núcleo del rubro: incluido en todos los planes
  if p_key = any(private.rubro_core((select s.business_type from public.org_settings s where s.org_id = p_org))) then return true; end if;
  v := f -> p_key;
  return case jsonb_typeof(v) when 'boolean' then v::text = 'true' when 'number' then (v::text)::numeric <> 0 else false end;
end;
$$;
revoke execute on function private.rubro_core(text) from public, anon;
grant execute on function private.rubro_core(text) to authenticated, service_role;

-- Licencias (lectura en modo restringido / bloqueo de escritura) para las tablas nuevas
select private.install_license_guards();

commit;

notify pgrst, 'reload schema';
