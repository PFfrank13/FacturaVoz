# Fase 9 · Punto de venta Bodega/Tienda adaptable

**2026-11-18.** Alcance: interfaz POS Flutter. No cambia el contrato de facturación, la emisión SUNAT, los datos de PostgreSQL, los permisos por plan ni el registro de pagos.

## Flujo comercial

- **Móvil y tablet (ancho disponible inferior a 900 dp de espacio útil):** catálogo con cuadrícula adaptable y barra de carrito/cobro fija. No aparece un segundo menú.
- **PC y ventana amplia (900 dp o más de espacio útil):** catálogo a la izquierda y resumen permanente de venta a la derecha. El carrito muestra SKU/descrición, cantidad, precio unitario, subtotal, IGV y total **calculados por el motor existente**. La acción principal abre `PosCartReviewScreen`: después mantiene el flujo de pago y el guardado idempotente existente.
- **Carrito vacío:** indica cómo empezar y deshabilita «Revisar y cobrar»; nunca inventa una transacción.
- **Existencias:** cuando Bodega tiene stock controlado, la interfaz impide añadir cantidades que **ya** exceden el saldo conocido y señala productos sin stock o por debajo del punto de reposición. El control de la base de datos y la consulta de stock justo antes de confirmar el pago continúan siendo la autoridad final para ventas entre cajas.
- **Servicios o productos sin stock controlado (`stock = NULL`):** conservan la venta libre. Resto de rubros: navegación, catálogo y checkout sin cambios.
- **Fotos:** si todavía no hay fotografía, se muestra un icono contextual y la categoría del catálogo, no una leyenda de contenido inacabado.
- **Accesibilidad:** el resumen es una lista desplazable, con textos de varias líneas, botones de 54 dp y contraste del sistema Enterprise.

## Verificación

- `flutter analyze` y `flutter test` incluyen pruebas nuevas para anchos de 320/360/600/840/1040/1280/1440, modo claro/oscuro, carrito vacío, cálculo de impuestos y stock controlado.
- CI general: PostgreSQL (desde cero y upgrade), backend, test de bloqueo de firma release, build web y APK debug.
- Emulador Android API 35 con flujos reales simulados y sin claves de producción.
- **Prueba física pendiente de evidencias:** impresoras reales, firma release privada y SUNAT real, separadas de este cambio de UI.

Guía: https://docs.flutter.dev/ui/adaptive-responsive/best-practices — medir el ancho disponible del componente, no suponer un tamaño de dispositivo. Los paneles de apoyo son apropiados para pantallas amplias; no se activan en móviles.

## Rollback

Se puede revertir el PR en GitHub, sin migraciones SQL y sin afectar el inventario registrado.
