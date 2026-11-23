-- v3.8a · Cupones también con «Puntos y fidelización» (plan Pro de bodega), no solo con «Precios y promociones».
-- docs/INVESTIGACION_RETAIL.md, fila 11. Solo amplía quién puede usar cupones; no cambia datos.
-- Cambia sobre la definición vigente (no la reescribe a mano): feature_for devuelve 'precios|fidelizacion' para
-- coupons y license_guard acepta cualquiera de las funciones separadas por '|'.
begin;

create or replace function private.has_any_feature(p_org uuid, p_features text)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from unnest(string_to_array(p_features, '|')) f(k) where private.has_feature(p_org, f.k)) $$;
revoke all on function private.has_any_feature(uuid, text) from public, anon;
grant execute on function private.has_any_feature(uuid, text) to authenticated, service_role;

do $$
declare
  f text := pg_get_functiondef('private.feature_for(text,jsonb)'::regprocedure);
  g text := pg_get_functiondef('private.license_guard()'::regprocedure);
  needle_f text := 'when ''coupons'' then ''precios''';
  needle_g text := 'not private.has_feature(v_org, v_feature)';
begin
  if (length(f) - length(replace(f, needle_f, ''))) / length(needle_f) <> 1 then
    raise exception 'feature_for no tiene la forma esperada; no se modifica';
  end if;
  if (length(g) - length(replace(g, needle_g, ''))) / length(needle_g) <> 2 then
    raise exception 'license_guard no tiene la forma esperada; no se modifica';
  end if;
  execute replace(f, needle_f, 'when ''coupons'' then ''precios|fidelizacion''');
  execute replace(g, needle_g, 'not private.has_any_feature(v_org, v_feature)');
end $$;

alter policy hub_feature_read_coupons on public.coupons
  using (org_id = any ((select private.my_feature_org_ids('precios'))::uuid[])
      or org_id = any ((select private.my_feature_org_ids('fidelizacion'))::uuid[]));

commit;
notify pgrst, 'reload schema';
