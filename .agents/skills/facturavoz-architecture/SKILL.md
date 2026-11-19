---
name: facturavoz-architecture
description: "Arquitectura y refactorización del monorepo FacturaVoz; usar al cambiar contratos entre Flutter, Next.js y persistencia."
---

# facturavoz-architecture

## Archivos de entrada
- [app/lib/services/repo.dart](../../../app/lib/services/repo.dart)
- [app/lib/services/v2_repo.dart](../../../app/lib/services/v2_repo.dart)
- [backend/src/lib/erp/context.ts](../../../backend/src/lib/erp/context.ts)
- [backend/src/lib/solvex.ts](../../../backend/src/lib/solvex.ts)
- [docs/FACTURAVOZ_RETORNO.md](../../../docs/FACTURAVOZ_RETORNO.md)

## Trabajo
Traza pantalla → servicio → RPC → tablas y lectores antes de mover código. Conserva contratos públicos, identificadores de organización y tenant_ref. Reutiliza el código de 704632d y las mejoras posteriores verificadas; no reinicies desde un scaffold. Los nombres internos retail son compatibilidad, no otra marca. Voz/OCR preparan borradores revisables; no elimines sus servicios por el cambio de dirección.

## Aceptación
Refactor sin alterar permisos, cálculos ni estados; lectores Flutter y web coherentes. Probar el contrato afectado, no todas las suites por rutina.
