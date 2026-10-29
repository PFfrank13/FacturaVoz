# Conectar FacturaVoz con Solvex Hub (licencias y cobros)

Guía corta. Mientras **no** pongas las variables de Solvex en Vercel, FacturaVoz funciona en **modo desarrollo**:
todo habilitado, sin cobros, y la app lo dice en "Mi plan". Nada se bloquea por error.

## 1. Producto (una vez)
Panel del Hub → **Productos** → Nuevo:
- Código: `FACTURAVOZ` · Nombre: `FacturaVoz` · Tipo: SaaS.

## 2. Planes (una vez)
Dentro del producto → **Planes** → crea los tres de `docs/facturavoz-planes.json` (BASICO, PRO, EMPRESA).
- Copia tal cual el bloque `features` de cada plan (son las claves que la app y la base de datos leen).
- `trial_days: 3` y `grace_days: 5`. Los precios del archivo son una **propuesta**: ajústalos.
- `max_users` limita las personas por empresa (lo aplica la base de datos al invitar).

## 3. Instancia (una por ambiente)
Panel → **Integraciones** → Nueva instancia:
- Producto: FacturaVoz · Nombre: `FacturaVoz producción` · Ambiente: producción.
- **URL de webhook**: `https://TU-DOMINIO-VERCEL/api/solvex/webhook` (ej. `https://factura-voz-two.vercel.app/api/solvex/webhook`).
- Al crearla el Hub muestra **una sola vez**: la **clave de API** (`slxk_…`) y el **secreto del webhook**. Cópialos.
- Anota el **id de la instancia** (`ins_…`).
- Llave pública: en `https://TU-HUB/.well-known/solvex-license-keys.json` copia el valor `raw_b64` (o déjalo vacío y
  el servidor la descarga solo y la guarda 1 hora).

## 4. Variables en Vercel (Settings → Environment Variables, marcar las secretas como *Sensitive*)
| Variable | Valor |
|---|---|
| `SOLVEX_HUB_URL` | `https://TU-HUB` (solo https) |
| `SOLVEX_INSTANCE_ID` | `ins_…` |
| `SOLVEX_API_KEY` | `slxk_…` (Sensitive) |
| `SOLVEX_WEBHOOK_SECRET` | secreto del webhook (Sensitive) |
| `SOLVEX_PUBLIC_KEYS` | `raw_b64` de la llave pública (opcional; separa con coma si hay rotación) |
| `SOLVEX_PLANS_URL` | página donde el cliente elige plan (ej. tu web de precios) |

Luego **Redeploy**. El cron `/api/cron/solvex-sync` (una vez al día) sincroniza todas las licencias, pide las
pruebas pendientes y manda el "latido" de la instancia. Los cambios urgentes (pago, corte) llegan al instante por el
webhook firmado.

## 5. Probar
1. Crea una empresa nueva en la app con un RUC válido → Ajustes → Mi plan → "Activar mi prueba de 3 días".
2. En el Hub debe aparecer el cliente con su licencia de prueba (`EMPRESA`).
3. Repite con el mismo RUC en otra cuenta → "Este RUC ya usó su prueba".
4. Cambia la licencia a "suspendida" en el Hub → la app muestra "Modo solo lectura" o la pantalla de pago (según el modo).

Prueba de punta a punta sin teléfono: `node backend/scripts/e2e-solvex-hub.cjs` (instrucciones dentro del archivo).

## Qué hace cada modo en FacturaVoz
| Modo | En la app | En la base de datos |
|---|---|---|
| `full` | Todo lo del plan | Todo lo del plan |
| `warning` | Aviso amarillo "pago pendiente" + botón Pagar | Igual que full |
| `restricted` | Dueño/admin: aviso rojo "solo lectura" (puede pagar y exportar). Personal: pantalla de pago | Sin cambios (ni ventas ni cobros); solo el dueño/admin puede leer |
| `blocked` | Pantalla "Tu plan está pausado" con botón de pago | Lectura bloqueada; los datos NO se borran |
