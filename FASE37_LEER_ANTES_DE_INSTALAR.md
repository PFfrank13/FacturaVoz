# FacturaVoz v3.1 — Fase 37: licencias obligatorias de Solvex Hub

**ATENCIÓN: No apliques la migración en una base con clientes reales sin respaldar y preparar sus claves.**

## Archivos modificados

- `app/lib/access.dart`: bloquea acceso si no existe verificación online de una licencia Hub; no confía en modo desarrollo ni en licencias cacheadas.
- `app/lib/main.dart`: después de iniciar sesión aparece la pantalla de activación antes de continuar con la empresa; empleados de una empresa activada entran directamente.
- `app/lib/screens/license_gate.dart`: ingreso de código, copiar UUID de empresa, activar, renovar y reconsultar; "Mi plan" informa las funciones del Hub, no precios estimados.
- `app/lib/services/v2_api.dart`: `/api/license/activate` y org_id en rutas de proveedor.
- `backend/src/app/api/license/activate/route.ts`: valida código contra licencia firmada del Hub y ligada a esa empresa, limita intentos y activa desde servicio privilegiado.
- `backend/src/app/api/cron/solvex-sync/route.ts`: ya no desbloquea por ausencia de variables y no inicia pruebas locales.
- `backend/src/app/api/license/trial/route.ts`: prueba automática deshabilitada.
- `backend/src/lib/license-check.ts` y seis rutas de servicios: comprobación de plan activo antes de invocar proveedores externos.
- `backend/supabase/migrations/20261124_v31_solvex_activation_required.sql`: nueva migración para retirar prueba local, bloquear hasta ingresar clave, registrar activación efectiva, definir flags desde Hub y limitar intentos.
- `app/test/solvex_activation_gate_test.dart`: casos unitarios de concesión/bloqueo de funciones.

## Orden de despliegue

1. **Staging:** hacer copia; aplicar migraciones anteriores hasta `20261123`, luego `20261124`; verificar qué empresas quedarían bloqueadas.
2. **Hub:** configurar `FACTURAVOZ`, una instancia y los planes. Asignar una licencia firmada a cada `tenant_ref=organizations.id`. Obtener su `lic` de manera segura. **El Hub no expone un canje genérico en este ZIP:** este código requiere una licencia ya asignada.
3. **Backend:** desplegar `backend` en Vercel/AWS con todas las variables Solvex y Supabase; configurar webhook y cron.
4. **App:** compilar Flutter, entrar con correo y contraseña, copiar ID de empresa, activar licencia desde Solvex y verificar módulos por rubro/plan.
5. Ensayar suspensiones, cambio de plan, renovación, reinicios, errores de red, roles, 9 rubros y comprobantes antes de pasar a producción.

## Qué NO se ha validado

- La ejecución real de Flutter/Android, el SQL en Supabase y el backend desplegado.
- La existencia en tu panel Solvex de un código usable que coincida con `lic`; puede requerir adaptar el Hub.
- El estado real de tu servidor Docker o la capacidad para 200 empresas.
- Que todos los endpoints de pago o funciones secundarias estén completamente cubiertos: sigue siendo necesaria auditoría integral.

**Guía detallada:** `docs/FASE37_SOLVEX_LICENCIAS.md`.
