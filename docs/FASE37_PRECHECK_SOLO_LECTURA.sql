-- Diagnóstico sin modificar datos: ejecutar antes de la migración 20261124.
-- Si aparece cualquier licencia local/dev, quedará bloqueada al aplicar Fase 37.
select source, status, mode, count(*) as empresas
from public.org_licenses
group by source, status, mode
order by source, status, mode;

select count(*) as empresas_con_empresa_sin_licencia
from public.organizations o
where not exists (select 1 from public.org_licenses l where l.org_id = o.id);

select count(*) as empresas_con_licencia_hub
from public.org_licenses
where source = 'hub';
