-- v3.8c · Turnos de caja por cajero (docs/INVESTIGACION_RETAIL.md, filas 5 y 7: robo interno 39 %, colusión 21 %).
-- Cada cajero abre su turno con su fondo y lo cierra contando su cajón a ciegas; lo esperado (fondo + cobros en
-- efectivo + ingresos − retiros del propio cajero desde que abrió) lo calcula la base y solo lo ve finanzas.
-- SOLO AÑADE una tabla y funciones. La caja del día (day_summary / day_closings) no cambia.
begin;

create table if not exists public.cash_shifts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  opened_at timestamptz not null default now(),
  opening_float numeric(14,2) not null check (opening_float >= 0 and opening_float <= 10000000),
  closed_at timestamptz,
  counted_cash numeric(14,2) check (counted_cash is null or (counted_cash >= 0 and counted_cash <= 100000000)),
  expected_cash numeric(14,2),
  cash_sales numeric(14,2),
  digital_sales numeric(14,2),
  cash_in numeric(14,2),
  cash_out numeric(14,2),
  note text check (note is null or char_length(note) <= 300),
  check ((closed_at is null) = (counted_cash is null))
);
create unique index if not exists cash_shifts_one_open on public.cash_shifts(org_id, user_id) where closed_at is null;
create index if not exists cash_shifts_org_opened_idx on public.cash_shifts(org_id, opened_at desc);
create index if not exists cash_shifts_user_idx on public.cash_shifts(user_id);
alter table public.cash_shifts enable row level security;
revoke all on public.cash_shifts from public, anon, authenticated;
-- El cajero ve sus turnos sin lo esperado (vista abajo); finanzas ve todos con todo.
grant select (id, org_id, user_id, opened_at, opening_float, closed_at, counted_cash, note) on public.cash_shifts to authenticated;
drop policy if exists cash_shifts_read on public.cash_shifts;
create policy cash_shifts_read on public.cash_shifts for select to authenticated
  using (private.is_org_member(org_id) and (user_id = (select auth.uid()) or private.can_finance(org_id)));

create or replace function private.shift_totals(p_org uuid, p_user uuid, p_from timestamptz, p_to timestamptz)
returns table (cash_sales numeric, digital_sales numeric, cash_in numeric, cash_out numeric)
language sql stable security definer set search_path = ''
as $$
  select
    coalesce((select sum(p.amount) from public.payments p where p.org_id = p_org and p.user_id = p_user
               and p.created_at >= p_from and p.created_at <= p_to and p.method = 'efectivo'), 0),
    coalesce((select sum(p.amount) from public.payments p where p.org_id = p_org and p.user_id = p_user
               and p.created_at >= p_from and p.created_at <= p_to and p.method <> 'efectivo'), 0),
    coalesce((select sum(m.amount) from public.cash_movements m where m.org_id = p_org and m.user_id = p_user
               and m.created_at >= p_from and m.created_at <= p_to and m.method = 'efectivo' and m.kind = 'ingreso'), 0),
    coalesce((select sum(m.amount) from public.cash_movements m where m.org_id = p_org and m.user_id = p_user
               and m.created_at >= p_from and m.created_at <= p_to and m.method = 'efectivo' and m.kind = 'egreso'), 0)
$$;

create or replace function private.shift_guard(p_org uuid)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not private.is_org_member(p_org) or coalesce(private.org_role(p_org), '') = 'tecnico' then
    raise exception 'Tu rol no maneja caja' using errcode = '42501';
  end if;
  if not private.license_write_ok(p_org) or not private.has_feature(p_org, 'caja') then
    raise exception 'La licencia vigente no incluye caja' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.shift_open_impl(p_org uuid, p_float numeric)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  perform private.shift_guard(p_org);
  if p_float is null or p_float < 0 or p_float > 10000000 or p_float <> round(p_float, 2) then
    raise exception 'Fondo inicial inválido' using errcode = '22023';
  end if;
  select id into v_id from public.cash_shifts where org_id = p_org and user_id = (select auth.uid()) and closed_at is null;
  if found then return v_id; end if; -- reintento: el turno ya está abierto
  insert into public.cash_shifts(org_id, user_id, opening_float) values (p_org, (select auth.uid()), p_float) returning id into v_id;
  return v_id;
end;
$$;

-- Cierre ciego: el cajero solo escribe lo contado. Devuelve la diferencia únicamente a finanzas.
create or replace function private.shift_close_impl(p_org uuid, p_counted numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  s public.cash_shifts%rowtype;
  t record;
  v_expected numeric(14,2);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  perform private.shift_guard(p_org);
  if p_counted is null or p_counted < 0 or p_counted > 100000000 or p_counted <> round(p_counted, 2) then
    raise exception 'Escribe el efectivo contado' using errcode = '22023';
  end if;
  if char_length(coalesce(v_note, '')) > 300 then raise exception 'La nota admite hasta 300 caracteres' using errcode = '22023'; end if;
  select * into s from public.cash_shifts where org_id = p_org and user_id = (select auth.uid()) and closed_at is null for update;
  if not found then raise exception 'No tienes un turno abierto' using errcode = '22023'; end if;
  select * into t from private.shift_totals(p_org, s.user_id, s.opened_at, now());
  v_expected := s.opening_float + t.cash_sales + t.cash_in - t.cash_out;
  update public.cash_shifts set closed_at = now(), counted_cash = p_counted, expected_cash = v_expected,
    cash_sales = t.cash_sales, digital_sales = t.digital_sales, cash_in = t.cash_in, cash_out = t.cash_out, note = v_note
  where id = s.id;
  perform private.audit(p_org, 'cash_shift_close', 'cash_shifts', s.id::text,
    jsonb_build_object('counted', p_counted, 'expected', v_expected), (select auth.uid()));
  if private.can_finance(p_org) then
    return jsonb_build_object('id', s.id, 'expected', v_expected, 'counted', p_counted, 'difference', p_counted - v_expected);
  end if;
  return jsonb_build_object('id', s.id, 'counted', p_counted);
end;
$$;

-- Turnos con lo esperado, solo para finanzas (dueño, administrador o finanzas).
create or replace function private.shift_report_impl(p_org uuid, p_from date, p_to date)
returns table (id uuid, user_id uuid, name text, opened_at timestamptz, closed_at timestamptz, opening_float numeric,
               cash_sales numeric, digital_sales numeric, cash_in numeric, cash_out numeric,
               expected_cash numeric, counted_cash numeric, difference numeric, note text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.can_finance(p_org) then raise exception 'Solo finanzas ve los turnos' using errcode = '42501'; end if;
  return query
  select s.id, s.user_id, coalesce(m.display_name, 'Sin nombre'), s.opened_at, s.closed_at, s.opening_float,
         coalesce(s.cash_sales, t.cash_sales), coalesce(s.digital_sales, t.digital_sales), coalesce(s.cash_in, t.cash_in), coalesce(s.cash_out, t.cash_out),
         coalesce(s.expected_cash, s.opening_float + t.cash_sales + t.cash_in - t.cash_out),
         s.counted_cash, s.counted_cash - s.expected_cash, s.note
  from public.cash_shifts s
  left join public.organization_members m on m.org_id = s.org_id and m.user_id = s.user_id
  cross join lateral private.shift_totals(s.org_id, s.user_id, s.opened_at, coalesce(s.closed_at, now())) t
  where s.org_id = p_org
    and (s.opened_at at time zone 'America/Lima')::date between p_from and p_to
  order by s.opened_at desc
  limit 500;
end;
$$;

revoke all on function private.shift_totals(uuid,uuid,timestamptz,timestamptz), private.shift_guard(uuid),
  private.shift_open_impl(uuid,numeric), private.shift_close_impl(uuid,numeric,text), private.shift_report_impl(uuid,date,date) from public, anon;
grant execute on function private.shift_totals(uuid,uuid,timestamptz,timestamptz), private.shift_guard(uuid),
  private.shift_open_impl(uuid,numeric), private.shift_close_impl(uuid,numeric,text), private.shift_report_impl(uuid,date,date) to authenticated;

create or replace function public.shift_open(p_org uuid, p_float numeric)
returns uuid language sql security invoker set search_path = '' as $$ select private.shift_open_impl(p_org, p_float) $$;
create or replace function public.shift_close(p_org uuid, p_counted numeric, p_note text default null)
returns jsonb language sql security invoker set search_path = '' as $$ select private.shift_close_impl(p_org, p_counted, p_note) $$;
create or replace function public.shift_report(p_org uuid, p_from date, p_to date)
returns table (id uuid, user_id uuid, name text, opened_at timestamptz, closed_at timestamptz, opening_float numeric,
               cash_sales numeric, digital_sales numeric, cash_in numeric, cash_out numeric,
               expected_cash numeric, counted_cash numeric, difference numeric, note text)
language sql stable security invoker set search_path = '' as $$ select * from private.shift_report_impl(p_org, p_from, p_to) $$;
revoke all on function public.shift_open(uuid,numeric), public.shift_close(uuid,numeric,text), public.shift_report(uuid,date,date) from public, anon;
grant execute on function public.shift_open(uuid,numeric), public.shift_close(uuid,numeric,text), public.shift_report(uuid,date,date) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cash_shifts') then
    alter publication supabase_realtime add table public.cash_shifts;
  end if;
end $$;

comment on table public.cash_shifts is 'Turnos de caja por cajero (v3.8c): fondo, cierre ciego y diferencia (shift_report solo para finanzas).';
commit;
notify pgrst, 'reload schema';
