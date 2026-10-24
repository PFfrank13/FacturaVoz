-- Voice-to-Invoice · Esquema multi-tenant con RLS optimizado
-- Pegar completo en Supabase > SQL Editor > Run

create schema if not exists private;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  business_name text,
  tax_id text,
  address text,
  created_at timestamptz not null default now()
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  email text,
  tax_id text,
  address text,
  created_at timestamptz not null default now()
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  number text not null,
  issue_date date not null default current_date,
  tax_rate numeric(5,2) not null default 21 check (tax_rate between 0 and 100),
  status text not null default 'draft' check (status in ('draft','sent','paid')),
  notes text,
  transcript text,
  created_at timestamptz not null default now(),
  unique (user_id, number)
);

create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  description text not null check (char_length(description) between 1 and 200),
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0)
);

-- Índices para cada FK usada en RLS
create index idx_clients_user_id on public.clients(user_id);
create index idx_invoices_user_id on public.invoices(user_id);
create index idx_invoices_client_id on public.invoices(client_id);
create index idx_items_user_id on public.invoice_items(user_id);
create index idx_items_invoice_id on public.invoice_items(invoice_id);

-- RLS
alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;

-- profiles
create policy "profiles_select" on public.profiles for select to authenticated
  using ((select auth.uid()) = id);
create policy "profiles_insert" on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);
create policy "profiles_update" on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- clients
create policy "clients_select" on public.clients for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "clients_insert" on public.clients for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "clients_update" on public.clients for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "clients_delete" on public.clients for delete to authenticated
  using ((select auth.uid()) = user_id);

-- invoices (el client_id debe pertenecer al mismo usuario)
create policy "invoices_select" on public.invoices for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "invoices_insert" on public.invoices for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and (client_id is null or exists (
      select 1 from public.clients c
      where c.id = client_id and c.user_id = (select auth.uid())))
  );
create policy "invoices_update" on public.invoices for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and (client_id is null or exists (
      select 1 from public.clients c
      where c.id = client_id and c.user_id = (select auth.uid())))
  );
create policy "invoices_delete" on public.invoices for delete to authenticated
  using ((select auth.uid()) = user_id and status = 'draft');

-- invoice_items (la factura debe pertenecer al mismo usuario)
create policy "items_select" on public.invoice_items for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "items_insert" on public.invoice_items for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.invoices i
      where i.id = invoice_id and i.user_id = (select auth.uid()))
  );
create policy "items_update" on public.invoice_items for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.invoices i
      where i.id = invoice_id and i.user_id = (select auth.uid()))
  );
create policy "items_delete" on public.invoice_items for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Perfil automático al registrarse (SECURITY DEFINER en esquema private)
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Control de uso (rate limiting sin coste, usado por /api/parse)
create table public.api_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index idx_api_usage_user_created on public.api_usage(user_id, created_at desc);
alter table public.api_usage enable row level security;
create policy "usage_select" on public.api_usage for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "usage_insert" on public.api_usage for insert to authenticated
  with check ((select auth.uid()) = user_id);
-- (sin policy de update/delete: el usuario no puede borrar su propio historial de uso)

-- Defensa en profundidad: el rol anónimo no necesita nada en public
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
-- La función de privilegio elevado no debe ser invocable por nadie salvo el trigger
revoke execute on function private.handle_new_user() from public, anon, authenticated;
revoke all on schema private from anon, authenticated;
