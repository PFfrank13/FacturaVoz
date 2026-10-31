-- FacturaVoz · v3.1 · Rubro bloqueado
-- Una vez elegido el rubro, el CLIENTE ya no puede cambiarlo desde la app (ni por la API): solo la plataforma
-- (SQL Editor / service_role) lo cambia, sin tocar clientes, ventas, productos ni trabajos.
-- Aditiva e idempotente. Ejecutar después de 20261116.
begin;

-- 1) Candado: un usuario de la app (authenticated/anon) no puede cambiar business_type si ya tenía un rubro.
--    Empresas con 'otro' (aún sin elegir) pueden elegir UNA vez; después queda fijo.
create or replace function private.lock_rubro()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and new.business_type is distinct from old.business_type
     and old.business_type <> 'otro'
     and current_user in ('authenticated', 'anon') then
    raise exception 'El rubro del negocio ya fue elegido y no se puede cambiar desde la app. Escríbenos y lo cambiamos por ti sin perder tus datos.'
      using errcode = '42501';
  end if;
  return new;
end
$$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_lock_rubro' and tgrelid = 'public.org_settings'::regclass) then
    create trigger trg_lock_rubro before update on public.org_settings
      for each row execute function private.lock_rubro();
  end if;
end $$;

-- 2) Cambio de rubro hecho por la plataforma (tú). No borra ningún dato del negocio:
--    solo cambia el rubro y limpia las personalizaciones de pantalla del rubro anterior
--    (módulos a la vista, pasos de trabajo, campos extra y palabras) para que se vea la app del nuevo rubro.
--    Los trabajos ya creados conservan su estado guardado.
--    Uso (SQL Editor):  select private.admin_set_rubro('<id de la empresa>', 'restaurante');
create or replace function private.admin_set_rubro(p_org uuid, p_rubro text, p_reset_overrides boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text;
begin
  if p_rubro is null or p_rubro not in ('bodega', 'restaurante', 'servicios_tecnicos', 'salon', 'consultorio', 'taller', 'mayorista', 'educacion', 'construccion') then
    raise exception 'Rubro no válido: %. Usa: bodega, restaurante, servicios_tecnicos, salon, consultorio, taller, mayorista, educacion o construccion.', p_rubro;
  end if;
  select business_type into v_old from public.org_settings where org_id = p_org;
  if not found then
    raise exception 'La empresa % no tiene configuración de negocio todavía (el dueño aún no abrió la app).', p_org;
  end if;
  update public.org_settings
     set business_type = p_rubro,
         onboarding_done = true,
         modules = case when p_reset_overrides then '{}'::jsonb else modules end,
         job_statuses = case when p_reset_overrides then '[]'::jsonb else job_statuses end,
         client_fields = case when p_reset_overrides then '[]'::jsonb else client_fields end,
         labels = case when p_reset_overrides then (labels - 'job' - 'jobs') else labels end,
         updated_at = now()
   where org_id = p_org;
  perform private.audit(p_org, 'rubro.cambiado_plataforma', 'org_settings', p_org::text,
                        jsonb_build_object('de', v_old, 'a', p_rubro, 'limpio', p_reset_overrides));
  return jsonb_build_object('empresa', p_org, 'de', v_old, 'a', p_rubro);
end
$$;
revoke all on function private.admin_set_rubro(uuid, text, boolean) from public, anon, authenticated;
grant execute on function private.admin_set_rubro(uuid, text, boolean) to service_role;

commit;
