-- v4.0 · PIN de entrada ligado a la CUENTA (no solo al teléfono) y PIN del dueño protegido.
-- Antes: el PIN de entrada vivía solo en cada celular. Quien entraba a la cuenta desde otro celular creaba uno nuevo sin
-- conocer el del dueño, y el PIN del dueño se podía cambiar o quitar sin escribir el actual.
-- Ahora:
--   · El PIN de entrada se guarda cifrado (bcrypt) en la cuenta. En un celular nuevo hay que escribir el PIN de siempre.
--   · Cambiarlo exige el PIN actual (Ajustes → Seguridad). Si se olvidó, solo se puede crear otro tras entrar con el
--     código que llega al correo (en los últimos 15 minutos).
--   · El PIN del dueño (anular, borrar cobros) también exige el actual para cambiarlo o quitarlo.
-- SOLO AÑADE una tabla privada y funciones; la versión de 2 parámetros de set_admin_pin sigue existiendo (ahora pide el
-- PIN actual cuando ya hay uno). No borra ni modifica datos existentes.
begin;

create table if not exists private.app_pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null,
  fails integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table private.app_pins enable row level security;
revoke all on private.app_pins from public, anon, authenticated;

-- ¿Entró con el código del correo hace menos de 15 minutos? (lo dice el token firmado por Supabase Auth)
create or replace function private.recent_email_code()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from jsonb_array_elements(coalesce((select auth.jwt()) -> 'amr', '[]'::jsonb)) e
     where e ->> 'method' in ('otp', 'magiclink', 'recovery', 'email/signup')
       and to_timestamp((e ->> 'timestamp')::double precision) > now() - interval '15 minutes'
  );
$$;

-- Espera tras fallos seguidos (igual que la app): 5→30 s, 6→1 min, 7→5 min, 8→15 min, 9+→1 h.
create or replace function private.pin_wait(p_fails integer)
returns interval language sql immutable set search_path = ''
as $$
  select case when p_fails < 5 then interval '0' when p_fails = 5 then interval '30 seconds'
              when p_fails = 6 then interval '1 minute' when p_fails = 7 then interval '5 minutes'
              when p_fails = 8 then interval '15 minutes' else interval '1 hour' end;
$$;

create or replace function private.app_pin_status_impl()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); r private.app_pins;
begin
  if v_uid is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  select * into r from private.app_pins where user_id = v_uid;
  return jsonb_build_object(
    'has_pin', found,
    'version', case when found then (extract(epoch from r.updated_at) * 1000)::bigint::text end,
    'can_reset', private.recent_email_code(),
    'wait', case when found and r.locked_until > now() then ceil(extract(epoch from r.locked_until - now()))::int else 0 end);
end;
$$;

-- Comprueba el PIN con límite de intentos en el servidor. 10 fallos seguidos → la app cierra la sesión.
create or replace function private.app_pin_verify_impl(p_pin text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); r private.app_pins; v_fails integer;
begin
  if v_uid is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  select * into r from private.app_pins where user_id = v_uid for update;
  if not found then return jsonb_build_object('ok', false, 'no_pin', true); end if;
  if r.locked_until is not null and r.locked_until > now() then
    return jsonb_build_object('ok', false, 'wait', ceil(extract(epoch from r.locked_until - now()))::int, 'fails_left', greatest(10 - r.fails, 0));
  end if;
  if coalesce(p_pin, '') ~ '^[0-9]{6}$' and extensions.crypt(p_pin, r.pin_hash) = r.pin_hash then
    update private.app_pins set fails = 0, locked_until = null where user_id = v_uid;
    return jsonb_build_object('ok', true, 'version', (extract(epoch from r.updated_at) * 1000)::bigint::text);
  end if;
  v_fails := r.fails + 1;
  update private.app_pins set fails = v_fails, locked_until = case when private.pin_wait(v_fails) > interval '0' then now() + private.pin_wait(v_fails) end
   where user_id = v_uid;
  return jsonb_build_object('ok', false, 'fails_left', greatest(10 - v_fails, 0), 'signed_out', v_fails >= 10,
                            'wait', ceil(extract(epoch from private.pin_wait(v_fails)))::int);
end;
$$;

-- Crea o cambia el PIN. Si ya existe, exige el actual (o haber entrado con el código del correo hace < 15 min).
create or replace function private.app_pin_set_impl(p_new text, p_current text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); r private.app_pins; v_check jsonb; v_at timestamptz := now();
begin
  if v_uid is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  if coalesce(p_new, '') !~ '^[0-9]{6}$' then raise exception 'El PIN debe tener 6 dígitos' using errcode = '22023'; end if;
  select * into r from private.app_pins where user_id = v_uid;
  if found and not private.recent_email_code() then
    if p_current is null then
      return jsonb_build_object('ok', false, 'error', 'Tu cuenta ya tiene un PIN. Escribe el actual para cambiarlo.');
    end if;
    v_check := private.app_pin_verify_impl(p_current);
    if not coalesce((v_check ->> 'ok')::boolean, false) then
      return v_check || jsonb_build_object('error', 'El PIN actual no es correcto.');
    end if;
  end if;
  insert into private.app_pins (user_id, pin_hash, fails, locked_until, updated_at)
  values (v_uid, extensions.crypt(p_new, extensions.gen_salt('bf', 8)), 0, null, v_at)
  on conflict (user_id) do update set pin_hash = excluded.pin_hash, fails = 0, locked_until = null, updated_at = v_at;
  return jsonb_build_object('ok', true, 'version', (extract(epoch from v_at) * 1000)::bigint::text);
end;
$$;

-- Cuerpo original de set_admin_pin (sin cambios), ahora solo se llama tras comprobar el PIN actual.
create or replace function private.set_admin_pin_impl_raw(p_org uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_salt text := replace(gen_random_uuid()::text, '-', '');
begin
  if not private.is_org_admin(p_org) then raise exception 'Solo el propietario o un administrador' using errcode = '42501'; end if;
  if p_pin is null then
    insert into public.org_security (org_id, pin_hash, pin_salt) values (p_org, null, null)
    on conflict (org_id) do update set pin_hash = null, pin_salt = null, failed = 0, locked_until = null, updated_at = now();
    perform private.audit(p_org, 'pin.desactivado', 'org', p_org::text, '{}'::jsonb);
    return;
  end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'El PIN debe tener de 4 a 8 dígitos' using errcode = '22023'; end if;
  insert into public.org_security (org_id, pin_hash, pin_salt) values (p_org, encode(sha256(convert_to(v_salt || ':' || p_pin, 'UTF8')), 'hex'), v_salt)
  on conflict (org_id) do update set pin_hash = excluded.pin_hash, pin_salt = excluded.pin_salt, failed = 0, locked_until = null, updated_at = now();
  perform private.audit(p_org, 'pin.cambiado', 'org', p_org::text, '{}'::jsonb);
end;
$$;


-- PIN del dueño: cambiarlo o quitarlo exige el actual (o el código del correo reciente). Devuelve {ok, error} para que
-- los intentos fallidos SÍ queden contados (una excepción desharía el contador).
create or replace function private.set_admin_pin_checked_impl(p_org uuid, p_pin text, p_current text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare s public.org_security;
begin
  if not private.is_org_admin(p_org) then raise exception 'Solo el propietario o un administrador' using errcode = '42501'; end if;
  select * into s from public.org_security where org_id = p_org for update;
  if found and s.pin_hash is not null and not private.recent_email_code() then
    if s.locked_until is not null and s.locked_until > now() then
      return jsonb_build_object('ok', false, 'error', 'Demasiados intentos. Espera unos minutos.');
    end if;
    if p_current is null or encode(sha256(convert_to(s.pin_salt || ':' || p_current, 'UTF8')), 'hex') <> s.pin_hash then
      update public.org_security set failed = failed + 1,
        locked_until = case when failed + 1 >= 5 then now() + interval '15 minutes' end where org_id = p_org;
      perform private.audit(p_org, 'pin.fallido', 'org', p_org::text, '{}'::jsonb);
      return jsonb_build_object('ok', false, 'error', case when p_current is null
        then 'Escribe el PIN actual del dueño para cambiarlo o quitarlo.' else 'El PIN actual del dueño no es correcto.' end);
    end if;
  end if;
  perform private.set_admin_pin_impl_raw(p_org, p_pin);
  return jsonb_build_object('ok', true);
end;
$$;

-- La versión de 2 parámetros (apps antiguas) sigue sirviendo para crear el primer PIN; para cambiarlo pide el actual.
create or replace function private.set_admin_pin_impl(p_org uuid, p_pin text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v jsonb := private.set_admin_pin_checked_impl(p_org, p_pin, null);
begin
  if not coalesce((v ->> 'ok')::boolean, false) then raise exception '%', v ->> 'error' using errcode = '28000'; end if;
end;
$$;

revoke all on function private.recent_email_code(), private.pin_wait(integer), private.app_pin_status_impl(),
  private.app_pin_verify_impl(text), private.app_pin_set_impl(text, text), private.set_admin_pin_impl_raw(uuid, text),
  private.set_admin_pin_checked_impl(uuid, text, text) from public, anon;
grant execute on function private.recent_email_code(), private.pin_wait(integer), private.app_pin_status_impl(),
  private.app_pin_verify_impl(text), private.app_pin_set_impl(text, text),
  private.set_admin_pin_checked_impl(uuid, text, text) to authenticated;

create or replace function public.app_pin_status()
returns jsonb language sql stable security invoker set search_path = '' as $$ select private.app_pin_status_impl() $$;
create or replace function public.app_pin_verify(p_pin text)
returns jsonb language sql security invoker set search_path = '' as $$ select private.app_pin_verify_impl(p_pin) $$;
create or replace function public.app_pin_set(p_new text, p_current text default null)
returns jsonb language sql security invoker set search_path = '' as $$ select private.app_pin_set_impl(p_new, p_current) $$;
create or replace function public.set_admin_pin(p_org uuid, p_pin text, p_current text)
returns jsonb language sql security invoker set search_path = '' as $$ select private.set_admin_pin_checked_impl(p_org, p_pin, p_current) $$;

revoke all on function public.app_pin_status(), public.app_pin_verify(text), public.app_pin_set(text, text),
  public.set_admin_pin(uuid, text, text) from public, anon;
grant execute on function public.app_pin_status(), public.app_pin_verify(text), public.app_pin_set(text, text),
  public.set_admin_pin(uuid, text, text) to authenticated;

comment on table private.app_pins is 'PIN de entrada de cada cuenta (bcrypt). Un celular nuevo pide el PIN de siempre (v4.0).';
commit;
notify pgrst, 'reload schema';
