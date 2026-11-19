---
name: facturavoz-database
description: "Diseñar y probar cambios Supabase/PostgreSQL de FacturaVoz: RLS, RPC, migraciones, concurrencia y reconciliación."
---

# facturavoz-database

## Archivos de entrada
- [backend/supabase/schema.sql](../../../backend/supabase/schema.sql)
- [backend/supabase/migrations](../../../backend/supabase/migrations)
- [backend/supabase/local/retail_checkout.sql](../../../backend/supabase/local/retail_checkout.sql)
- [backend/scripts/test-restored-pos.mjs](../../../backend/scripts/test-restored-pos.mjs)
- [tools/verify_private_backup.py](../../../tools/verify_private_backup.py)

## Trabajo
Proyecto existente qzcpeipjlskyazrrelqu. Primero inspecciona esquema real y dependencias; los archivos históricos no prueban migraciones aplicadas. Usa copia restaurada sin red para pruebas de escritura; nunca producción como laboratorio. Mantén organizaciones, Auth, org_licenses, solvex_events, guards y funciones license_*. Aditivo preferente; cambios irreversibles requieren revisión específica. RLS y grants separados; SECURITY DEFINER solo con controles explícitos y search_path seguro. Orden estable de bloqueos y validación de precio dentro de transacción. Consulta skill Supabase y docs actuales al implementar.

## Aceptación
Ensaya migración y contratos sobre restauración; commit real leído por otra conexión; doble solicitud, concurrencia, empresa ajena y rollback. No declares restauración integral basándote solo en SQL: Auth/Storage/config/secretos requieren evidencia separada.
