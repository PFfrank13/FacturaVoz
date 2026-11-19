---
name: facturavoz-web
description: "Desarrollar Next.js/React/TypeScript de FacturaVoz: formularios, POS, dashboard y navegación administrativa responsive."
---

# facturavoz-web

## Archivos de entrada
- [backend/src/app/erp/actions.ts](../../../backend/src/app/erp/actions.ts)
- [backend/src/app/erp/checkout.ts](../../../backend/src/app/erp/checkout.ts)
- [backend/src/components/erp/PointOfSale.tsx](../../../backend/src/components/erp/PointOfSale.tsx)
- [backend/src/lib/erp/access.ts](../../../backend/src/lib/erp/access.ts)
- [backend/src/lib/retail/ticket-store.ts](../../../backend/src/lib/retail/ticket-store.ts)

## Trabajo
Consulta workspaceContext y hasFeature/can en servidor; ocultar botones no autoriza operaciones. Mantén claves de servicio solo en servidor. Trabaja con etiquetas y datos comerciales compartidos, sin nueve experiencias obligatorias. Evita que un formulario limpie datos tras error incierto. No confíes en precios enviados por el cliente; el RPC debe validarlos bajo bloqueo. Para cambios React amplios consulta react-best-practices del plugin disponible.

## Aceptación
Desde backend: npm run lint, npx tsc --noEmit y pruebas pertinentes; npm run build para rutas/SSR. Verifica teclado, foco, etiquetas, móvil/escritorio y estados reales. HTTP 200 no equivale a validación visual o login autenticado.
