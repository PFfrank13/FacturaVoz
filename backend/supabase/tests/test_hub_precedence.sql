-- Run only in a disposable LOCAL database after all migrations. No business rows are touched.
begin;
do $$
declare r text; p text; k text;
begin
  foreach r in array array['bodega','restaurante','servicios_tecnicos','salon','consultorio','taller','mayorista','educacion','construccion'] loop
    foreach p in array array['BASICO','PRO','EMPRESA'] loop
      foreach k in array array['stock','facturar','clientes','cobros','voz','agenda','trabajos'] loop
        if private.plan_allows(r,p,jsonb_build_object(k,false),k) then raise exception 'Hub denial overridden: % % %',r,p,k; end if;
        if private.plan_allows(r,p,'{}'::jsonb,k) then raise exception 'Missing flag enabled: % % %',r,p,k; end if;
        if not private.plan_allows(r,p,jsonb_build_object(k,true),k) then raise exception 'Hub grant lost: % % %',r,p,k; end if;
      end loop;
    end loop;
  end loop;
  if private.plan_allows('bodega','EMPRESA','{"max_users":-1}'::jsonb,'max_users') then raise exception 'Limit treated as feature'; end if;
end;
$$;
rollback;
