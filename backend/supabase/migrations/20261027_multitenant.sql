-- FacturaVoz · Migración 4 · Multi-empresa (organizaciones y equipo)
-- Ejecutar DESPUÉS de las migraciones 1-3 y 20261026_harden_fiscal.sql. Idempotente.
-- Fase 1: los datos (clientes, facturas, líneas) pertenecen a una organización; un usuario puede
-- pertenecer a varias y trabajar en equipo con roles. La emisión SUNAT sigue ligada al usuario emisor.
begin;

create schema if not exists private;
grant usage on schema private to authenticated;

-- 1) Tablas -----------------------------------------------------------------------------------
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  tax_id text check (tax_id is null or char_length(tax_id) <= 30),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index if not exists idx_org_members_user on public.organization_members(user_id);

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;

-- 2) Ayudantes de pertenencia (SECURITY DEFINER solo en private; evitan recursión de RLS) --------
create or replace function private.is_org_member(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_members m
    where m.org_id = p_org and m.user_id = (select auth.uid()));
$$;

create or replace function private.is_org_admin(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_members m
    where m.org_id = p_org and m.user_id = (select auth.uid()) and m.role in ('owner', 'admin'));
$$;
revoke execute on function private.is_org_member(uuid), private.is_org_admin(uuid) from public, anon;
grant execute on function private.is_org_member(uuid), private.is_org_admin(uuid) to authenticated;

-- 3) Backfill: cada usuario existente recibe su organización personal ---------------------------
insert into public.organizations (name, tax_id, created_by)
select coalesce(nullif(btrim(p.business_name), ''), 'Mi empresa'), p.tax_id, u.id
from auth.users u
left join public.profiles p on p.id = u.id
where not exists (select 1 from public.organization_members m where m.user_id = u.id)
  and (p.id is not null
       or exists (select 1 from public.invoices i where i.user_id = u.id)
       or exists (select 1 from public.clients c where c.user_id = u.id));

insert into public.organization_members (org_id, user_id, role)
select o.id, o.created_by, 'owner'
from public.organizations o
where o.created_by is not null
  and not exists (select 1 from public.organization_members m where m.org_id = o.id)
on conflict do nothing;

-- 4) org_id en datos ----------------------------------------------------------------------------
alter table public.clients add column if not exists org_id uuid references public.organizations(id) on delete cascade;
alter table public.invoices add column if not exists org_id uuid references public.organizations(id) on delete cascade;

update public.clients c set org_id = (
  select m.org_id from public.organization_members m where m.user_id = c.user_id order by m.created_at limit 1)
where c.org_id is null;
update public.invoices i set org_id = (
  select m.org_id from public.organization_members m where m.user_id = i.user_id order by m.created_at limit 1)
where i.org_id is null;

alter table public.clients alter column org_id set not null;
alter table public.invoices alter column org_id set not null;
create index if not exists idx_clients_org on public.clients(org_id);
create index if not exists idx_invoices_org on public.invoices(org_id, created_at desc);

-- La numeración correlativa pasa a ser por organización
alter table public.invoices drop constraint if exists invoices_user_id_number_key;
create unique index if not exists invoices_org_number_key on public.invoices(org_id, number);

-- 5) Políticas RLS por pertenencia --------------------------------------------------------------
-- organizations / members: lectura para miembros; escritura SOLO vía funciones controladas
drop policy if exists "orgs_select" on public.organizations;
create policy "orgs_select" on public.organizations for select to authenticated
  using (private.is_org_member(id));
drop policy if exists "orgs_update" on public.organizations;
create policy "orgs_update" on public.organizations for update to authenticated
  using (private.is_org_admin(id)) with check (private.is_org_admin(id));
drop policy if exists "members_select" on public.organization_members;
create policy "members_select" on public.organization_members for select to authenticated
  using (private.is_org_member(org_id));

revoke all on public.organizations, public.organization_members from anon, authenticated;
grant select on public.organizations, public.organization_members to authenticated;
grant update (name, tax_id) on public.organizations to authenticated;

-- clients
drop policy if exists "clients_select" on public.clients;
drop policy if exists "clients_insert" on public.clients;
drop policy if exists "clients_update" on public.clients;
drop policy if exists "clients_delete" on public.clients;
create policy "clients_select" on public.clients for select to authenticated
  using (private.is_org_member(org_id));
create policy "clients_insert" on public.clients for insert to authenticated
  with check ((select auth.uid()) = user_id and private.is_org_member(org_id));
create policy "clients_update" on public.clients for update to authenticated
  using (private.is_org_member(org_id))
  with check (private.is_org_member(org_id));
create policy "clients_delete" on public.clients for delete to authenticated
  using (private.is_org_admin(org_id));

-- invoices
drop policy if exists "invoices_select" on public.invoices;
drop policy if exists "invoices_insert" on public.invoices;
drop policy if exists "invoices_update" on public.invoices;
drop policy if exists "invoices_delete" on public.invoices;
create policy "invoices_select" on public.invoices for select to authenticated
  using (private.is_org_member(org_id));
create policy "invoices_insert" on public.invoices for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and private.is_org_member(org_id)
    and (client_id is null or exists (
      select 1 from public.clients c where c.id = client_id and c.org_id = invoices.org_id))
  );
create policy "invoices_update" on public.invoices for update to authenticated
  using (private.is_org_member(org_id))
  with check (
    private.is_org_member(org_id)
    and (client_id is null or exists (
      select 1 from public.clients c where c.id = client_id and c.org_id = invoices.org_id))
  );
create policy "invoices_delete" on public.invoices for delete to authenticated
  using (status = 'draft' and ((select auth.uid()) = user_id or private.is_org_admin(org_id)));

-- invoice_items (solo mientras la factura es borrador, como antes)
drop policy if exists "items_select" on public.invoice_items;
drop policy if exists "items_insert" on public.invoice_items;
drop policy if exists "items_update" on public.invoice_items;
drop policy if exists "items_delete" on public.invoice_items;
create policy "items_select" on public.invoice_items for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and private.is_org_member(i.org_id)));
create policy "items_insert" on public.invoice_items for insert to authenticated
  with check ((select auth.uid()) = user_id
    and exists (select 1 from public.invoices i
                where i.id = invoice_id and private.is_org_member(i.org_id) and i.status = 'draft'));
create policy "items_update" on public.invoice_items for update to authenticated
  using (exists (select 1 from public.invoices i
                 where i.id = invoice_id and private.is_org_member(i.org_id) and i.status = 'draft'))
  with check (exists (select 1 from public.invoices i
                      where i.id = invoice_id and private.is_org_member(i.org_id) and i.status = 'draft'));
create policy "items_delete" on public.invoice_items for delete to authenticated
  using (exists (select 1 from public.invoices i
                 where i.id = invoice_id and private.is_org_member(i.org_id) and i.status = 'draft'));

-- Comprobantes fiscales: los ven todos los miembros de la organización de la factura
drop policy if exists "fiscal_documents_select" on public.fiscal_documents;
create policy "fiscal_documents_select" on public.fiscal_documents for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and private.is_org_member(i.org_id)));
drop policy if exists "fiscal_notes_select" on public.fiscal_notes;
create policy "fiscal_notes_select" on public.fiscal_notes for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and private.is_org_member(i.org_id)));

-- org_id inmutable (junto con user_id y number)
create or replace function private.guard_invoice_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id or new.number is distinct from old.number
     or new.org_id is distinct from old.org_id then
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

-- 6) Funciones de gestión de equipo (SECURITY DEFINER en private + envoltorio INVOKER público) ---
create or replace function private.create_organization_impl(p_name text, p_tax_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 120 then
    raise exception 'Nombre de empresa no válido' using errcode = '22023';
  end if;
  if (select count(*) from public.organization_members m where m.user_id = v_uid and m.role = 'owner') >= 10 then
    raise exception 'Límite de empresas alcanzado' using errcode = '22023';
  end if;
  insert into public.organizations (name, tax_id, created_by)
  values (btrim(p_name), nullif(btrim(coalesce(p_tax_id, '')), ''), v_uid)
  returning id into v_id;
  insert into public.organization_members (org_id, user_id, role) values (v_id, v_uid, 'owner');
  return v_id;
end;
$$;

create or replace function private.add_member_impl(p_org uuid, p_email text, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_target uuid;
  v_caller text;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select m.role into v_caller from public.organization_members m where m.org_id = p_org and m.user_id = v_uid;
  if v_caller is null or v_caller = 'member' then
    raise exception 'Solo propietarios y administradores pueden agregar personas' using errcode = '42501';
  end if;
  if p_role not in ('admin', 'member') then raise exception 'Rol no válido' using errcode = '22023'; end if;
  if p_role = 'admin' and v_caller <> 'owner' then
    raise exception 'Solo el propietario puede nombrar administradores' using errcode = '42501';
  end if;
  if (select count(*) from public.organization_members m where m.org_id = p_org) >= 25 then
    raise exception 'Límite de personas por empresa alcanzado' using errcode = '22023';
  end if;
  select u.id into v_target from auth.users u where lower(u.email) = lower(btrim(coalesce(p_email, ''))) limit 1;
  if v_target is null then
    raise exception 'Ese correo aún no tiene cuenta en FacturaVoz. Pídele que se registre primero.' using errcode = 'P0002';
  end if;
  insert into public.organization_members (org_id, user_id, role) values (p_org, v_target, p_role)
  on conflict (org_id, user_id) do nothing;
end;
$$;

create or replace function private.remove_member_impl(p_org uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller text;
  v_target text;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select m.role into v_caller from public.organization_members m where m.org_id = p_org and m.user_id = v_uid;
  select m.role into v_target from public.organization_members m where m.org_id = p_org and m.user_id = p_user;
  if v_caller is null or v_target is null then raise exception 'No encontrado' using errcode = 'P0002'; end if;
  if v_target = 'owner' then raise exception 'No se puede quitar al propietario' using errcode = '42501'; end if;
  if p_user <> v_uid and (v_caller = 'member' or (v_caller = 'admin' and v_target = 'admin')) then
    raise exception 'Sin permiso para quitar a esta persona' using errcode = '42501';
  end if;
  delete from public.organization_members where org_id = p_org and user_id = p_user;
end;
$$;

revoke execute on function private.create_organization_impl(text, text), private.add_member_impl(uuid, text, text),
  private.remove_member_impl(uuid, uuid) from public, anon;
grant execute on function private.create_organization_impl(text, text), private.add_member_impl(uuid, text, text),
  private.remove_member_impl(uuid, uuid) to authenticated;

create or replace function public.create_organization(p_name text, p_tax_id text default null)
returns uuid language sql security invoker set search_path = ''
as $$ select private.create_organization_impl(p_name, p_tax_id); $$;
create or replace function public.add_org_member(p_org uuid, p_email text, p_role text default 'member')
returns void language sql security invoker set search_path = ''
as $$ select private.add_member_impl(p_org, p_email, p_role); $$;
create or replace function public.remove_org_member(p_org uuid, p_user uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.remove_member_impl(p_org, p_user); $$;
revoke execute on function public.create_organization(text, text), public.add_org_member(uuid, text, text),
  public.remove_org_member(uuid, uuid) from public, anon;
grant execute on function public.create_organization(text, text), public.add_org_member(uuid, text, text),
  public.remove_org_member(uuid, uuid) to authenticated;

-- Lista de integrantes con su correo (solo para miembros de la organización)
create or replace function private.list_members_impl(p_org uuid)
returns table (user_id uuid, email text, role text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_org_member(p_org) then raise exception 'Sin acceso' using errcode = '42501'; end if;
  return query select m.user_id, u.email::text, m.role
    from public.organization_members m join auth.users u on u.id = m.user_id
    where m.org_id = p_org order by m.created_at;
end;
$$;
revoke execute on function private.list_members_impl(uuid) from public, anon;
grant execute on function private.list_members_impl(uuid) to authenticated;
create or replace function public.list_org_members(p_org uuid)
returns table (user_id uuid, email text, role text)
language sql stable security invoker set search_path = ''
as $$ select * from private.list_members_impl(p_org); $$;
revoke execute on function public.list_org_members(uuid) from public, anon;
grant execute on function public.list_org_members(uuid) to authenticated;

-- 7) Usuario nuevo: perfil + organización personal ----------------------------------------------
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  insert into public.organizations (name, created_by) values ('Mi empresa', new.id) returning id into v_org;
  insert into public.organization_members (org_id, user_id, role) values (v_org, new.id, 'owner');
  return new;
end;
$$;

-- 8) create_invoice con organización y numeración por organización ------------------------------
drop function if exists public.create_invoice(text, text, numeric, text, text, text, jsonb);
create or replace function public.create_invoice(
  p_client_name text,
  p_client_tax_id text,
  p_tax_rate numeric,
  p_currency text,
  p_notes text,
  p_transcript text,
  p_items jsonb,
  p_org_id uuid default null
)
returns table (invoice_id uuid, invoice_number text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_org uuid := p_org_id;
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
  if v_org is null then
    select m.org_id into v_org from public.organization_members m
    where m.user_id = v_uid order by m.created_at limit 1;
  end if;
  if v_org is null or not private.is_org_member(v_org) then
    raise exception 'Empresa no válida' using errcode = '42501';
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

  perform pg_advisory_xact_lock(hashtextextended('invoice-number:' || v_org::text, 0));

  select c.id into v_client
  from public.clients c
  where c.org_id = v_org and lower(c.name) = lower(v_name)
  order by c.created_at
  limit 1;

  if v_client is null then
    insert into public.clients (user_id, org_id, name, tax_id)
    values (v_uid, v_org, v_name, v_tax)
    returning clients.id into v_client;
  elsif v_tax is not null then
    update public.clients set tax_id = v_tax where clients.id = v_client and clients.tax_id is null;
  end if;

  select coalesce(max((substring(i.number from '(\d+)$'))::bigint), 0) + 1
  into v_next
  from public.invoices i
  where i.org_id = v_org and i.number ~ '\d+$';

  v_number := 'F-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next::text, 4, '0');

  insert into public.invoices (user_id, org_id, client_id, number, tax_rate, currency, notes, transcript)
  values (v_uid, v_org, v_client, v_number, p_tax_rate, p_currency, p_notes, p_transcript)
  returning invoices.id into v_id;

  insert into public.invoice_items (user_id, invoice_id, description, quantity, unit_price, position)
  select v_uid, v_id, btrim(e.item ->> 'description'),
         (e.item ->> 'quantity')::numeric, (e.item ->> 'unit_price')::numeric, e.ord::integer
  from jsonb_array_elements(p_items) with ordinality as e(item, ord);

  return query select v_id, v_number;
end;
$$;
revoke execute on function public.create_invoice(text, text, numeric, text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.create_invoice(text, text, numeric, text, text, text, jsonb, uuid) to authenticated;

-- 9) Borrado de cuenta: limpia organizaciones que queden sin integrantes ------------------------
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
  delete from public.organizations o
  where not exists (select 1 from public.organization_members m where m.org_id = o.id);
end;
$$;

commit;
