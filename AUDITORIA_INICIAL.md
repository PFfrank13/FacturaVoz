# Auditoría inicial — Solvex Retail, etapa 1

Continuidad sobre el trabajo local existente (sin descartarlo). Referencia: docs/ERP_AUDITORIA_Y_ALCANCE.md y ERP_AVANCE_2026-11-07.md. Esta revisión sustituye el alcance nuevo de nueve rubros por retail. Las correcciones explícitas del usuario prevalecen sobre ambos PDF. No se borra ningún módulo en esta fase.

| Elementos existentes | Decisión | Motivo / evidencia |
|---|---|---|
| Autenticación, Access, workspaceContext, Solvex Hub | MANTENER | Separación de empresa, rol y licencia; no conceder offline derechos por caché |
| POS Flutter, PointOfSale web y fast_checkout_atomic | REFACTORIZAR | Cobro depende de red; ticket volátil; dinero double/number; conservar RPC compatible |
| products, productExtras, catálogo y búsquedas | REFACTORIZAR | Catálogo compartido con stock; separar versiones de precios y presentaciones sin perder IDs |
| stock / apply_stock_on_issue / stockAdjust | REFACTORIZAR | Persistencia legacy con campo editable; no es kardex integral ni stock físico/disponible/reservado/tránsito |
| caja, pagos y reportes | REFACTORIZAR | Separar registro de pago de verificación externa; cierre ciego y bitácora requieren integración |
| clientes, gastos, compras/importación, precios | MANTENER | Reutilizables; expansión funcional en etapa 2 después de puerta 1 |
| voz, OCR, parse/transcribe, copiloto, SUNAT | MANTENER | Conservar servicios y contratos; no anunciar asistente retail nuevo ni ampliar fuera de etapa |
| inicio, login, onboarding, navegación, temas | REFACTORIZAR | Cambiar composición e identidad visible; POS centrado en ticket/acción, Control en administración |
| restaurante, salón, talleres, consultorio, educación, construcción | MANTENER (compatibilidad) | Fuera de desarrollo nuevo; tienen servicios/tablas compartidas e históricos; no borrar dependencias |
| pruebas existentes y docs históricos | MANTENER | Evidencia fechada; no renombrar historia como si fuera prueba del producto nuevo |
| Android applicationId, paquetes Dart, deep links, API, esquema, env, infraestructura | MANTENER | Identificadores externos requieren migración independiente; cero cambios productivos |

## Riesgos confirmados y alcance

- El POS necesita respuesta del servidor para cobrar. No hay evidencia de siete días offline, sincronización o recuperación durable de ventas. No habilitar una confirmación offline ficticia.
- El ticket web vive en useState. El ticket Flutter vive en un Map del widget. La recuperación local de borradores es un paso independiente de la confirmación de ventas.
- El código monetario actual usa double/number. Incorporar aritmética entera sin alterar silenciosamente contratos históricos.
- RLS completa y caja requieren laboratorio. Docker no estaba disponible en la intervención anterior. No se consultó producción para verificarlo.
- No se volcaron secretos. Se mantienen intactas sus configuraciones y archivos.
- BORRAR: ningún elemento aprobado en esta revisión; retirada técnica requiere mapa de dependencias y prueba de recuperación.

## Inventario reproducible de archivos por dominio

### app/lib/screens (64 archivos)

- app/lib/screens/agent.dart
- app/lib/screens/api_access.dart
- app/lib/screens/assistant.dart
- app/lib/screens/bank_recon.dart
- app/lib/screens/branding.dart
- app/lib/screens/business_setup.dart
- app/lib/screens/cash_day.dart
- app/lib/screens/catalog.dart
- app/lib/screens/client_profile.dart
- app/lib/screens/clients.dart
- app/lib/screens/clients360.dart
- app/lib/screens/clients_hub.dart
- app/lib/screens/collections.dart
- app/lib/screens/emit_sunat.dart
- app/lib/screens/employee_login.dart
- app/lib/screens/expenses.dart
- app/lib/screens/fiados.dart
- app/lib/screens/fiscal_setup.dart
- app/lib/screens/goal_sheet.dart
- app/lib/screens/home.dart
- app/lib/screens/hubs_v3.dart
- app/lib/screens/import_screen.dart
- app/lib/screens/inicio.dart
- app/lib/screens/invoice_detail.dart
- app/lib/screens/jobs.dart
- app/lib/screens/kitchen.dart
- app/lib/screens/legal.dart
- app/lib/screens/license_gate.dart
- app/lib/screens/lock_screen.dart
- app/lib/screens/login.dart
- app/lib/screens/menu.dart
- app/lib/screens/new_invoice.dart
- app/lib/screens/notebook.dart
- app/lib/screens/notices.dart
- app/lib/screens/onboarding.dart
- app/lib/screens/orgs.dart
- app/lib/screens/owner_control.dart
- app/lib/screens/pay_settings.dart
- app/lib/screens/payments_card.dart
- app/lib/screens/pos.dart
- app/lib/screens/products.dart
- app/lib/screens/profile_form.dart
- app/lib/screens/profit.dart
- app/lib/screens/promos.dart
- app/lib/screens/quotes.dart
- app/lib/screens/recurring.dart
- app/lib/screens/reports.dart
- app/lib/screens/rubro_picker.dart
- app/lib/screens/rubro_tools.dart
- app/lib/screens/scan.dart
- app/lib/screens/security.dart
- app/lib/screens/sell_hub.dart
- app/lib/screens/settings.dart
- app/lib/screens/settings_v2.dart
- app/lib/screens/share_sheet.dart
- app/lib/screens/shell.dart
- app/lib/screens/store.dart
- app/lib/screens/store_v2.dart
- app/lib/screens/surveys.dart
- app/lib/screens/taxes.dart
- app/lib/screens/team.dart
- app/lib/screens/trash.dart
- app/lib/screens/welcome_employee.dart
- app/lib/screens/workbook_import.dart

### app/lib/services (22 archivos)

- app/lib/services/api.dart
- app/lib/services/app_lock.dart
- app/lib/services/boot_cache.dart
- app/lib/services/growth_repo.dart
- app/lib/services/importer.dart
- app/lib/services/live.dart
- app/lib/services/location.dart
- app/lib/services/pdf_builder.dart
- app/lib/services/print/kitchen_print.dart
- app/lib/services/print/net_print_io.dart
- app/lib/services/print/net_print_stub.dart
- app/lib/services/print/ticket_printer.dart
- app/lib/services/pro_api.dart
- app/lib/services/pro_repo.dart
- app/lib/services/quick_launch.dart
- app/lib/services/repo.dart
- app/lib/services/rubro_apply.dart
- app/lib/services/rubro_repo.dart
- app/lib/services/v2_api.dart
- app/lib/services/v2_repo.dart
- app/lib/services/voice.dart
- app/lib/services/workbook_import.dart

### app/lib/logic (18 archivos)

- app/lib/logic/appointments.dart
- app/lib/logic/bank_match.dart
- app/lib/logic/credit.dart
- app/lib/logic/cutoff.dart
- app/lib/logic/doc_voice.dart
- app/lib/logic/escpos.dart
- app/lib/logic/notice_parser.dart
- app/lib/logic/obra.dart
- app/lib/logic/pay_score.dart
- app/lib/logic/pos_kitchen.dart
- app/lib/logic/pricing.dart
- app/lib/logic/regulars.dart
- app/lib/logic/sample_catalog.dart
- app/lib/logic/scan_checks.dart
- app/lib/logic/search_score.dart
- app/lib/logic/stagnant.dart
- app/lib/logic/tables.dart
- app/lib/logic/taxes.dart

### backend/src/app (61 archivos)

- backend/src/app/actions/invoices.ts
- backend/src/app/api/agent/decide/route.ts
- backend/src/app/api/agent/route.ts
- backend/src/app/api/assistant/route.ts
- backend/src/app/api/cron/collections/route.ts
- backend/src/app/api/cron/daily/route.ts
- backend/src/app/api/cron/solvex-sync/route.ts
- backend/src/app/api/cron/webhooks/route.ts
- backend/src/app/api/day-close/route.ts
- backend/src/app/api/email/send/route.ts
- backend/src/app/api/fiscal/emit/route.ts
- backend/src/app/api/fiscal/note/route.ts
- backend/src/app/api/fiscal/setup/route.ts
- backend/src/app/api/fx/route.ts
- backend/src/app/api/health/route.ts
- backend/src/app/api/import/notify/route.ts
- backend/src/app/api/import/workbook/route.ts
- backend/src/app/api/license/activate/route.ts
- backend/src/app/api/license/trial/route.ts
- backend/src/app/api/lookup/route.ts
- backend/src/app/api/notebook/route.ts
- backend/src/app/api/parse/route.ts
- backend/src/app/api/pay/mp/webhook/route.ts
- backend/src/app/api/pay/settings/route.ts
- backend/src/app/api/public/book/route.ts
- backend/src/app/api/public/claim/route.ts
- backend/src/app/api/public/doc/route.ts
- backend/src/app/api/public/mp/route.ts
- backend/src/app/api/public/order/route.ts
- backend/src/app/api/public/quote/route.ts
- backend/src/app/api/public/survey/route.ts
- backend/src/app/api/scan/route.ts
- backend/src/app/api/solvex/webhook/route.ts
- backend/src/app/api/transcribe/route.ts
- backend/src/app/api/tts/route.ts
- backend/src/app/api/v1/clients/route.ts
- backend/src/app/api/v1/invoices/route.ts
- backend/src/app/api/v1/orders/route.ts
- backend/src/app/api/v1/products/route.ts
- backend/src/app/auth/callback/route.ts
- backend/src/app/comprobante/[token]/page.tsx
- backend/src/app/cotizacion/[token]/page.tsx
- backend/src/app/encuesta/[token]/page.tsx
- backend/src/app/erp/[org]/[module]/page.tsx
- backend/src/app/erp/[org]/error.tsx
- backend/src/app/erp/[org]/layout.tsx
- backend/src/app/erp/[org]/loading.tsx
- backend/src/app/erp/[org]/page.tsx
- backend/src/app/erp/actions.ts
- backend/src/app/erp/checkout.ts
- backend/src/app/favicon.ico
- backend/src/app/globals.css
- backend/src/app/layout.tsx
- backend/src/app/login/page.tsx
- backend/src/app/pagar/[token]/page.tsx
- backend/src/app/page.tsx
- backend/src/app/portal/[token]/page.tsx
- backend/src/app/reservar/[slug]/page.tsx
- backend/src/app/tienda/[slug]/manifest.webmanifest/route.ts
- backend/src/app/tienda/[slug]/p/[id]/page.tsx
- backend/src/app/tienda/[slug]/page.tsx

### backend/src/lib (41 archivos)

- backend/src/lib/agent.ts
- backend/src/lib/api-auth.ts
- backend/src/lib/apikey.ts
- backend/src/lib/assistant.ts
- backend/src/lib/collections.ts
- backend/src/lib/cron.ts
- backend/src/lib/crypto.ts
- backend/src/lib/dayclose.ts
- backend/src/lib/doclookup.ts
- backend/src/lib/email.ts
- backend/src/lib/erp/access.ts
- backend/src/lib/erp/context.ts
- backend/src/lib/fiscal/calc.ts
- backend/src/lib/fiscal/cert.ts
- backend/src/lib/fiscal/ids.ts
- backend/src/lib/fiscal/lycet.ts
- backend/src/lib/fiscal/note.ts
- backend/src/lib/fiscal/payload.ts
- backend/src/lib/fiscal/words.ts
- backend/src/lib/fx.ts
- backend/src/lib/groq.ts
- backend/src/lib/license-check.ts
- backend/src/lib/mercadopago.ts
- backend/src/lib/notebook.ts
- backend/src/lib/publicbase.ts
- backend/src/lib/publicdata.ts
- backend/src/lib/publicdocs.ts
- backend/src/lib/qr.ts
- backend/src/lib/rubro-copilot.ts
- backend/src/lib/scan.ts
- backend/src/lib/schemas.ts
- backend/src/lib/solvex.ts
- backend/src/lib/storeseo.ts
- backend/src/lib/supabase/admin.ts
- backend/src/lib/supabase/client.ts
- backend/src/lib/supabase/server.ts
- backend/src/lib/taxes.ts
- backend/src/lib/tts.ts
- backend/src/lib/webhooks.ts
- backend/src/lib/workbook-import.ts
- backend/src/lib/xlsx.ts

### backend/supabase/migrations (34 archivos)

- backend/supabase/migrations/20261023_mobile_prod.sql
- backend/supabase/migrations/20261024_fiscal_sunat.sql
- backend/supabase/migrations/20261025_credit_notes.sql
- backend/supabase/migrations/20261026_harden_fiscal.sql
- backend/supabase/migrations/20261027_multitenant.sql
- backend/supabase/migrations/20261028_multitenant_fiscal.sql
- backend/supabase/migrations/20261029_products.sql
- backend/supabase/migrations/20261030_payments.sql
- backend/supabase/migrations/20261031_imports.sql
- backend/supabase/migrations/20261101_negocio_pro.sql
- backend/supabase/migrations/20261102_revolucion.sql
- backend/supabase/migrations/20261103_permisos_service_role.sql
- backend/supabase/migrations/20261104_fase0_permisos_app.sql
- backend/supabase/migrations/20261105_sunat_marca.sql
- backend/supabase/migrations/20261106_crm.sql
- backend/supabase/migrations/20261107_equipo_roles.sql
- backend/supabase/migrations/20261108_tienda_productos.sql
- backend/supabase/migrations/20261109_modulos_dinero.sql
- backend/supabase/migrations/20261110_modulos_conexion.sql
- backend/supabase/migrations/20261111_licencias.sql
- backend/supabase/migrations/20261112_servicios.sql
- backend/supabase/migrations/20261113_v3_totales_importador.sql
- backend/supabase/migrations/20261114_v3_rendimiento_rls.sql
- backend/supabase/migrations/20261115_v3_rubros.sql
- backend/supabase/migrations/20261116_v3_voz_documentos.sql
- backend/supabase/migrations/20261117_v31_rubro_bloqueado.sql
- backend/supabase/migrations/20261118_v31_planes_por_rubro.sql
- backend/supabase/migrations/20261119_v31_tiempo_real.sql
- backend/supabase/migrations/20261120_v31_endurecimiento.sql
- backend/supabase/migrations/20261121_v31_tiempo_real_2.sql
- backend/supabase/migrations/20261122_v31_comandas_caja_persistentes.sql
- backend/supabase/migrations/20261123_v31_fast_checkout_atomic.sql
- backend/supabase/migrations/20261124_v31_solvex_activation_required.sql
- backend/supabase/migrations/20261125_v32_hub_feature_precedence.sql
