-- FacturaVoz · Migración 16 · Equipo, roles y acceso de empleados (Fase 2)
--
-- Roles efectivos por empresa:
--   owner / admin  → todo (como antes).
--   finanzas       → vende, cobra, ve gastos, rentabilidad, conciliación, importación. No equipo ni licencias.
--   cajero         → vende, cobra, clientes, cotizaciones, caja. NO ve gastos ni rentabilidad.
--   vendedor       → igual que cajero (pensado para vendedores en calle y comisiones).
--   tecnico        → SOLO sus trabajos/agenda asignados y los clientes de esos trabajos; no ve ventas de otros.
-- Los integrantes antiguos ('member' sin rol específico) se tratan como 'cajero' (operan, pero no ven gastos).
--
-- Los permisos se aplican EN LA BASE DE DATOS con políticas RLS RESTRICTIVAS (se suman a las existentes con AND):
-- ocultar un botón no basta, y no se reemplaza ninguna política anterior (sin DROP).
--
-- Invitaciones: el administrador registra el correo y el rol del empleado. Si esa persona ya tiene cuenta entra
-- de inmediato; si no, al crear su cuenta (o al iniciar sesión con "Iniciar con Empresa") queda unida a la
-- empresa con el rol indicado, sin crear una empresa propia.
-- Idempotente y aditiva. Ejecutar después de 20261106.
begin;

-- ───────────── Columnas del integrante ─────────────
alter table public.organization_members
  add column if not exists staff_role text,
  add column if not exists display_name text,
  add column if not exists commission_pct numeric(5,2),
  add column if not exists sales_goal numeric(14,2),
  add column if not exists welcomed_at timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'organization_members_staff_chk') then
    alter table public.organization_members add constraint organization_members_staff_chk check (
      (staff_role is null or staff_role in ('finanzas', 'cajero', 'tecnico', 'vendedor'))
      and (display_name is null or char_length(display_name) <= 80)
      and (commission_pct is null or commission_pct between 0 and 100)
      and (sales_goal is null or sales_goal between 0 and 1000000000));
  end if;
end $$;

-- ───────────── Invitaciones ─────────────
create table if not exists public.org_invites (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  email text not null check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 200),
  role text not null default 'member' check (role in ('admin', 'member')),
  staff_role text check (staff_role is null or staff_role in ('finanzas', 'cajero', 'tecnico', 'vendedor')),
  display_name text check (display_name is null or char_length(display_name) <= 80),
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id) on delete set null
);
create unique index if not exists org_invites_pending_key on public.org_invites(org_id, lower(email)) where accepted_at is null;
create index if not exists idx_org_invites_email on public.org_invites(lower(email)) where accepted_at is null;
create index if not exists idx_org_invites_invited_by on public.org_invites(invited_by);
create index if not exists idx_org_invites_accepted_by on public.org_invites(accepted_by);
alter table public.org_invites enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'org_invites' and policyname = 'org_invites_select') then
    create policy "org_invites_select" on public.org_invites for select to authenticated using (private.is_org_admin(org_id));
    create policy "org_invites_delete" on public.org_invites for delete to authenticated using (private.is_org_admin(org_id) and accepted_at is null);
  end if;
end $$;
revoke all on public.org_invites from anon, authenticated;
grant select, delete on public.org_invites to authenticated;
grant select, insert, update, delete on public.org_invites to service_role;

-- ───────────── Rol efectivo y permisos ─────────────
create or replace function private.org_role(p_org uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when m.role in ('owner', 'admin') then m.role else coalesce(m.staff_role, 'cajero') end
  from public.organization_members m where m.org_id = p_org and m.user_id = (select auth.uid());
$$;

-- ¿Puede ver dinero de la empresa (gastos, rentabilidad, conciliación, recurrentes)?
create or replace function private.can_finance(p_org uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(private.org_role(p_org) in ('owner', 'admin', 'finanzas'), false); $$;

-- ¿Es técnico? (los técnicos solo ven lo suyo)
create or replace function private.is_tech(p_org uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(private.org_role(p_org) = 'tecnico', false); $$;

-- Cliente visible para un técnico: tiene un trabajo asignado a él (o creado por él), o él creó el cliente.
create or replace function private.tech_sees_client(p_client uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.jobs j where j.client_id = p_client
                   and (j.assigned_to = (select auth.uid()) or j.created_by = (select auth.uid())))
      or exists (select 1 from public.clients c where c.id = p_client and c.user_id = (select auth.uid()));
$$;

create or replace function private.tech_sees_job(p_job uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.jobs j where j.id = p_job
                   and (j.assigned_to = (select auth.uid()) or j.created_by = (select auth.uid())));
$$;

-- Límite de usuarios por empresa (la Fase 5 lo conecta con el plan contratado; -1 = sin límite).
create or replace function private.max_users(p_org uuid)
returns integer language sql stable security definer set search_path = ''
as $$ select -1; $$;

revoke execute on function private.org_role(uuid), private.can_finance(uuid), private.is_tech(uuid),
  private.tech_sees_client(uuid), private.tech_sees_job(uuid), private.max_users(uuid) from public, anon;
grant execute on function private.org_role(uuid), private.can_finance(uuid), private.is_tech(uuid),
  private.tech_sees_client(uuid), private.tech_sees_job(uuid), private.max_users(uuid) to authenticated, service_role;

-- ───────────── Políticas RESTRICTIVAS por rol ─────────────
do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- (tabla, nombre, comando, using, with_check)
      ('expenses', 'role_expenses', 'all', 'private.can_finance(org_id)', 'private.can_finance(org_id)'),
      ('recurring_invoices', 'role_recurring', 'all', 'private.can_finance(org_id)', 'private.can_finance(org_id)'),
      ('import_jobs', 'role_import_jobs', 'all', 'private.can_finance(org_id)', 'private.can_finance(org_id)'),
      ('invoices', 'role_invoices_select', 'select', 'not private.is_tech(org_id) or user_id = (select auth.uid())', null),
      ('invoice_items', 'role_items_select', 'select', 'exists (select 1 from public.invoices i where i.id = invoice_id)', null),
      ('payments', 'role_payments_select', 'select', 'not private.is_tech(org_id) or user_id = (select auth.uid())', null),
      ('quotes', 'role_quotes_select', 'select', 'not private.is_tech(org_id) or user_id = (select auth.uid())', null),
      ('quote_items', 'role_quote_items_select', 'select', 'exists (select 1 from public.quotes q where q.id = quote_id)', null),
      ('fiscal_documents', 'role_fiscal_select', 'select', 'exists (select 1 from public.invoices i where i.id = invoice_id)', null),
      ('fiscal_notes', 'role_fiscal_notes_select', 'select', 'exists (select 1 from public.invoices i where i.id = invoice_id)', null),
      ('payment_claims', 'role_claims_select', 'select', 'not private.is_tech(org_id)', null),
      ('clients', 'role_clients_select', 'select', 'not private.is_tech(org_id) or private.tech_sees_client(id)', null),
      ('client_notes', 'role_client_notes_select', 'select', 'not private.is_tech(org_id) or private.tech_sees_client(client_id)', null),
      ('client_assets', 'role_client_assets_select', 'select', 'not private.is_tech(org_id) or private.tech_sees_client(client_id)', null),
      ('jobs', 'role_jobs_select', 'select', 'not private.is_tech(org_id) or assigned_to = (select auth.uid()) or created_by = (select auth.uid())', null),
      ('jobs', 'role_jobs_update', 'update', 'not private.is_tech(org_id) or assigned_to = (select auth.uid()) or created_by = (select auth.uid())', null),
      ('job_events', 'role_job_events_select', 'select', 'not private.is_tech(org_id) or private.tech_sees_job(job_id)', null),
      ('job_materials', 'role_job_materials', 'all', 'not private.is_tech(org_id) or private.tech_sees_job(job_id)', 'not private.is_tech(org_id) or private.tech_sees_job(job_id)'),
      ('job_milestones', 'role_job_milestones', 'all', 'private.can_finance(org_id) or (not private.is_tech(org_id))', 'private.can_finance(org_id) or (not private.is_tech(org_id))'),
      ('media_files', 'role_media_select', 'select', 'not private.is_tech(org_id) or (job_id is not null and private.tech_sees_job(job_id)) or (client_id is not null and private.tech_sees_client(client_id))', null),
      -- Catálogo y precios: lo editan propietario, administrador o finanzas (ver es libre para el equipo)
      ('products', 'role_products_insert', 'insert', null, 'private.can_finance(org_id)'),
      ('products', 'role_products_update', 'update', 'private.can_finance(org_id)', null),
      ('products', 'role_products_delete', 'delete', 'private.can_finance(org_id)', null)
    ) as t(tbl, pol, cmd, use_expr, check_expr)
  loop
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = r.tbl and policyname = r.pol) then
      execute format('create policy %I on public.%I as restrictive for %s to authenticated %s %s',
        r.pol, r.tbl, r.cmd,
        case when r.use_expr is null then '' else 'using (' || r.use_expr || ')' end,
        case when r.check_expr is null then '' else 'with check (' || r.check_expr || ')' end);
    end if;
  end loop;
end $$;

-- ───────────── Invitar / cambiar rol / quitar ─────────────
create or replace function private.invite_member_impl(p_org uuid, p_email text, p_staff_role text, p_admin boolean, p_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller text;
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_target uuid;
  v_role text := case when coalesce(p_admin, false) then 'admin' else 'member' end;
  v_staff text := case when coalesce(p_admin, false) then null else nullif(btrim(coalesce(p_staff_role, '')), '') end;
  v_max integer;
  v_count integer;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select m.role into v_caller from public.organization_members m where m.org_id = p_org and m.user_id = v_uid;
  if v_caller is null or v_caller not in ('owner', 'admin') then
    raise exception 'Solo el propietario o un administrador puede invitar' using errcode = '42501';
  end if;
  if v_role = 'admin' and v_caller <> 'owner' then
    raise exception 'Solo el propietario puede nombrar administradores' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo no válido' using errcode = '22023'; end if;
  if v_staff is not null and v_staff not in ('finanzas', 'cajero', 'tecnico', 'vendedor') then
    raise exception 'Rol no válido' using errcode = '22023';
  end if;
  v_max := private.max_users(p_org);
  select count(*) into v_count from public.organization_members m where m.org_id = p_org;
  v_count := v_count + (select count(*) from public.org_invites i where i.org_id = p_org and i.accepted_at is null and lower(i.email) <> v_email);
  if v_max >= 0 and v_count >= v_max then
    raise exception 'Tu plan permite % usuarios. Mejora tu plan para agregar más personas.', v_max using errcode = 'P0001';
  end if;
  if v_count >= 50 then raise exception 'Límite de personas por empresa alcanzado' using errcode = '22023'; end if;

  select u.id into v_target from auth.users u where lower(u.email) = v_email limit 1;
  if v_target is not null then
    insert into public.organization_members (org_id, user_id, role, staff_role, display_name)
    values (p_org, v_target, v_role, v_staff, nullif(btrim(coalesce(p_name, '')), ''))
    on conflict (org_id, user_id) do update
      set staff_role = excluded.staff_role,
          display_name = coalesce(excluded.display_name, public.organization_members.display_name)
      where public.organization_members.role <> 'owner';
    return 'added';
  end if;
  insert into public.org_invites (org_id, email, role, staff_role, display_name, invited_by)
  values (p_org, v_email, v_role, v_staff, nullif(btrim(coalesce(p_name, '')), ''), v_uid)
  on conflict (org_id, lower(email)) where accepted_at is null do update
    set role = excluded.role, staff_role = excluded.staff_role, display_name = excluded.display_name, invited_by = excluded.invited_by;
  return 'invited';
end;
$$;

create or replace function private.set_member_role_impl(p_org uuid, p_user uuid, p_staff_role text, p_admin boolean,
                                                         p_commission numeric, p_goal numeric, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller text;
  v_target text;
  v_staff text := nullif(btrim(coalesce(p_staff_role, '')), '');
begin
  select m.role into v_caller from public.organization_members m where m.org_id = p_org and m.user_id = v_uid;
  select m.role into v_target from public.organization_members m where m.org_id = p_org and m.user_id = p_user;
  if v_caller is null or v_caller not in ('owner', 'admin') then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if v_target is null then raise exception 'No encontrado' using errcode = 'P0002'; end if;
  if v_target = 'owner' then
    update public.organization_members set display_name = coalesce(nullif(btrim(coalesce(p_name, '')), ''), display_name),
      commission_pct = p_commission, sales_goal = p_goal where org_id = p_org and user_id = p_user;
    return;
  end if;
  if (coalesce(p_admin, false) or v_target = 'admin') and v_caller <> 'owner' then
    raise exception 'Solo el propietario cambia administradores' using errcode = '42501';
  end if;
  if v_staff is not null and v_staff not in ('finanzas', 'cajero', 'tecnico', 'vendedor') then
    raise exception 'Rol no válido' using errcode = '22023';
  end if;
  update public.organization_members
     set role = case when coalesce(p_admin, false) then 'admin' else 'member' end,
         staff_role = case when coalesce(p_admin, false) then null else v_staff end,
         commission_pct = p_commission,
         sales_goal = p_goal,
         display_name = coalesce(nullif(btrim(coalesce(p_name, '')), ''), display_name)
   where org_id = p_org and user_id = p_user;
end;
$$;

-- Acepta las invitaciones pendientes del correo de la sesión. Devuelve cuántas empresas se unieron.
create or replace function private.claim_invites_impl()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_email text;
  v_n integer := 0;
  i record;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select lower(u.email) into v_email from auth.users u where u.id = v_uid;
  if v_email is null then return 0; end if;
  for i in select * from public.org_invites where lower(email) = v_email and accepted_at is null for update loop
    insert into public.organization_members (org_id, user_id, role, staff_role, display_name)
    values (i.org_id, v_uid, i.role, i.staff_role, i.display_name)
    on conflict (org_id, user_id) do nothing;
    update public.org_invites set accepted_at = now(), accepted_by = v_uid where id = i.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Lo que la app necesita saber del usuario en la empresa activa (rol, permisos, nombre, si ya vio la bienvenida).
create or replace function private.my_access_impl(p_org uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  m public.organization_members;
  v_role text;
begin
  select * into m from public.organization_members where org_id = p_org and user_id = (select auth.uid());
  if not found then raise exception 'Sin acceso' using errcode = '42501'; end if;
  v_role := case when m.role in ('owner', 'admin') then m.role else coalesce(m.staff_role, 'cajero') end;
  return jsonb_build_object(
    'role', v_role,
    'is_admin', m.role in ('owner', 'admin'),
    'display_name', m.display_name,
    'welcomed', m.welcomed_at is not null,
    'org_name', (select o.name from public.organizations o where o.id = p_org),
    'can', jsonb_build_object(
      'finance', v_role in ('owner', 'admin', 'finanzas'),
      'sell', v_role <> 'tecnico',
      'collect', v_role <> 'tecnico',
      'clients', true,
      'jobs', true,
      'all_jobs', v_role <> 'tecnico',
      'products_edit', v_role in ('owner', 'admin', 'finanzas'),
      'team', m.role in ('owner', 'admin'),
      'settings', m.role in ('owner', 'admin'),
      'license', m.role in ('owner', 'admin'),
      'import', v_role in ('owner', 'admin', 'finanzas')));
end;
$$;

create or replace function private.mark_welcomed_impl(p_org uuid)
returns void language sql security definer set search_path = ''
as $$ update public.organization_members set welcomed_at = coalesce(welcomed_at, now()) where org_id = p_org and user_id = (select auth.uid()); $$;

create or replace function private.team_members_impl(p_org uuid)
returns table (user_id uuid, email text, role text, staff_role text, display_name text, commission_pct numeric, sales_goal numeric, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  return query
    select m.user_id, u.email::text, m.role, m.staff_role, m.display_name,
           case when private.is_org_admin(p_org) or m.user_id = (select auth.uid()) then m.commission_pct end,
           case when private.is_org_admin(p_org) or m.user_id = (select auth.uid()) then m.sales_goal end,
           m.created_at
    from public.organization_members m join auth.users u on u.id = m.user_id
    where m.org_id = p_org order by m.created_at;
end;
$$;

revoke execute on function private.invite_member_impl(uuid, text, text, boolean, text),
  private.set_member_role_impl(uuid, uuid, text, boolean, numeric, numeric, text), private.claim_invites_impl(),
  private.my_access_impl(uuid), private.mark_welcomed_impl(uuid), private.team_members_impl(uuid) from public, anon;
grant execute on function private.invite_member_impl(uuid, text, text, boolean, text),
  private.set_member_role_impl(uuid, uuid, text, boolean, numeric, numeric, text), private.claim_invites_impl(),
  private.my_access_impl(uuid), private.mark_welcomed_impl(uuid), private.team_members_impl(uuid) to authenticated;

create or replace function public.invite_member(p_org uuid, p_email text, p_staff_role text default 'cajero', p_admin boolean default false, p_name text default null)
returns text language sql security invoker set search_path = '' as $$ select private.invite_member_impl(p_org, p_email, p_staff_role, p_admin, p_name) $$;
create or replace function public.set_member_role(p_org uuid, p_user uuid, p_staff_role text, p_admin boolean default false,
                                                  p_commission numeric default null, p_goal numeric default null, p_name text default null)
returns void language sql security invoker set search_path = '' as $$ select private.set_member_role_impl(p_org, p_user, p_staff_role, p_admin, p_commission, p_goal, p_name) $$;
create or replace function public.claim_invites()
returns integer language sql security invoker set search_path = '' as $$ select private.claim_invites_impl() $$;
create or replace function public.my_access(p_org uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$ select private.my_access_impl(p_org) $$;
create or replace function public.mark_welcomed(p_org uuid)
returns void language sql security invoker set search_path = '' as $$ select private.mark_welcomed_impl(p_org) $$;
create or replace function public.team_members(p_org uuid)
returns table (user_id uuid, email text, role text, staff_role text, display_name text, commission_pct numeric, sales_goal numeric, joined_at timestamptz)
language sql stable security invoker set search_path = '' as $$ select * from private.team_members_impl(p_org) $$;

revoke execute on function public.invite_member(uuid, text, text, boolean, text),
  public.set_member_role(uuid, uuid, text, boolean, numeric, numeric, text), public.claim_invites(),
  public.my_access(uuid), public.mark_welcomed(uuid), public.team_members(uuid) from public, anon;
grant execute on function public.invite_member(uuid, text, text, boolean, text),
  public.set_member_role(uuid, uuid, text, boolean, numeric, numeric, text), public.claim_invites(),
  public.my_access(uuid), public.mark_welcomed(uuid), public.team_members(uuid) to authenticated;

-- ───────────── Usuario nuevo: si fue invitado, entra a esa empresa (sin crear una propia) ─────────────
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_invited integer := 0;
  i record;
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  if new.email is not null then
    for i in select * from public.org_invites where lower(email) = lower(new.email) and accepted_at is null loop
      insert into public.organization_members (org_id, user_id, role, staff_role, display_name)
      values (i.org_id, new.id, i.role, i.staff_role, i.display_name) on conflict (org_id, user_id) do nothing;
      update public.org_invites set accepted_at = now(), accepted_by = new.id where id = i.id;
      v_invited := v_invited + 1;
    end loop;
  end if;
  if v_invited = 0 then
    insert into public.organizations (name, created_by) values ('Mi empresa', new.id) returning id into v_org;
    insert into public.organization_members (org_id, user_id, role) values (v_org, new.id, 'owner');
  end if;
  return new;
end;
$$;

-- Tiempo real del equipo (ventas de empleados aparecen al instante en el panel del dueño: invoices ya está publicado)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'organization_members') then
    alter publication supabase_realtime add table public.organization_members;
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
