# Cambios v1.1 "Negocio Pro" — qué reemplazar

Detalle funcional y pasos de despliegue: docs/NEGOCIO_PRO.md

## Orden de integración
1. Supabase → SQL Editor → backend/supabase/migrations/20261101_negocio_pro.sql
2. Vercel → variables SECRETS_KEY, CRON_SECRET, PUBLIC_BASE_URL (ver backend/.env.example)
3. Copia la carpeta completa sobre tu repo → git push (Vercel redepliega el backend)
4. app/: flutter pub get → dart run tool/post_create.dart → flutter analyze && flutter test → flutter run (mismo comando)

## Archivos nuevos
backend/supabase/migrations/20261101_negocio_pro.sql
backend/src/lib/{assistant,collections,cron,crypto,groq,mercadopago,publicbase,publicdata,scan}.ts
backend/src/app/api/assistant/route.ts
backend/src/app/api/scan/route.ts
backend/src/app/api/public/{quote,claim,mp}/route.ts
backend/src/app/api/pay/settings/route.ts
backend/src/app/api/pay/mp/webhook/route.ts
backend/src/app/api/cron/collections/route.ts
backend/src/app/cotizacion/[token]/page.tsx
backend/src/app/pagar/[token]/page.tsx
backend/src/components/public/{Shell,QuoteActions,PayActions}.tsx
backend/tests/pro.test.ts
app/lib/{finance,models_pro}.dart
app/lib/ui/motion.dart
app/lib/services/{pro_api,pro_repo}.dart
app/lib/screens/{assistant,collections,expenses,pay_settings,profit,quotes,scan,share_sheet,shell}.dart
app/test/finance_test.dart
docs/NEGOCIO_PRO.md

## Archivos modificados
README.md
backend/.env.example · backend/vercel.json (2.º cron) · backend/src/middleware.ts (rutas públicas)
backend/src/app/layout.tsx (idioma es) · backend/src/lib/supabase/admin.ts (comentario)
app/pubspec.yaml (image_picker, flutter_tts; versión 1.1.0+2) · app/tool/post_create.dart (permisos)
app/lib/main.dart (MainShell) · app/lib/app_state.dart (señal dataVersion)
app/lib/models.dart (stock, Mercado Pago) · app/lib/services/repo.dart (stock, saveProduct devuelve id)
app/lib/ui/widgets.dart (shimmer, rebote) · app/lib/screens/home.dart (avisos del día, Copiloto)
app/lib/screens/new_invoice.dart (modo cotización, borrador inicial, score de crédito)
app/lib/screens/invoice_detail.dart (enlace de cobro) · app/lib/screens/products.dart (stock)
app/lib/screens/settings.dart (Cobros y recordatorios, Gastos)
