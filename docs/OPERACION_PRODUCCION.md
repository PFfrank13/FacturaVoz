# Operación en producción (G)

## 1. Seguridad: lo que ya está
- **RLS en todas las tablas** con `org_id` + permisos por rol en la base. Prueba automática
  `backend/supabase/tests/test_v3_rls_audit.sql`: siembra datos en la empresa A y verifica que un usuario de la
  empresa B no ve **ninguna** fila en **ninguna** de las 50 tablas (resultado: 0 fugas).
- Políticas optimizadas (v3, `20261114`): mismas reglas, se calculan una vez por consulta.
- Campos que solo escribe el servidor (totales, anulado, importación) protegidos por disparador: el cliente no
  puede falsearlos (probado).
- **Ninguna clave en la app Flutter**: GROQ, ELEVENLABS, DOC_API, RESEND, SUNAT y Solvex viven solo en Vercel.
  `doclookup.ts` enmascara el token en cualquier registro; la clave de ElevenLabs va en cabecera, nunca en URL.
- Límites de uso: Copiloto 8/min y 150/día por usuario; lectura de Excel 5/min y 60/día; DNI/RUC por persona,
  empresa y hora; voz por empresa y global; tienda pública con límite por teléfono (`store_place_order2`).
- Validación de entradas en el servidor (tamaños, formatos, UUID, montos) y en la base (CHECK).

## 2. Rotación de claves (hacer cada 6 meses o ante sospecha)
| Clave | Dónde se genera | Pasos |
|---|---|---|
| `GROQ_API_KEY` | console.groq.com → API Keys | Crear nueva → pegar en Vercel (Production y Preview) → Redeploy → borrar la vieja. |
| `ELEVENLABS_API_KEY` | elevenlabs.io → Profile → API Keys | Igual. |
| `DOC_API_TOKEN` | panel de apisperu.com | Igual. |
| `RESEND_API_KEY` | resend.com → API Keys | Igual. |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase → Settings → API (rotar JWT secret) | ⚠️ Rotar el JWT secret cierra todas las sesiones. Hacerlo de noche. |
| `CRON_SECRET` | `openssl rand -hex 32` | Cambiar en Vercel y en `private.app_config` si usas pg_cron. **Recomendado ahora:** se compartió en un chat anterior. |
| `SOLVEX_API_KEY` / `SOLVEX_WEBHOOK_SECRET` | Panel del Hub | Crear nueva clave de instancia → Vercel → Redeploy → revocar la vieja. |
| Certificado SUNAT | Ajustes → SUNAT en la app | Subir el nuevo `.pfx` antes de que venza. |

## 3. Respaldos y recuperación
- **Supabase Free no tiene respaldos automáticos descargables.** Al pasar a producción: **Supabase Pro** (respaldo
  diario, 7 días). Opcional: PITR (pago).
- Respaldo propio semanal gratis: `pg_dump` con la cadena de conexión (Settings → Database) a un disco tuyo:
  `pg_dump "$DB_URL" -Fc -f facturavoz_$(date +%F).dump`.
- Recuperación de un error humano: **Papelera** (30 días) en la app; importaciones: **Deshacer**.
- Probar una restauración cada 3 meses en un proyecto Supabase de prueba (`pg_restore`).

## 4. Registro de errores (gratis)
- Servidor: Vercel → Logs (Hobby 1 h, Pro 1 día). Los mensajes nunca incluyen claves ni datos de clientes.
- Recomendado: **Sentry** plan Developer gratuito (5 000 errores/mes) para Next.js y Flutter. No se instaló para no
  añadir dependencias sin tu cuenta: crea el proyecto y se agrega con `npx @sentry/wizard -i nextjs` y
  `sentry_flutter`. Alternativa sin código: Firebase Crashlytics (gratis) en la app.

## 5. Página de estado
- Nuevo `GET /api/health`: dice si la base responde y qué servicios están configurados (sin valores de claves).
- Monitor gratuito: UptimeRobot o Better Stack (gratis) apuntando a `https://<tu-dominio>/api/health` cada 5 min,
  con página de estado pública.

## 6. Actualizaciones de la app
1. Sube `version:` en `app/pubspec.yaml` (ahora `3.1.0+6`) y compila con `--dart-define=APP_VERSION=3.1.0`.
2. Primero **migraciones SQL** (en orden), luego **backend** (git push → Vercel), luego **app** (tiendas).
3. La app soporta un servidor más nuevo (y al revés, un servidor viejo: el Copiloto vuelve al modo sin tiempo real).
4. Pruebas internas en Play Console (pista interna) antes de producción.

## 7. SUNAT: pasar de beta a producción (checklist)
- [ ] Certificado digital vigente (`.pfx`) del RUC del negocio, cargado en Ajustes → SUNAT.
- [ ] Usuario secundario SOL con perfil de emisión electrónica.
- [ ] Emitir en **beta**: 1 factura, 1 boleta, 1 nota de crédito; revisar CDR "aceptado".
- [ ] Revisar series (F001/B001) y que no choquen con otro sistema que el negocio use.
- [ ] Cambiar el ambiente a **producción** en Ajustes → SUNAT (por empresa).
- [ ] Emitir el primer comprobante real con monto pequeño y verificarlo en "Consulta de validez del CPE" de SUNAT.
- [ ] Boletas: hoy se envían una por una; para volumen alto implementar Resumen Diario (Hoja de ruta).
- [ ] Comprobantes **importados** de otro sistema: la app NO los reenvía a SUNAT (bloqueado en el servidor).

## 8. Cambiar el rubro de un cliente (solo la plataforma)
Desde v3.1 el cliente elige su rubro una sola vez y queda fijo (la app y la base de datos lo impiden).
Para cambiarlo sin perder ningún dato (clientes, ventas, productos, trabajos), en Supabase → SQL Editor:

```sql
select private.admin_set_rubro('<id de la empresa>', 'restaurante');
```
Rubros: bodega, restaurante, servicios_tecnicos, salon, consultorio, taller, mayorista, educacion, construccion.
Limpia solo las personalizaciones de pantalla del rubro anterior (módulos, pasos de trabajo, campos extra); para
conservarlas, usa un tercer parámetro `false`. Queda registrado en la bitácora (`rubro.cambiado_plataforma`).
Migración: `20261117_v31_rubro_bloqueado.sql`.
