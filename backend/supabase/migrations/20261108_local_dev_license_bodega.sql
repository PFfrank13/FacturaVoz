-- Independent, tenant-scoped development mode. Hub enforcement stays ON globally.
-- A restorable snapshot is kept in private, with no API grants.
begin;
create table if not exists private.standalone_license_backups (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  snapshot jsonb not null,
  saved_at timestamptz not null default now()
);
alter table private.standalone_license_backups enable row level security;
revoke all on private.standalone_license_backups from public, anon, authenticated;

create or replace function private.effective_features(p_org uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  l public.org_licenses;
  v_rubro text;
  k text;
  v jsonb;
  out jsonb := '{}'::jsonb;
  allowed text[];
begin
  if not private.license_enforced() then return private.all_features(); end if;
  select * into l from public.org_licenses where org_id=p_org;
  if not found then return '{}'::jsonb; end if;
  if l.source='dev' then return private.all_features(); end if;
  select business_type into v_rubro from public.org_settings where org_id=p_org;
  if l.source='local' then
    allowed := private.plan_matrix(v_rubro,l.plan);
    for k,v in select * from jsonb_each(private.all_features()) loop
      if jsonb_typeof(v)='boolean' then
        out := out || jsonb_build_object(k,k=any(allowed));
      else
        out := out || jsonb_build_object(k,case k
          when 'max_users' then to_jsonb(case l.plan when 'BASICO' then 1 when 'PRO' then 5 else 20 end)
          when 'max_branches' then to_jsonb(case when l.plan='EMPRESA' then 5 else 1 end)
          else v end);
      end if;
    end loop;
    return out;
  end if;
  for k,v in select * from jsonb_each(private.all_features()) loop
    if jsonb_typeof(v)='boolean' then
      out := out || jsonb_build_object(k,private.plan_allows(v_rubro,l.plan,coalesce(l.features,'{}'::jsonb),k));
    else
      out := out || jsonb_build_object(k,coalesce(l.features->k,v));
    end if;
  end loop;
  return coalesce(l.features,'{}'::jsonb) || out;
end;
$$;

-- Only the existing test bodega, never unrelated tenants.
insert into private.standalone_license_backups(org_id,snapshot)
select l.org_id,to_jsonb(l) from public.org_licenses l
join public.org_settings s on s.org_id=l.org_id
where s.business_type='bodega' and l.plan='BASICO' and l.source='hub'
  and (select count(*) from public.organizations)=1
on conflict(org_id) do nothing;

update public.org_licenses l set
  source='local', status='desarrollo', mode='full',
  period_end=null, message='Plan Básico local de desarrollo (sin sincronización externa)',
  auto_cut=false
from private.standalone_license_backups b
where b.org_id=l.org_id and l.source='hub' and l.plan='BASICO'
  and (select count(*) from public.organizations)=1;
commit;
notify pgrst, 'reload schema';
