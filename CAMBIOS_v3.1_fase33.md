# Fase 33 · Vender como en el video (flujo directo)
Pedido de Frank tras ver la demo de otro sistema: abrir en Vender, comanda y precuenta impresas, catálogo de ejemplo y cobro en un toque, para todos los rubros.

**1. Cada rubro abre en SU primera pestaña.** El rubro se elige al empezar (como ya estaba definido) y cada uno mantiene su barra. Solo si la barra incluye Vender (Bodega) abre ahí: pestaña Vender = cuadrícula de productos. Restaurante y los demás NO se saltan a ninguna pantalla. Se quitó el botón extra "Más funciones" de Vender: Cotizaciones, cuaderno, tienda, etc. siguen en Menú → Otras funciones.
**2. Cobro en un toque.** Cobrar → eliges Efectivo / Yape / Plin / Tarjeta / Transferencia → se crea la venta, se registra el cobro y se abre el ticket listo (se imprime solo si hay impresora Bluetooth o de red configurada; con "PDF" no abre diálogos en cada venta). La boleta/factura electrónica se emite con el botón de siempre en el detalle. "Más opciones" abre el flujo completo (cliente, factura, crédito).
**3. Restaurante.** En Mesas: botón "Tomar pedido" → Mesa (vacío = para llevar), toca platos, ver detalle (nota por plato: "sin cebolla") → **Comanda** (sin precios, para cocina) y **Precuenta** ("NO ES COMPROBANTE DE PAGO"). Cada pedido que llega por la carta QR tiene un botón imprimir comanda. Sin impresora configurada salen en PDF de rollo.
**4. Catálogo de ejemplo.** Si no hay productos: "Cargar productos de ejemplo" (por rubro, precios referenciales editables, sin cargarse solos). Sin foto, cada producto muestra un emoji; las fotos reales las sube el dueño en Productos.

Honestidad / límites:
- No pude compilar ni probar en teléfono; revisión estática (sintaxis, importaciones). La impresión real depende de tu impresora.
- La comanda de la tomada en caja NO se guarda en la base (solo se imprime); no aparece en Comandas de la pantalla. Los pedidos de la carta QR sí.
- Cobrar rápido marca la nota como "enviada" (la base solo acepta cobros así); queda registrada como venta pagada.
- Las fotos de ejemplo no se incluyen (no hay imágenes con licencia en el proyecto).

Probar: ver docs/GUIA_PRUEBAS_RUBROS.md (sección Fase 33).
Ejecutar: flutter pub get && flutter analyze && flutter test


## Cada rubro con su propio documento (pedido de Frank)
- Aislamiento: los productos, clientes y ventas son de CADA empresa (org_id + RLS); como cada empresa tiene un solo rubro, lo que creas en Bodega no aparece en Restaurante ni en otro rubro. Los productos de ejemplo se cargan solo del rubro de esa empresa.
- Restaurante: comanda + precuenta (ya hecho).
- Taller: **Orden de trabajo** · Servicios técnicos: **Orden de servicio** · Construcción: **Orden de obra** (con línea de firma del cliente).
- Salón y Consultorio: **Cita** · Educación: **Horario / clase**.
- Se imprimen desde el detalle de la orden/cita (ícono de impresora). Son documentos internos, NO comprobantes de pago. Sin impresora configurada salen en PDF de rollo.
- Bodega usa el ticket de venta; Mayorista, sus pedidos/cotizaciones en PDF (ya existían).
