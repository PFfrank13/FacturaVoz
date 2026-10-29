-- FacturaVoz v3 · A3 Rendimiento de la seguridad (RLS) con decenas de miles de filas.
-- Las políticas llamaban funciones (es miembro / es técnico / licencia) UNA VEZ POR FILA. Con 10 000 comprobantes
-- eso son decenas de miles de llamadas por consulta. Aquí se calcula UNA VEZ por consulta la lista de empresas del
-- usuario y las políticas comparan contra esa lista. MISMAS reglas, mismo resultado; solo más rápido.
-- No borra nada: usa ALTER POLICY (cambia la condición de lectura de la política existente). Idempotente.
begin;

create or replace function private.my_org_ids()
returns uuid[] language sql stable security definer set search_path = ''
as $$ select coalesce(array_agg(m.org_id), '{}') from public.organization_members m where m.user_id = (select auth.uid()) $$;

create or replace function private.my_admin_org_ids()
returns uuid[] language sql stable security definer set search_path = ''
as $$ select coalesce(array_agg(m.org_id), '{}') from public.organization_members m where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin') $$;

-- Igual que private.is_tech: no es dueño/admin y su rol de equipo es 'tecnico'.
create or replace function private.my_tech_org_ids()
returns uuid[] language sql stable security definer set search_path = ''
as $$ select coalesce(array_agg(m.org_id), '{}') from public.organization_members m
      where m.user_id = (select auth.uid()) and m.role not in ('owner', 'admin') and coalesce(m.staff_role, 'cajero') = 'tecnico' $$;

-- Empresas cuya licencia permite leer (misma regla que private.license_read_ok).
create or replace function private.my_readable_org_ids()
returns uuid[] language sql stable security definer set search_path = ''
as $$ select coalesce(array_agg(m.org_id), '{}') from public.organization_members m
      where m.user_id = (select auth.uid()) and private.license_read_ok(m.org_id) $$;

revoke execute on function private.my_org_ids(), private.my_admin_org_ids(), private.my_tech_org_ids(), private.my_readable_org_ids() from public, anon;
grant execute on function private.my_org_ids(), private.my_admin_org_ids(), private.my_tech_org_ids(), private.my_readable_org_ids() to authenticated, service_role;

-- Reescribe SOLO políticas de lectura (SELECT) cuyo texto contiene las llamadas por fila conocidas.
do $$
declare
  p record;
  q text;
begin
  for p in
    select schemaname, tablename, policyname, qual from pg_policies
    where schemaname = 'public' and cmd = 'SELECT' and qual is not null
      and (qual like '%private.is_org_member(%org_id)%' or qual like '%private.license_read_ok(org_id)%'
           or qual like '%private.is_tech(org_id)%' or qual like '%private.is_org_admin(org_id)%')
  loop
    q := p.qual;
    q := replace(q, 'private.is_org_member(org_id)', '(org_id = ANY ((SELECT private.my_org_ids())::uuid[]))');
    q := replace(q, 'private.is_org_member(i.org_id)', '(i.org_id = ANY ((SELECT private.my_org_ids())::uuid[]))');
    q := replace(q, 'private.license_read_ok(org_id)', '(org_id = ANY ((SELECT private.my_readable_org_ids())::uuid[]))');
    q := replace(q, '(NOT private.is_tech(org_id))', '(org_id <> ALL ((SELECT private.my_tech_org_ids())::uuid[]))');
    q := replace(q, 'private.is_tech(org_id)', '(org_id = ANY ((SELECT private.my_tech_org_ids())::uuid[]))');
    q := replace(q, 'private.is_org_admin(org_id)', '(org_id = ANY ((SELECT private.my_admin_org_ids())::uuid[]))');
    if q <> p.qual then
      execute format('alter policy %I on %I.%I using (%s)', p.policyname, p.schemaname, p.tablename, q);
    end if;
  end loop;
end $$;

-- Las políticas nuevas de licencia (tablas futuras) nacen ya en la forma rápida.
create or replace function private.install_license_guards()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  t text;
  n integer := 0;
  v_skip text[] := array['org_licenses', 'organization_members', 'audit_log', 'owner_alerts', 'trash', 'pin_grants', 'api_rate', 'webhook_outbox', 'job_events'];
begin
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
    where c.table_schema = 'public' and c.column_name = 'org_id'
  loop
    if t = any(v_skip) then continue; end if;
    execute format('create or replace trigger %I before insert or update or delete on public.%I for each row execute function private.license_guard()', t || '_license_guard', t);
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'license_read_' || t) then
      execute format('create policy %I on public.%I as restrictive for select to authenticated using (org_id = ANY ((SELECT private.my_readable_org_ids())::uuid[]))', 'license_read_' || t, t);
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$$;
select private.install_license_guards();

commit;

notify pgrst, 'reload schema';
