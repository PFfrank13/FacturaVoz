# Evidencia v3.4 — implementado, probado y desplegado (por separado)

## Hallazgos de la orden de producción
| § | Qué fallaba | Causa raíz | Corrección | Prueba | Estado |
|---|---|---|---|---|---|
| 3 | "Todavía no vemos una licencia activa" y la extensión del Hub no llega | Empresa en `source=local`; webhook/cron saltaban `local`; `org_mode` de producción con deriva; la app ocultaba el error real (`catch (_)`) | `20261209` (solo Hub, conversión respaldada, reconciliación verificada), backend sin excepción local, `POST /api/license/refresh`, motivo exacto en la app | `run_upgrade.sh` (24 comprobaciones), `licencias-v34.test.ts`, `solvex_activation_gate_test` | Implementado y probado. **No desplegado** |
| 4 | Migraciones que convierten Hub en local | 20261201/20261202 | Sin efecto sobre datos; 20261209 respalda y revierte | `licencias-v34.test.ts`, `test_v34_licencias` | Implementado y probado |
| 5 | Emisión sin producto | `min(uuid)` + descuento por coincidencia de descripción | Stock solo con `product_id`; dictado vincula SOLO nombre exacto y visible | `test_v34_stock` (8), `catalog_link_test` (5), `test_sunat` | Implementado y probado |
| 6 | Administrador con privilegios comerciales | `pay_url`/`can.license` | `20261207` + UI | `test_v33_suscripcion` | Probado; no desplegado |
| 7 | RLS por fila lenta | `has_feature` por fila | `20261208` | `test_v33_rls_funciones`, bench 450 → 7 ms | Probado; no desplegado |
| 8 | Cobro duplicado con reintento manual | id nuevo por toque | Intento persistido (cifrado) hasta estado final; bloqueo por objetivo; "pendiente de confirmar" en Inicio | `financial_intent_test` (6), `test_v33_idempotencia` | Implementado y probado |
| 9 | Datos de otra empresa tras cambiar | Respuestas tardías aplicadas | `dataScope` + ticket por consulta; Inicio con clave por empresa; al cambiar se cierran las pantallas abiertas | Revisión de código | Implementado; **falta prueba de widget** |
| 10 | Cambio de plan abría el mismo enlace sin intención | Sin confirmación | Confirmación y aviso de que solo el Hub activa | — | Parcial: **falta API de catálogo/checkout del Hub** |
| 11 | 404 en `/solvex/ir/{org}` | La ruta no existía | Ruta que lleva a `/erp/{org}` con sesión; regreso seguro tras login (`safeNext`) | `licencias-v34.test.ts` | Implementado; no desplegado |

## Verificación ejecutada aquí
- PostgreSQL 17.2 local: 48 migraciones desde cero + 15 pruebas SQL **pasan**; actualización desde la réplica de producción **pasa**; rollback **restaura el estado exacto**.
- Flutter y backend (`npm test`): no se pueden ejecutar en este entorno (sin SDK; npm bloqueado). Los corre el CI del PR.

## Pendientes reales (no implementados en esta entrega)
1. **Catálogo comercial y checkout desde el Hub** (§10): el Hub documentado solo expone licencias, pruebas y latido. Se necesita del Hub un endpoint de catálogo (plan, precio, moneda, ciclo, prueba, límites) y uno de intención de compra por plan. Sin eso no se muestran precios como verdad.
2. **Roles especializados en backend** (§12) y **multisucursal** (§13): requieren diseño de esquema (`staff_role` ampliado con permisos por fila, `branches` + `branch_id` solo en ventas/caja/stock). No iniciados.
3. **Advertencias del asesor de seguridad de Supabase** (§15): pendientes de revisión una por una.
4. **Android release, firma e instalación real** (§16C): requiere SDK, keystore y dispositivo/emulador.
5. **E2E comercial contra staging** (§16E): requiere un proyecto Supabase de staging y una instancia de pruebas del Hub.
