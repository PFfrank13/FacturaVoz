# FacturaVoz — Plan Básico para Bodega/Tienda
## Mapa de navegación y pruebas de aceptación

Esta aplicación usa una **licencia local Básico validada por Supabase**, sin
conceder funciones de Pro/Empresa y sin desactivar RLS. Los módulos se muestran
únicamente cuando el rol y las funciones efectivas lo permiten.

### 1. Inicio
- El negocio abre en Inicio; identifica rubro y plan en el encabezado.
- Muestra ventas reales del período y una cuadrícula de accesos al Plan Básico.
- El botón «Venta rápida» abre el POS. **Copiloto no se muestra en Básico**.
- Nunca rellenar cifras con ventas, clientes, stock o estados SUNAT simulados.

### 2. Venta rápida (POS)
- Busca por nombre/código y permite escanear productos de la empresa.
- Tocar una tarjeta añade producto; tarjeta con fotografía solo si el negocio
  ha subido `products.image_path`. Un producto sin foto se identifica como tal.
- La franja «Ver carrito / Cobrar» se ve **encima** del dock de navegación
  cuando el POS es una pestaña embebida.
- Carrito a pantalla completa: sumar/restar, vaciar (confirmación),
  subtotal, IGV y total. Ningún paso de cobro acepta carrito vacío.
- Selección del método: Efectivo (monto recibido/vuelto); Yape, Plin,
  Tarjeta o Transferencia (verificación manual por cajero). El QR procede
  únicamente de la imagen real subida por el comerciante.
- Se conserva el snapshot del checkout y su request ID antes de enviar la
  transacción para evitar dobles cobros ante cortes de red.
- **Venta a fiado:** disponible en el carrito si el rol/plan lo permite; abre el formulario de cliente y exige fecha de vencimiento, sin registrar un pago ficticio.
- **Solo después de confirmación del servidor**, se muestra Venta registrada.
  Desde allí se abre Boleta/Factura, comprobante y compartir/imprimir.
- Registrar venta **no equivale** a obtener CDR de SUNAT, ni confirma
  una transferencia bancaria.

### 3. Inventario
- Productos, precios, foto real, código de barras, stock, stock mínimo.
- Altas, ediciones y movimientos según permisos del rol.
- Quitar fondo con IA está condicionado a configurar proveedor externo;
  cuando no está configurado, conservar imagen original.
- Foto pendiente no se sustituye por marca inventada.

### 4. Compras y Reponer
- Compras: proveedor, cantidades, costo, recepción, historial y pago posterior.
- Reponer: advertencias y sugerencias basadas en el stock realmente registrado.
- Ajustar stock o registrar recepción debe dejar movimiento auditable.

### 5. Fiados
- Clientes, saldo, ventas al crédito, abonos e historial; se comprueba
  que el saldo no se duplique al reintentar un cobro incierto.

### 6. Caja
- Apertura, entradas/salidas, cobros, arqueo y cierre.
- Vuelto y diferencias calculados desde montos reales.

### 7. Reportes
- Ventas, productos, compras y períodos. No mostrar crecimiento ficticio
  ni rentabilidad inventada cuando falta el costo de adquisición.

### 8. Facturación electrónica
- Consulta de comprobantes, boleta/factura, PDF y ticket.
- Emisión a SUNAT requiere RUC y domicilio fiscal, usuario SOL secundario
  y certificado válido; no simular estados «Aceptado por SUNAT».

### 9. Configuración
- Datos fiscales, usuarios y roles, medios de pago, impresora, perfil
  del negocio y seguridad; según permisos.
- No guardar claves secretas de pasarelas o del certificado en el cliente.

## Comprobación local en Windows

Abrir la copia independiente `FacturaVoz-PlanBasico\app` en Android Studio:

```powershell
flutter run -d emulator-5554 --debug --dart-define-from-file=dart_defines.json
```

Conservar intacta la carpeta original `voice-invoice\app` de la rama
`codex/facturavoz-evolucion`; las ramas son divergentes y necesitan su
propia integración posterior.

**Limitaciones de certificación:** la prueba de compilación no sustituye
a una validación con Yape/Plin/terminal POS, SUNAT, impresora física y
fotos reales del inventario. La base de prueba contiene 10 productos y
ninguna fotografía en `products.image_path` al momento de esta revisión.
