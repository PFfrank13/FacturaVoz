-- Copia EXACTA (lógica) de private.org_mode() leída en producción el 2026-11-17: acepta local/dev como 'full'.
create or replace function private.org_mode(p_org uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare l public.org_licenses;
begin
  if not private.license_enforced() then return 'full'; end if;
  select * into l from public.org_licenses where org_id = p_org;
  if not found then return 'blocked'; end if;
  if l.source in ('local', 'dev') then
    return case when l.period_end is null or now() <= l.period_end then 'full' else 'blocked' end;
  end if;
  if l.mode in ('full', 'warning') and l.auto_cut and coalesce(l.cut_at, l.grace_end) is not null
     and now() > coalesce(l.cut_at, l.grace_end) then
    return 'restricted';
  end if;
  return l.mode;
end $$;
