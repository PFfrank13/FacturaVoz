# Reconstrucción FacturaVoz: arquitectura de experiencia, roles, planes, Design System y Bodega Básico

**Borrador. No fusionar sin revisión.** Rama `feat/reconstruccion-ux-roles-20261116`, sobre el PR #9 (`3cdc46e`).

## Qué trae
- **Navegación canónica**: contrato por destino (`nav/navigation_contract.dart`), acción principal por rubro en Inicio, nombres únicos (prueba).
- **Permisos granulares** (`permissions.dart`) sobre `my_access().can`, denegar por defecto.
- **Motor rubro × plan × rol** (`nav/role_matrix.dart`): 38 roles de rubro + propietario, administrador y finanzas; matriz generada desde el código (`tool/gen_matriz.py`).
- **Design System** con la paleta del prompt y modo claro AA (`ui/theme.dart`, `ui/ds.dart`).
- **Bodega Básico**: Inicio por rol con datos reales y Caja con pasos, acción fija y arqueo ciego.
- **Planes**: Básico · Pro (RECOMENDADO) · Empresa con precios, límites y días de prueba reales (`docs/facturavoz-planes.json`); pago solo para el propietario.
- **Activación** con pasos visibles; **Equipo** con permisos efectivos al invitar/editar.
- **Base de datos** (probar en staging antes de producción):
  - `20261201`–`20261205`: renombre de cinco `20261108_*` que no aplicaban en una base nueva (si producción usa el CLI, `supabase migration repair`).
  - `20261206`: corrige `min(uuid)`: la emisión de líneas sin producto fallaba.
  - `20261207`: `pay_url` y `can.license` solo para el propietario.
  - `20261208`: RLS de funciones del plan sin evaluación por fila (medido: `day_summary` 450 ms → 7 ms).
- **Idempotencia** de cobros, abonos de fiado y movimientos de caja.

## Verificación
- PostgreSQL 16 local: 47 migraciones en orden + 13 pruebas SQL (`backend/supabase/tests/local/run_all.sh`), **13/13 pasan**.
- **No ejecutado** (sin SDK en el entorno): `flutter analyze`, `flutter test`, compilación Android, `npm test`. Este PR existe para que los corra el CI.

Detalle: `docs/reconstruccion/00`–`07`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01XeULdY7eMnQ6u3oA4uwL1z
