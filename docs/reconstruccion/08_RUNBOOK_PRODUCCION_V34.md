# Runbook de producción v3.4 — licencias solo Solvex Hub

**No ejecutar sin autorización explícita del propietario.** Todo lo de abajo está probado en PostgreSQL 17 sobre una
réplica sintética del estado real de producción (`backend/supabase/tests/upgrade/run_upgrade.sh`, también en CI).

## Estado real verificado (2026-11-17, solo lectura)
| Elemento | Producción |
|---|---|
| Supabase | `qzcpeipjlskyazrrelqu`, PostgreSQL 17.11 |
| Empresas | 1 (`Solvex`, rubro bodega), 1 usuario propietario, 1 comprobante |
| Licencia | `source=local`, `BASICO`, `activa`, `mode=full`, `period_end=null`, token del Hub vencido (11-nov), sin fila en `org_license_activations` |
| Respaldo previo | `private.standalone_license_backups`: la prueba del Hub (`source=hub`, `prueba`, código presente, vencía 11-nov) |
| `org_mode()` | **Distinta del repositorio**: acepta `local`/`dev` como `full` sin token (deriva no versionada) |
| `feature_for()` | Sin `invoices`/`clients`/`payments` (deriva) |
| `apply_stock_on_issue()` | Contiene `min(p.id)` → falla en PG17 con líneas sin producto |
| Webhook y cron del Hub | Saltan tenants `local` → **la extensión de prueba hecha en el Hub nunca llegó** |
| Migraciones registradas | 16 (aplicadas por MCP); las anteriores, por el editor SQL. Equivalencias: `20261108223032 isolated_bodega_local_plan` = `20261201`, `20261108223858 …remove_stale_hub_trial_banner` = `20261202`, `20261108223029 pos_merchant_qr_fields` = `20261203`, `20261108224717 …qr_owner_column_grants` = `20261204`, `20261108224159 …feature_read_policies_fix` = `20261205` |
| Vercel | Producción = `main` `e184ba5`; dominio `factura-voz-two.vercel.app`; variables `SOLVEX_*` presentes (valores no leídos) |

**No usar `supabase migration repair`**: las versiones de producción no coinciden con los nombres de archivo; 20261201–20261205 ya
están aplicadas con otras versiones y no deben volver a correrse.

## Requisito comercial previo (fuera del código)
En Solvex Hub, la instancia de FacturaVoz debe tener una licencia **asignada a `tenant_ref = 71c6841a-968a-4c21-acb9-25114a507067`**,
con la prueba extendida y `trial_days ≥ 7` configurado en los planes. Si el código (`lic`) es el mismo que tenía la prueba original,
la empresa se reconcilia sola; si el Hub emitió otro código, el propietario lo introduce en la app ("Activar mi licencia").

## Orden de despliegue (ventana corta, ~10 min)
1. **Respaldo**: Supabase → Database → Backups (o `pg_dump` del esquema `public` y `private`). Anotar la hora.
2. **Migraciones** (en este orden, cada una en su transacción): `20261206_v33_fix_stock_min_uuid`, `20261207_v33_suscripcion_solo_propietario`,
   `20261208_v33_rls_funciones_rendimiento`, `20261209_v34_licencias_solo_hub`.
   Desde aquí la empresa queda **bloqueada** (sin acceso comercial) hasta que el Hub confirme: es lo correcto.
3. **Backend**: fusionar el PR (después del #9) → Vercel despliega `main`. El webhook y el cron empiezan a usar `license_sync_apply`.
4. **Sincronizar**: el propietario toca **"Comprobar con Solvex Hub"** en la app, o ejecutar `GET /api/cron/solvex-sync` con `CRON_SECRET`.
5. **Verificar** (SQL de solo lectura):
   ```sql
   select source, plan, status, mode, period_end, token_exp, private.org_mode(org_id) from public.org_licenses;
   select * from private.license_reconcile_pending;   -- debe quedar vacía
   select action, created_at from public.audit_log where action like 'license.%' order by created_at desc limit 5;
   ```
   Y en la app del propietario: entra, ve su plan y vencimiento del Hub.
6. **Probar** venta → comprobante → caja con el propietario; luego invitar un cajero y comprobar que no ve "Pagar plan".

## Rollback (probado)
`backend/supabase/rollback/20261209_v34_rollback.sql` restaura la fila de licencia exacta desde `private.license_v34_backups`
y la lógica previa de `org_mode`. Verificado: el hash de la fila y el modo coinciden con el estado anterior. La corrección de
stock y la RPC del backend se mantienen (no dan acceso). Para el backend: "Instant Rollback" en Vercel al despliegue anterior.

## Qué NO hace esta migración
No crea licencias, no extiende pruebas, no pone `full` a nadie, no borra datos. Si el Hub no tiene licencia para el tenant,
la app lo dice con el motivo exacto y la empresa espera la asignación comercial.
