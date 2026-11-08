-- Standalone Bodega development: remove expired Hub trial copy.
-- Only modifies the single backed-up test company; production tenant guard stays enforced.
begin;
update public.org_licenses l set status='activa', period_end=null, grace_end=null, cut_at=null, auto_cut=false,
  message='Plan Básico local de desarrollo; sin vencimiento comercial externo'
from private.standalone_license_backups b
join public.org_settings s on s.org_id=b.org_id
where l.org_id=b.org_id and l.source='local' and l.plan='BASICO'
  and s.business_type='bodega'
  and (select count(*) from public.organizations)=1;
commit;
notify pgrst, 'reload schema';
