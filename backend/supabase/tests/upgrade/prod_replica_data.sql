\set ON_ERROR_STOP 1
-- Réplica sintética del estado de producción (sin datos reales): 1 empresa bodega, propietario, 1 comprobante,
-- licencia de prueba del Hub que luego 20261108223032 convirtió en local.
insert into private.app_config(key, value) values ('license_enforced', 'true'::jsonb) on conflict (key) do update set value = excluded.value;
insert into auth.users(id, email) values ('aaaaaaaa-0000-4000-8000-000000000001', 'dueno@bodega.pe');
-- Estado anterior: prueba del Hub (token y código), igual que el respaldo encontrado en producción.
-- Producción tiene 0 filas en org_license_activations (la prueba no pasó por la activación con código).
update public.org_licenses set source = 'hub', plan = 'BASICO', status = 'prueba', mode = 'full', features = private.all_features(),
  license_code = 'LIC-PRUEBA-0001', token = 'token-hub-anterior', token_iat = 1794134255, token_exp = '2026-11-11 05:00+00',
  period_end = '2026-11-11 04:59:59.999+00'
 where org_id = (select org_id from public.organization_members where user_id = 'aaaaaaaa-0000-4000-8000-000000000001');
insert into public.org_settings(org_id, business_type) select org_id, 'bodega' from public.organization_members where user_id = 'aaaaaaaa-0000-4000-8000-000000000001' on conflict (org_id) do update set business_type = 'bodega';
-- Datos de negocio que deben sobrevivir
insert into public.products(org_id, user_id, name, unit_price, unit, stock, active)
select org_id, user_id, 'Arroz 1kg', 4.5, 'NIU', 50, true from public.organization_members where user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
