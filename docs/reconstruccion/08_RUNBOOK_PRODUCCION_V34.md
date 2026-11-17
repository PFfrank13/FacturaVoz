# Runbook de producción v3.4 — licencias solo Solvex Hub, SIN corte de servicio

**No ejecutar sin autorización explícita del propietario.** Probado en PostgreSQL 17 sobre una réplica sintética del
estado real de producción (`backend/supabase/tests/upgrade/run_upgrade.sh`, también en el job `database` del CI).

## Diseño: dos fases, la empresa nunca queda bloqueada
| Fase | Qué hace | ¿Puede bloquear? |
|---|---|---|
| **A** `20261209_v34a_transicion_hub_sin_corte` | Respalda la licencia local, la pone en cola con su código del Hub, instala `license_sync_apply`, `license_preflight_state` y la corrección de stock. No toca `org_mode`, `effective_features` ni `org_licenses`. | **No** (probado: sigue `local`/`full`, se puede vender) |
| Reconciliación | El backend trae el token del Hub, verifica firma Ed25519, emisor, audiencia (instancia) y tenant. Si el código coincide, en UNA transacción la empresa pasa a `hub` + activación. Si no coincide, **no cambia nada** (`pending_code_mismatch`). | **No** (probado) |
| **B** `20261210_v34b_licencias_solo_hub` | Modo estricto: sin local/dev, control fijo, `org_mode` exige Hub + token + activación. **Se niega a ejecutarse** si queda alguna empresa local, en cola o sin activación. | **No** (probado: se detiene y no cambia nada) |

La app (todas las versiones) y la web aceptan la licencia local hasta la fase B, así que ningún orden de despliegue las corta.

## Estado verificado (2026-11-17, solo lectura)
| Elemento | Resultado |
|---|---|
| Empresa | `71c6841a-968a-4c21-acb9-25114a507067` "Solvex", bodega, 1 propietario |
| Licencia actual | `local` · BASICO · activa · `full` · `period_end` vacío · 0 activaciones |
| Último token del Hub guardado | `iss=solvex-hub`, `alg=EdDSA`, `typ=slx-license+jwt`, `aud=ins_nztfsjj6y8cuns65e7a2`, `tenant` = la empresa, `product=FACTURAVOZ`, código terminado en **0001** (= código de la empresa), BASICO · prueba · venció 2026-11-11 05:00 UTC, `max_users=2` |
| Webhooks del Hub aceptados por producción (firma HMAC válida) | 11-11 05:00, 11-15 21:18, 11-16 14:51, 11-16 20:06 (UTC). Los tres últimos coinciden con la extensión de la prueba y se **descartaron** por ser local |
| Vercel producción | `main` `e184ba5`; `SOLVEX_HUB_URL`, `SOLVEX_INSTANCE_ID`, `SOLVEX_API_KEY`, `SOLVEX_WEBHOOK_SECRET`, `CRON_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` presentes (solo entorno Production); `SOLVEX_PUBLIC_KEYS` ausente (se descargan del Hub). `/api/health`: todos los servicios configurados |
| Respaldo | Supabase no ofrece copia descargable desde aquí; la migración guarda el estado previo en `private.license_v34_backups` y existe `standalone_license_backups` |

## Antes de autorizar: comprobar en el panel de Solvex Hub
1. Producto **FACTURAVOZ** → instancia **`ins_nztfsjj6y8cuns65e7a2`** (la misma que firmó el token anterior).
2. Cliente/licencia con **tenant_ref = `71c6841a-968a-4c21-acb9-25114a507067`**.
3. El **código de licencia termina en `0001`** (si es otro, la reconciliación automática no se hará; tendrás que escribir el código nuevo en la app, también sin corte).
4. Estado **prueba** o **activa**, modo **full**, **fin de período posterior a hoy** (y, como objetivo comercial, **≥ 7 días** de prueba).
5. Plan (**BASICO**) y funciones/límites esperados (`max_users`).
6. Registro de entregas del webhook: los envíos del 15 y 16 de nov a `https://factura-voz-two.vercel.app/api/solvex/webhook` respondieron **200** (fueron aceptados y descartados por ser local).

## Plan de ejecución (cada paso requiere tu GO)
| # | Paso | Verificación | Si falla |
|---|---|---|---|
| 0 | **Respaldo**: Supabase → Database → Backups (confirmar que existe uno de hoy) o `pg_dump` de `public` y `private` | Hora del respaldo anotada | No continuar |
| 1 | Aplicar `20261206`, `20261207`, `20261208` y **FASE A** `20261209_v34a` | `select source, mode, private.org_mode(org_id) from public.org_licenses;` → sigue `local`/`full`; la app sigue vendiendo | Ninguno de estos pasos cambia el acceso; el rollback no hace falta |
| 2 | Fusionar **PR #9** y luego **PR #10** → Vercel despliega `main` | `/api/health` 200; la app y la web siguen operando (aceptan local) | Rollback inmediato de Vercel al despliegue anterior |
| 3 | **Preflight (solo lectura)**: con sesión de propietario en la web, abrir `https://factura-voz-two.vercel.app/api/license/preflight?org=71c6841a-968a-4c21-acb9-25114a507067` | Debe decir `"verdict":"GO"`: firma, emisor, audiencia y tenant verificados, mismo código, token y período vigentes | **NO-GO**: se queda en fase A (sin corte) y se corrige en el Hub según `reasons` |
| 4 | **Reconciliar**: en la app, Mi plan → "Comprobar con Solvex Hub" (o ejecutar el cron con `CRON_SECRET`) | `source=hub`, `org_mode=full`, `license_reconcile_pending` vacía, activación con código ****0001, auditoría `license.v34_reconciled` | Si responde `pending_code_mismatch`: no cambió nada; activar el código nuevo en la app |
| 5 | **FASE B** `20261210_v34b` | Si quedara algo sin reconciliar, la migración se detiene sola y no cambia nada | — |
| 6 | Prueba real con el propietario: venta → comprobante → caja; Mi plan muestra plan y vencimiento del Hub | — | `rollback/20261209_v34_rollback.sql` (restaura la fila exacta y la lógica previa; probado) |

**No usar `supabase migration repair`**: las versiones registradas en producción no coinciden con los nombres de archivo.
Equivalencias: `20261108223032` = `20261201`, `20261108223858` = `20261202`, `20261108223029` = `20261203`,
`20261108224717` = `20261204`, `20261108224159` = `20261205` (ya aplicadas; no volver a correrlas).
