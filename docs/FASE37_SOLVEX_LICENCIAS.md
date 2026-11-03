# FacturaVoz — Fase 37: activación obligatoria desde Solvex Hub

## Qué se encontró en el ZIP original

- Flutter tiene **nueve fotografías WebP** por rubro, `mini_market.webp` y `welcome_scene.webp` en `app/assets/photos/`. Se distribuyen **dentro de la aplicación**, no en Docker ni en Vercel.
- `infra/lycet/docker-compose.yml` ejecuta **Lycet** (compilado desde un commit específico de Git) y **Caddy** (`caddy:2`, etiqueta flotante); no es un despliegue de Flutter.
- La migración `20261111_licencias.sql` creaba pruebas **locales** con plan `EMPRESA` y todas las funciones. El cron podía desactivar el control de licencias si faltaba la configuración del Hub. Era incompatible con la activación obligatoria.
- La matriz local de planes podía dar funciones aunque el Hub las tuviera apagadas. En Fase 37 la API `my_license` sólo devuelve los flags que estén habilitados por la licencia firmada y activada.
- No se inspeccionó ningún contenedor Docker **en ejecución** ni un despliegue real; no se puede asegurar que tu servidor ya utilice la imagen o configuración del ZIP.

## Nuevo flujo

1. El cliente registra correo y contraseña / OTP en Supabase Auth.
2. La migración multiempresa crea automáticamente su organización (`organizations.id`). La licencia de esa empresa comienza como `pendiente`, `blocked`, sin prueba automática.
3. Al iniciar sesión aparece **Activa tu FacturaVoz**, con el identificador de empresa y un campo de código.
4. El vendedor asigna en **Solvex Hub** un plan de `FACTURAVOZ` **al tenant_ref igual a ese UUID**. Debe entregar el **código `lic`** que figura en el token firmado de esa licencia (NO la API key `slxk_…`, ni el secreto del webhook, ni el token de Supabase).
5. El cliente introduce el código. El backend consulta el endpoint *ya existente* `GET /v1/instance/licenses`, verifica firma Ed25519, audiencia de instancia, expiración y que `tenant_ref` coincide con `organizations.id`. También comprueba que el código coincide y que el estado es `full` o `warning`.
6. La operación privilegiada `license_activate_authorized` guarda estado + confirmación de activación en una transacción. **Los webhooks y el cron por sí solos NO pueden desbloquear** empresas no activadas por el cliente.
7. Flutter refresca `my_license`; los botones y módulos siguen el rubro seleccionado y los derechos verificados del Hub. Las restricciones efectivas se aplican en PostgreSQL mediante RLS y triggers existentes. Las API externas requieren revisión independiente por endpoint.
8. Un empleado de una empresa activada entra con sus propias credenciales sin introducir otro código. Para una empresa distinta hace falta otra licencia asignada a su ID.

### Limitación de compatibilidad con Solvex Hub

Esta integración **no inventa** un endpoint para generar/canjear códigos nuevos dentro del Hub. Utiliza el endpoint de consulta de licencias que ya figura en el proyecto. La clave aceptada es el valor firmado `lic` **de una licencia previamente asignada al tenant**. Si tu Hub sólo genera claves sin tenant o no expone el identificador `lic`, tendrás que añadir una API de canje oficial al Hub antes de usar códigos comerciales distintos.

## SQL requerido (peligroso en producción sin plan de migración)

Ejecutar **después de todas las migraciones hasta `20261123`**:

`backend/supabase/migrations/20261124_v31_solvex_activation_required.sql`

⚠️ **Este archivo BLOQUEA a todas las empresas con licencia `local`/`dev`**, incluidas aquellas que estuvieran en prueba o usando la app sin Hub. Conserva sus registros pero no permite operar hasta asignar y activar una licencia de Hub. También bloquea a empresas que tenían un token Hub pero nunca introdujeron código. Ejecuta primero en STAGING, realiza respaldo, entrega claves a los clientes y planifica una ventana de activación. No lo ejecutes aún en tu base principal si no has preparado las licencias.

## Variables necesarias en backend Vercel/AWS

`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SOLVEX_HUB_URL`, `SOLVEX_INSTANCE_ID`, `SOLVEX_API_KEY`, `SOLVEX_WEBHOOK_SECRET`, `CRON_SECRET`.

`SOLVEX_PUBLIC_KEYS` es recomendable si no quieres que la instancia dependa de descargar las llaves de verificación al primer inicio. La `service_role` y las claves privadas **nunca** van en Flutter.

La API **nueva** debe estar desplegada: `POST /api/license/activate`. La ruta `/api/license/trial` ahora responde prohibición y el cron nunca vuelve a desactivar las licencias por falta de variables.

## Verificar Docker/Lycet en tu AWS (sin afectar a Flutter)

En el servidor, desde el directorio `infra/lycet` que tengas desplegado:

```bash
docker compose config
docker compose ps
docker compose images
docker image ls
git rev-parse HEAD
```

Verifica digest o ID de la imagen **en ejecución**, versión de Caddy, salud de Lycet y hash del commit usado para construir; no asumas que coinciden con el ZIP. Haz copia de los volúmenes de Lycet antes de reconstruir. **No ejecutes** `docker compose down -v`: borraría los datos persistentes.

## Pruebas obligatorias antes de producción

- Alta de propietario nuevo: entra en la pantalla de licencia, no puede crear ventas sin activarla.
- Intentar código inexistente o de otra empresa: `403`; tras 8 intentos por hora: `429`.
- Licencia de Hub previamente asignada al mismo `tenant_ref`: se activa exactamente una vez; tras reiniciar, no solicita nueva clave.
- Un webhook recibido *antes* de introducir código: la empresa permanece bloqueada.
- Renovación, cambio de plan o suspensión desde Hub: la app refleja los derechos del nuevo token y la base impide lo prohibido.
- Un empleado en negocio activado no necesita segunda licencia; no puede activar empresas ajenas.
- Sin internet / RPC `my_license` con error: **no desbloquea usando el caché**.
- Matriz de pruebas para los nueve rubros: Inicio, menú, ventas, clientes, stock, caja, citas, órdenes, comandas, impresoras y reportes.
- Pruebas reales de `flutter analyze`, `flutter test`, build release y endpoints del backend. La capacidad para 200 empresas **NO** está demostrada por esta fase.

## Inconsistencias todavía por auditar

- Cada endpoint del backend con costes externos (voz/IA, consultas de DNI/RUC, etc.) debe verificar la licencia y el límite contractual; la UI no sustituye esta validación.
- La matriz histórica `planMatrix` sigue presente como catálogo comercial; los planes y precios mostrados en la app pueden quedar desactualizados si se cambian en Hub. Usar el panel Hub como fuente final de precios.
- Lycet/SUNAT Beta, certificados, comprobantes reales y prueba física de impresoras siguen pendientes de validación en infraestructura.
- No se ha probado con usuarios reales si los flujos de cada rubro son comprensibles ni se ha ejecutado el plan de carga.

### Endpoints reforzados en Fase 37

- `/api/license/activate`: código + JWT firmado del Hub + tenant + cuota.
- `/api/assistant`, `/api/agent`: deniegan licencias ausentes, bloqueadas y módulos IA no incluidos.
- `/api/transcribe`, `/api/notebook`: requieren `org_id` autenticado y `voz`/`cuaderno_ia` activos.
- `/api/lookup`, `/api/fx`: exigen la empresa activa y los permisos de facturación/multimoneda.

Estos cambios son defensivos, pero no implican una auditoría exhaustiva del backend ni validación de las API en AWS/Vercel.
