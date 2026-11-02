# FacturaVoz — entrega Fase 35 (UI y fiabilidad inicial)

## Cambio visual implementado

- Nueva identidad azul petróleo, turquesa y coral sutil, aplicada desde el sistema de tema común.
- Pantalla de bienvenida con imagen ambiental de apariencia fotográfica, transición de entrada, temporizador breve y opción Omitir/Comenzar; desactiva animación si el sistema pide movimiento reducido.
- Nueve imágenes ambientales de **categoría** en `app/assets/photos/`, vista de elección de rubro y banners de Inicio. **No** son fotografías documentales verificadas de negocios reales; son escenas de apariencia fotográfica obtenidas de imágenes generadas. No sustituyen productos ni datos propios.
- Cabecera de Ajustes con imagen del rubro, botón principal y tarjetas armonizados; PDF A4 con nueva paleta sin cambiar QR, montos ni estructura fiscal.
- Nuevo icono vectorial rasterizado original y recursos para launcher Android/iOS/Web. Tras generar carpetas nativas: `cd app && dart run tool/post_create.dart` copia el icono correspondiente.
- Rubros, RLS y datos permanecen separados; no se cambió la selección de rubro ni se introdujeron artículos ficticios.

## Cambio transaccional (P0 parcial)

`backend/supabase/migrations/20261123_v31_fast_checkout_atomic.sql` (requiere todas las migraciones anteriores, incluida 20261122) crea:

1. `invoice_items.product_id` opcional, comprobación del SKU contra la empresa activa.
2. Trigger de descuento de stock por **ID** (no por nombre), con fila bloqueada y rechazo de existencias insuficientes.
3. Tabla con clave idempotente `(org_id, request_id)` y políticas RLS.
4. RPC `fast_checkout_atomic` que ejecuta factura, líneas, estado, inventario y pago en una transacción PostgreSQL, con reintentos de la misma clave.
5. Flutter POS llama a este RPC y conserva la clave en la pantalla hasta confirmación, sin volver al flujo inseguro de tres peticiones.

**Importante:** migración nueva NO aplicada en tu Supabase. Haz un respaldo y ejecútala **solo en STAGING** primero. Si no la ejecutas, el cobro rápido devuelve error hasta instalarla; no hay fallback inseguro. Las líneas elegidas desde el catálogo en facturas manuales conservan `product_id` y se insertan en la transacción de creación. Para facturas dictadas o líneas escritas sin SKU, el disparador solo resuelve nombres si hay **un único** producto activo con ese nombre en esa empresa; si hay varios, rechaza la emisión con un mensaje de ambigüedad. Las líneas que no coinciden con ningún producto siguen tratándose como servicios/no stock; falta certificar todas las entradas externas y resolver la asociación a SKU para voz/importaciones. El POS no persiste la clave de reintento entre reinicios completos del proceso, por lo que la recuperación tras cierre forzado sigue pendiente de implementar y certificar. Comandas y cobro son dos operaciones distintas; vinculación posterior puede fallar y aún requiere reconciliación integral.

## Pruebas realizadas y pendientes

- Realizado: inventario de archivos, generación y comprobación de imágenes, estructura del proyecto y sintaxis JS k6 con `node --check`; verificación de integridad del ZIP.
- **NO realizado:** `flutter analyze`, `flutter test`, compilación APK/AAB, ejecución SQL en Supabase, tests de RLS y concurrencia reales, imágenes en dispositivos, ticketera, Lycet/SUNAT Beta, pruebas de restauración y capacidad real para 200 negocios.
- `tools/load/k6/` contiene el punto de partida para pruebas de POS **solo en staging**, con tokens de usuarios de prueba. `backend/supabase/tests/verify_fast_checkout_staging_readonly.sql` verifica conciliación y referencias sin escribir datos. Ninguna prueba en este paquete certifica 30.000 ventas por día.

## Orden de ejecución recomendado

1. Crear Supabase STAGING separado, restaurar datos de prueba y aplicar SQL hasta 20261122. **Solo después** inspeccionar y aplicar `20261123_v31_fast_checkout_atomic.sql`.
2. Ejecutar `flutter pub get`, generar `android/`, `ios/`, `web/` si faltan, `dart run tool/post_create.dart`, `flutter analyze` y `flutter test`.
3. Comprobar visualmente bienvenida, icono en Android/iOS y cada uno de los nueve rubros, modo oscuro, accesibilidad, y todo el flujo de impresión.
4. En staging: pruebas multiempresa RLS (usuario de empresa A intenta UUID de B), dos productos mismo nombre, 10 cajas/5 unidades, cobro duplicado con misma request_id y corte de red antes/durante/después del commit.
5. Ejecutar `tools/load/k6/` por etapas; medir p95/p99, tasa real, CPU/Postgres, reconexión, volúmenes de datos, protección de cuotas y costes.
6. No lanzar masivamente hasta completar el PDF de plan de carga: reconciliación contable, recuperación, observabilidad, roles/planes, colas de facturación, PITR y tres ciclos aprobados.

**Esta entrega es una evolución de código y recursos, no una certificación de producción ni una garantía de funcionamiento sin pruebas.**
