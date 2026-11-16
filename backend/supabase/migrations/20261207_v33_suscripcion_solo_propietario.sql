-- v3.3 · Prompt Maestro §4/§13: el ADMINISTRADOR no gestiona la suscripción; solo el PROPIETARIO.
-- Antes: my_license() entregaba pay_url (enlace de pago del plan) a propietario y administrador, y
-- my_access().can.license era true para ambos. La app ya lo ocultaba; ahora lo decide la base.
-- No cambia la ACTIVACIÓN de la licencia (api/license/activate sigue aceptando propietario o administrador).
-- Idempotente. Probar en staging antes de producción.
begin;
CREATE OR REPLACE FUNCTION private.my_access_impl(p_org uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      'license', m.role = 'owner',
      'import', v_role in ('owner', 'admin', 'finanzas')));
end;
$function$
;

CREATE OR REPLACE FUNCTION private.my_license_impl(p_org uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  l public.org_licenses;
  v_admin boolean;
  v_owner boolean;
  v_mode text;
  v_features jsonb;
begin
  if not exists (select 1 from public.organization_members m where m.org_id = p_org and m.user_id = (select auth.uid())) then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  v_admin := private.is_org_admin(p_org);
  v_owner := exists (select 1 from public.organization_members m where m.org_id = p_org and m.user_id = (select auth.uid()) and m.role = 'owner');
  v_mode := private.org_mode(p_org);
  select * into l from public.org_licenses where org_id = p_org;
  v_features := private.effective_features(p_org);
  return jsonb_build_object(
    'enforced', private.license_enforced(),
    'dev', not private.license_enforced(),
    'source', l.source,
    'mode', v_mode,
    'plan', coalesce(l.plan, 'EMPRESA'),
    'status', l.status,
    'features', v_features,
    'message', l.message,
    'pay_url', case when v_owner then l.pay_url end,
    'period_end', l.period_end,
    'grace_end', l.grace_end,
    'cut_at', coalesce(l.cut_at, l.grace_end),
    'is_trial', l.status = 'prueba',
    'last_sync_at', case when v_admin then l.last_sync_at end,
    'stale', l.source = 'hub' and l.token_exp is not null and l.token_exp < now(),
    'trial_requested', l.trial_requested_at is not null,
    'is_admin', v_admin);
end;
$function$;

commit;
