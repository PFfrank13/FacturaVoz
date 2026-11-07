# Reutilización compatible de infraestructura — 7 noviembre 2026

## Decisión vigente

Reutilizar FacturaVoz como base de Solvex Retail mediante cambios aditivos y
compatibles. No crear un tercer Supabase, no pagar ampliaciones, no eliminar ni
pausar proyectos. No se ha aplicado aún ninguna migración nueva remota.

| Recurso observado | Identidad | Tratamiento |
|---|---|---|
| Supabase `qzcpeipjlskyazrrelqu` | FacturaVoz, us-west-2, PostgreSQL 17 | Candidato a reutilización; conservar identidad y contratos |
| Supabase `gpgaoxmcompncvwurclq` | PFfrank13's Project, us-east-1 | Conservar; tablas de portafolio, atribución de integraciones aún incompleta |
| Vercel `prj_aRyyOsMROWr66PtCWLjZe5Y9WrzR` | factura-voz, backend, Node 24 | Mantener producción y webhook actuales |
| Vercel `prj_NTxDixu3HDHsy5ofUFs7GhH0qtWw` | solvex-retail-control | Creado, Next.js/backend/Node 24/npm ci; pendiente Preview funcional |

El segundo Supabase contiene certificates, comments, messages, projects, settings
y tools. Esto indica un portafolio, pero no prueba ausencia de dependencias
indirectas. El código local del Hub (repositorio y copia Solvex-Hub-Deploy) no
contiene referencias a Supabase. Eso tampoco certifica por sí solo el estado AWS.

## Contratos que no deben romperse

- Mantener `organizations.id` como `tenant_ref`, usuarios Auth y membresías.
- Preservar `org_licenses`, `solvex_events`, `private.app_config`,
  `private.license_activation_attempts`, `private.org_license_activations`.
- Preservar RPC `license_apply`, `license_mark`, `license_set_enforced`,
  `my_license`, `license_activation_attempt`, `license_activate_authorized`,
  las funciones `license_read_ok`/`license_write_ok`, guardas y políticas RLS.
- Mantener `/api/solvex/webhook`, `/api/cron/solvex-sync`,
  `/api/license/activate`. HMAC, Ed25519, audiencia, tenant y antirrepetición
  siguen siendo obligatorios. No activar licencias reales en pruebas.
- Credenciales por nombre: `SOLVEX_HUB_URL`, `SOLVEX_INSTANCE_ID`,
  `SOLVEX_API_KEY`, `SOLVEX_WEBHOOK_SECRET`, `SOLVEX_PUBLIC_KEYS` opcional,
  `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `SECRETS_KEY`.
- Conservar claves/API/UUID/producto técnico FACTURAVOZ mientras exista el
  contrato. Cambiar marca visible no implica rotación técnica.
- Hub usa su propia persistencia SQLite: no migrarla ni modificar AWS, Caddy,
  panel, licencias, web corporativa o base del Hub.

## Evidencia de respaldo

Directorio privado, fuera de Git:
`C:\Users\pined\Documents\Solvex-Retail-Backups\20261107-publicacion`.

- Bundle Git verificado; schema.sql, data.sql, roles.sql,
  managed-schema.sql y auth-storage-migrations.sql exportados.
- data.sql del CLI actual ya incluye Auth y Storage. No restaurar esos datos
  dos veces; el export complementario aporta el historial de migraciones.
- Config remota API/Auth/database/pooler/realtime/storage exportada mediante
  `config pull` a la carpeta privada, sin cambiar configuración remota.
- Cero Edge Functions desplegadas según API; no hay código remoto que descargar.
- Storage: org-media y tts-cache; un objeto de cero bytes descargado por API.
- Restauración SQL en `restore_20261107121401629485`, contenedor
  `solvex-cloud-lab-20261107`, sin red ni volúmenes del host. Salida 0.
  Se restauran datos con triggers deshabilitados SOLO en el laboratorio y luego
  se recrean/validan todas las claves foráneas de public/auth/storage.
- Conteos iguales remoto/restauración: 1 usuario, 1 organización, 1 licencia,
  6 eventos Solvex, 1 objeto Storage y 4 migraciones registradas.

**Límites:** no equivale a restaurar los servicios alojados Auth/Storage ni a
probar credenciales externas. Vercel exportó 20 secretos como `[SENSITIVE]`,
no como valores recuperables. Por tanto el respaldo integral todavía no está
certificado para eliminar el proyecto. No se elimina nada. Las credenciales
existentes permanecen configuradas en producción.

## Siguientes puertas verificables

1. Comparar migraciones locales con esquema realmente restaurado. No aplicar
   toda la carpeta histórica a ciegas: producción registra solo cuatro versiones.
2. Ensayar ampliación retail sobre la restauración y comprobar que contratos,
   licencias y datos anteriores permanecen idénticos.
3. Verificar integraciones desplegadas sin activar, cobrar ni sincronizar
   licencias reales. El intento de comprobación API Hub se detuvo al detectar
   secretos ocultos por Vercel; no se enviaron credenciales placeholder.
4. Preparar Preview sin secretos operativos del Hub; aislar cualquier prueba
   comercial de usuarios reales. No publicar una demo desconectada como ERP listo.
5. Aplicar únicamente cambios compatibles y verificados. La retirada de recursos
   requiere inventario de consumidores; ninguna eliminación está propuesta ahora.

GitHub sigue privado. Rama de trabajo `codex/solvex-retail-preview`; main y el
archivo local `archive/facturavoz-before-solvex-20261107` preservan el punto previo.
