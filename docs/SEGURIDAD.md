# Seguridad: parches aplicados y pendientes

## Parcheado en este código
| # | Riesgo | Sev. | Solución |
|---|--------|------|----------|
| 1 | Dependencia `postcss` vulnerable (XSS/lectura de archivos) | Alta | `overrides` → 8.5.31; `npm audit` = 0 |
| 2 | La app móvil no tiene cookies: middleware la redirigía; no había auth móvil | Crítica (funcional) | `/api/parse` acepta `Bearer` (validado contra Supabase Auth) y excluye la ruta del middleware |
| 3 | Cuota por usuario con condición de carrera (varias peticiones paralelas la saltaban) | Alta | RPC `consume_api_quota` atómica con bloqueo por usuario |
| 4 | Tipo de audio confiado al cliente | Media | Verificación por firma binaria; nombre/tipo generados por el servidor |
| 5 | Sin timeouts hacia Groq (cuelgues = coste/DoS) | Media | Timeout 20 s; 429 de Groq → 503 controlado |
| 6 | Prompt injection vía dictado | Media | Dictado delimitado como dato; salida validada (Zod) y redondeada; el usuario revisa antes de guardar |
| 7 | Numeración con carrera / fallo permanente tras borrar borradores; creación en 3 pasos no atómica | Alta | RPC `create_invoice` transaccional con bloqueo por usuario |
| 8 | Facturas emitidas editables | Media (fiscal) | Trigger `guard_invoice_update` + RLS: líneas solo editables en borrador |
| 9 | CORS abierto/ausente | Media | Lista blanca `ALLOWED_ORIGINS`; cookies solo mismo origen (Origin obligatorio) |
| 10 | Sin supresión de cuenta (exigida por Apple/Google/RGPD) | Alta (legal) | `delete_my_account()` (única función DEFINER pública; solo borra `auth.uid()`; `search_path` vacío) |
| 11 | Límites de longitud sin respaldo en BD | Baja | `CHECK` en perfiles, clientes y facturas |
| 12 | Secretos en la app | — | Ninguno: solo URL y clave `anon` (pública, protegida por RLS); Groq solo en servidor |
| 13 | Copias de seguridad Android y HTTP en claro | Media | `allowBackup=false`, `usesCleartextTraffic=false` (script `post_create`); la app exige HTTPS |

Probado: SQL en un Postgres real con dos usuarios (aislamiento, inmutabilidad, rollback, cuota, borrado);
la API con un Supabase simulado (401/403/400/429/CORS). El flujo de voz con Groq real NO se pudo probar aquí.

## Módulo fiscal (añadido)
| Riesgo | Solución |
|---|---|
| Un usuario falsifica «aceptado» o altera correlativos | `fiscal_*` solo lo escribe el servidor (RLS sin escritura; funciones solo `service_role`) |
| Emitir con el RUC de otro editando el perfil | El RUC sale de `fiscal_companies` (1 RUC = 1 cuenta; en producción el certificado debe contener el RUC) |
| Secretos SOL/certificado en la nube | Solo en tu VPS; nunca en Supabase ni en la app; `.pfx` convertido en memoria |
| Lycet expuesto / token en URL | Solo Caddy público: Basic Auth (bcrypt), rutas en lista blanca, token interno inyectado por Caddy |
| Duplicar números / saltarlos | Reserva atómica e idempotente con bloqueo por usuario; reintento = mismo número |
| `zod` vulnerable (memoria) | Actualizado a 4.x; `next-safe-action` 8 |
| Borrar cuenta con comprobantes de producción | Bloqueado (obligación de conservar), también si solo hay notas de crédito |
| SECURITY DEFINER expuesto | Ya no hay ninguna en `public`: `delete_my_account` es SECURITY INVOKER y delega en `private.delete_account_impl` (search_path vacío, solo borra `auth.uid()`) |
**Nota**: la regla «SECURITY DEFINER solo en `private`» se cumple desde `20261025`.
**Excepción documentada**: se usa `service_role` SOLO en `src/lib/supabase/admin.ts` (módulo fiscal). Rotarla si se filtra.
`node-forge` figura en `npm audit` (verificación de firmas RSA, que no usamos; sin parche): excepción justificada en `backend/scripts/audit-gate.mjs`.
**Riesgo residual**: la imagen oficial de Lycet usa PHP 8.1/Alpine 3.17 (sin soporte); mitigado por red cerrada, ver `infra/lycet/INSTALACION.md`.

## Lo que NO pude verificar (hazlo antes de vender)
- **La app Flutter no se compiló aquí** (el entorno no permite descargar el SDK). Está revisada y sin errores de
  sintaxis, pero puede haber errores de tipos/versión. El workflow `.github/workflows/ci.yml` ejecuta
  `flutter analyze`, `flutter test` y compila web+APK: corrígelo hasta que pase en verde. Prueba en un
  Android e iPhone reales (micrófono, permisos, compartir PDF).
- **El envío real a SUNAT** (no hay salida a SUNAT desde aquí): ver `docs/FISCAL.md`.
- Pentest externo y prueba de carga reales.

## Decisiones/riesgos de negocio que dependen de ti
- **Validez fiscal**: el PDF NO es comprobante electrónico válido. En Perú (SUNAT) hace falta emitir vía OSE/PSE o
  sistema autorizado; en otros países, su equivalente. Hasta integrarlo, véndelo como "borrador/comprobante interno" o
  intégralo con un proveedor autorizado. Consulta a un contador.
- **Escala**: este diseño (Supabase + Vercel + Groq) aguanta cientos/miles de usuarios, no 1 M RPS; el cuello de botella es la
  cuota de Groq (≈20 RPM en capa gratuita para TODOS los usuarios). Para vender, pasa Groq a plan de pago y confirma sus
  términos de uso comercial y retención de audio.
- **Planes gratuitos**: Vercel Hobby prohíbe uso comercial (necesitas Pro); Supabase Free se pausa por inactividad y no tiene
  backups (usa Pro antes de cobrar).
- **Privacidad (Ley 29733 en Perú / RGPD)**: política de privacidad, consentimiento del micrófono, contratos de encargado con
  Supabase/Vercel/Groq. Si no necesitas guardar la transcripción, elimina la columna `transcript`.
- **Limpieza**: `api_usage` crece; programa un borrado de filas > 7 días (pg_cron o manual).
- Pendiente recomendado: MFA opcional, registro de auditoría, límite global de Groq por cola, clientes y numeración por serie/año si tu normativa lo exige.
