# Pruebas SQL de la v2.0 (base de datos local, NUNCA en producción)

Son guiones de escenario que se corrieron contra PostgreSQL 16 con un "shim" mínimo de Supabase
(roles `anon`/`authenticated`/`service_role`, `auth.uid()`, esquema `storage`) y **sin privilegios por defecto**
(como los proyectos nuevos de Supabase, que es donde apareció el error 42501).

Cómo correrlos (en una base de datos de prueba vacía):

1. `schema.sql` y luego todas las migraciones en orden (`migrations/*.sql`).
2. Cada guion por separado en una base recién creada:
   `psql -v ON_ERROR_STOP=1 -f tests/test_fase0.sql` (y así con los demás).

| Guion | Qué prueba |
|---|---|
| test_fase0.sql | Permisos de la app (importación sin 42501) y `sales_summary` (misma cifra en Inicio y Mi negocio) |
| test_sunat.sql | Reserva de serie-correlativo SUNAT; un número rechazado se archiva y se usa uno nuevo; Storage del logo |
| test_crm.sql | Ficha 360, trabajos y estados, eventos, materiales que descuentan stock, aislamiento entre empresas |
| test_roles.sql | Roles (cajero, técnico, finanzas, vendedor), invitaciones, técnico solo ve sus trabajos |
| test_mod1.sql | Fiados, caja y cierre, bitácora encadenada, PIN del dueño, papelera y restaurar, cupones, puntos |
| test_mod2.sql | Portal del cliente, reservas, API con claves, webhooks, encuestas |
| test_lic.sql | Licencias de Solvex Hub: modo desarrollo, plan BASICO, funciones apagadas, límite de usuarios, corte y bloqueo |

Los bloques entre `\set ON_ERROR_STOP 0` y `\set ON_ERROR_STOP 1` son operaciones que **deben fallar**
(un cajero viendo gastos, una cotización sin plan, etc.). Si el guion termina con código 0, pasó.

## v3
| Archivo | Qué prueba |
|---|---|
| `test_v3_import.sql` | Importa el libro sintético de 1 500 comprobantes por bloques (necesita `/tmp/pg/wb_payload.json` generado con el analizador), compara conteos y neto, misma cifra en Inicio/series/Copiloto, idempotencia, protección de campos del servidor, otra empresa bloqueada, deshacer. |
| `test_v3_rubros.sql` | Historial privado por rol, paquetes (no se "devuelven" sesiones), recordatorios, aislamiento entre empresas. |
| `test_v3_voz.sql` | Cuotas de voz premium (empresa y global) y de DNI/RUC (persona y empresa). |
| `test_v3_rls_audit.sql` | Auditoría: un usuario de otra empresa no ve NINGUNA fila de las 50 tablas con `org_id`. |
| `bench_v3.sql` | 10 000 comprobantes: tiempos antes/después (ver `docs/RENDIMIENTO.md`). |
| `test_v31_planes.sql` | v3.1: plan × rubro (Básico/Pro/Empresa, complementos del Hub), `my_license` ya resuelto por rubro, tareas del Copiloto agente (estados, aprobación, aislamiento). |
