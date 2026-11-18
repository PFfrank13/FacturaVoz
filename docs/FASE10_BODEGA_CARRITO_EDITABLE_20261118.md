# Fase 10 · Edición directa del carrito POS (Bodega/Tienda)

Fecha: 2026-11-18. Cambio limitado a la interfaz Flutter y sus pruebas.

## Experiencia

- En escritorios con carrito lateral (>=900 dp del área útil de POS), cada SKU tiene botones de aumentar, reducir y quitar, con objetivos táctiles de 48 dp y texto accesible.
- Los productos por peso o fracción se pueden retirar: «−» reduce hasta cero sin crear cantidades negativas.
- El panel muestra los importes recalculados por `_lines()` y `computeTotals()` después de actualizar el estado; descuentos y tarifas siguen el motor de precios vigente.
- Cuando una recuperación de carrito, cobro o almacenamiento está pendiente, los controles de edición y revisión quedan ocultos o deshabilitados.
- La edición usa el mismo método `_add(Product, delta)` del POS, que ya protege los saldos de stock visibles, la persistencia del borrador por empresa y los cobros idempotentes. PostgreSQL conserva la validación definitiva del stock.

## Fuera de alcance

No modifica SQL, políticas RLS, licencias, permisos, endpoints de cobro, emisión SUNAT, compilación firmada ni el despliegue web. Se aplica exclusivamente al POS Bodega/Tienda integrado al shell empresarial.

## Puertas de calidad

- `flutter analyze`, `flutter test`: pruebas de incremento, decremento, eliminación, fracción y deshabilitación.
- CI completo y smoke test de emulador Android deben aprobar el commit final antes de fusionar.
- Pruebas físicas de impresora, SUNAT real y release firmada siguen siendo verificaciones aparte; no inferir que se ejecutaron por el CI.
- La integración del Flutter UI en un hosting de producción compatible sigue siendo un trabajo independiente del backend Next.js desplegado en Vercel.

## Reversión

Revertir el PR sin migraciones; no elimina ventas ni existencias previamente registradas.
