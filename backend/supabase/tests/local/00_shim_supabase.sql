-- Shim mínimo de Supabase para pruebas locales (NUNCA producción)
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create table if not exists auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}', created_at timestamptz default now());
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('sub', current_setting('request.jwt.claim.sub', true), 'email', (select email from auth.users where id = auth.uid())) $$;
create or replace function auth.email() returns text language sql stable as $$ select email from auth.users where id = auth.uid() $$;
create or replace function auth.role() returns text language sql stable as $$ select current_user::text $$;
create table if not exists storage.buckets(id text primary key, name text, public boolean default false, file_size_limit bigint, allowed_mime_types text[]);
create table if not exists storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, created_at timestamptz default now());
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name, '/') $$;
grant usage on schema auth, storage, extensions, public to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.jwt(), auth.email(), auth.role() to anon, authenticated, service_role;
-- Sin privilegios por defecto (como proyectos nuevos de Supabase)
revoke all on schema public from public;
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to authenticated; grant select on storage.buckets to authenticated, anon;
