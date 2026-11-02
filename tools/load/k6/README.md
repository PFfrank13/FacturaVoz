# FacturaVoz: pruebas de carga en STAGING

**No correr contra producción, SUNAT real, SMTP real ni proveedores de pago.** El ensayo requiere ejecutar previamente la migración `20261123_v31_fast_checkout_atomic.sql`, configurar 200 empresas ficticias, productos con stock adecuado y al menos 400 cuentas de prueba autenticadas con RLS. Copia `fixtures.staging.example.json` a `fixtures.staging.json` y completa referencias de staging (nunca subir JWT a Git).

```bash
cd tools/load/k6
FV_STAGING_ONLY=yes FV_EXPECTED_STAGING_REF=tu-ref-staging \
SUPABASE_URL=https://tu-ref-staging.supabase.co \
SUPABASE_ANON_KEY=tu-publicable PROFILE=reference \
k6 run fast_checkout.js
```

Repite con `PROFILE=nominal`, `PROFILE=peak` y después de pasar P0, `PROFILE=stress5x`, `PROFILE=stress10x`. Opcional `CHECK_RETRY=yes` reintenta un 5 % de las ventas con la misma clave para comprobar idempotencia. Revisa `dropped_iterations`, p95/p99, 5xx, bloqueo/CPU/IO PostgreSQL, costes y conciliación por empresa; **no** basta con que k6 termine correctamente. Los escenarios de lectura, fiados, QR, Realtime, facturación beta real limitada y recuperación deben ensayarse además por separado.

El script es una herramienta de prueba, no una certificación de capacidad. Actualiza sus tokens de corta duración antes de cada ejecución y descarta las cuentas de prueba después.
