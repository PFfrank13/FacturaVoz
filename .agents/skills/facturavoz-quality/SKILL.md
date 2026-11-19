---
name: facturavoz-quality
description: "Verificar recorridos de FacturaVoz con pruebas financieras, RLS, regresión, UI y evidencia reproducible."
---

# facturavoz-quality

## Archivos de entrada
- [backend/scripts/test-restored-pos.mjs](../../../backend/scripts/test-restored-pos.mjs)
- [backend/scripts/serve-retail-lab.mjs](../../../backend/scripts/serve-retail-lab.mjs)
- [backend/scripts/test-retail-lab-http.mjs](../../../backend/scripts/test-retail-lab-http.mjs)
- [app/test/receiving_flow_test.dart](../../../app/test/receiving_flow_test.dart)
- [docs/SOLVEX_PRIMERA_VENTA_LAB.md](../../../docs/SOLVEX_PRIMERA_VENTA_LAB.md)

## Trabajo
Distingue unitario/mock, widget/golden, HTTP→SQL y E2E autenticado. Usa scripts de laboratorio solo con la copia local validada; contienen identidad sintética fija, no Supabase Auth real. Si navegador no disponible, comunica limitación y sigue con pruebas independientes; no simules revisión visual. Datos históricos restaurados son privados, no adjuntes dumps/logs con contenido. Para seguridad especializada usa security-best-practices si el alcance lo amerita; no lo cargues por cada edición.

## Aceptación
Demuestra errores, doble cobro, concurrencia, red interrumpida y aislamiento de empresa según cambio. Registra comandos/resultados y límites. No actualizar goldens para esconder un defecto. No llamar E2E a un conjunto de mocks.
