# Importación masiva de facturas históricas

## Por qué NO hacemos scraping del portal de SUNAT
- Exige la **clave SOL** del cliente: guardarla (aunque sea temporal) en nuestros servidores es un riesgo legal y de seguridad enorme.
- El portal cambia sin aviso, usa captcha/validaciones y los términos de uso de SUNAT no permiten automatizarlo con un navegador.
- Un navegador automatizado no corre en Vercel (límite de 10–60 s) y un servidor propio es costo y mantenimiento.

**Alternativa implementada (sin credenciales):** el cliente descarga su *Registro de Ventas* (CSV/TXT) desde SOL o su sistema anterior y lo sube a la app. Lee Cliente, Servicio e Importe (+ fecha, RUC/DNI, número, moneda) y detecta las columnas solas.
**Fase 2 recomendada (oficial):** la API **SIRE** de SUNAT (OAuth con client_id/secret que el cliente genera en SOL) para traer el registro sin archivo. No está implementada porque no pude verificar sus endpoints; se enchufaría en `import_jobs.source = 'sire'` reutilizando las mismas tablas y el mismo worker.

## Cómo evita timeouts
1. La app lee el archivo **en el teléfono** y sube bloques de 500 filas (`import_add_rows`): peticiones cortas, con reintentos.
2. La base de datos convierte las filas en clientes + facturas **por lotes** (`import_run_batch`, 500–1000 filas, ~1 s). Nada pasa por una petición web larga.
3. Un **worker pg_cron** (cada minuto) sigue procesando aunque la app esté cerrada. La app abierta solo acelera (`import_step`).
4. La barra de progreso viene de **Realtime** sobre `import_jobs` (con consulta de respaldo cada 4 s).
5. Al terminar se borran las filas de paso (no consumen tu cuota de 500 MB).

## Seguridad
- RLS: cada usuario solo ve/usa trabajos de su empresa; `import_rows` no es accesible directamente; las funciones comprueban dueño y pertenencia.
- Validación en la base: importe 0–100 M, moneda, longitudes, 200 000 filas máx. por importación.
- Las facturas importadas quedan como **pagadas** (históricas), sin afectar "Por cobrar", y con número repetido se omiten (no se duplican).
- Los importes del archivo se toman como **total con IGV 18 %** (opción desactivable); puede haber diferencia de 1 céntimo por redondeo.

## Pasos para activarlo
1. Supabase → SQL Editor: ejecutar `backend/supabase/migrations/20261031_imports.sql`.
2. Supabase → Integrations → **Cron**: activar `pg_cron` y volver a ejecutar el mismo archivo (programa el worker). Sin pg_cron igual funciona mientras la app esté abierta.
3. Correo al terminar:
   - Vercel → Environment Variables: `CRON_SECRET` (cadena larga al azar). Redeploy.
   - Inmediato: Supabase → Database → **Webhooks** → tabla `import_jobs`, evento *Update*, método POST a `https://TU-APP.vercel.app/api/import/notify`, header `Authorization: Bearer <CRON_SECRET>`.
   - Sin webhook, el cron diario de Vercel (`vercel.json`) envía los avisos pendientes una vez al día.
   - Mientras Resend no tenga dominio verificado, el correo solo llega al dueño de la cuenta de Resend.
