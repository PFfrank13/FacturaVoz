# Cambios v1.2 "Revolución" — qué reemplazar
Detalle: docs/REVOLUCION.md

1. Supabase → backend/supabase/migrations/20261102_revolucion.sql
2. Copia la carpeta completa → git push
3. app/: flutter pub get → (PowerShell) flutter analyze; flutter test

Nuevos: migrations/20261102_revolucion.sql · backend/src/app/api/public/order/route.ts · backend/src/app/tienda/[slug]/page.tsx ·
backend/src/components/public/StoreCart.tsx · app/lib/{growth,models_growth}.dart · app/lib/services/growth_repo.dart ·
app/lib/screens/{clients360,recurring,store,goal_sheet}.dart · app/test/growth_test.dart · docs/REVOLUCION.md
Modificados: backend middleware.ts, lib/assistant.ts, lib/publicdata.ts, api/assistant/route.ts, tests/pro.test.ts ·
app: home.dart, quotes.dart, products.dart, profit.dart, assistant.dart, invoice_detail.dart, settings.dart, finance.dart,
models.dart, models_pro.dart, services/repo.dart, services/pro_repo.dart, ui/motion.dart, pubspec.yaml (1.2.0+3)

## Corrección 42501 (permiso denegado) en /api/cron/collections
Ejecuta en Supabase → SQL Editor: backend/supabase/migrations/20261103_permisos_service_role.sql
(da al servidor acceso al esquema private y a las funciones/tablas que usan el cron, la tienda y los pagos).
