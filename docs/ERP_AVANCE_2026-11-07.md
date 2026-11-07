# Reconstrucción ERP — avance local, 7 de noviembre de 2026

## Fase 1 / Bodega: implementada parcialmente, NO cerrada

Base Git: `704632d`. Se conservaron los cinco archivos pendientes al retomar. No se hicieron push, despliegues, cambios de secretos/licencias ni consultas o escrituras productivas. Sin cambios SQL en esta intervención.

### Flujo y archivos

- `app/lib/screens/shell.dart`: el dock reserva su altura; no se superpone al cobro del Scaffold interno.
- `app/lib/screens/pos.dart`: barra de cobro adaptable, confirmación explícita, permiso de venta/cobro revalidado antes de operar; carrito y vaciado bloqueados mientras un cobro pueda haberse confirmado; acceso a agregar productos desde el vacío. Se conserva `fast_checkout_atomic`.
- `app/lib/ui/pos_checkout_bar.dart`, `checkout_sheet.dart`: total y acción Cobrar visibles; efectivo recibido, vuelto, confirmación única y recuperación con el mismo método. Pagos digitales son registros del cajero, no aprobaciones bancarias.
- `app/lib/screens/catalog.dart`, `products.dart`: catálogo bajo facturar, no stock; edición por permiso; controles de existencias bajo stock. Publicar en tienda deja de ser obligatorio al crear un producto: foto/código no impiden el catálogo básico.
- `app/lib/screens/inicio.dart`, `app/lib/ui/business_header.dart`, `theme.dart`: se conservaron y validaron los cambios visuales pendientes; encabezado de negocio y acciones adaptables con tokens de papel/tinta.
- `backend/src/lib/erp/access.ts`, `backend/src/app/erp/[org]/page.tsx`, `[org]/[module]/page.tsx`: ruta Vender y acceso principal autorizado para Bodega/Mayorista.
- `backend/src/components/erp/PointOfSale.tsx`, `backend/src/app/erp/checkout.ts`, `backend/src/app/globals.css`: catálogo web, cantidades, resumen, confirmación, efectivo/vuelto y recibo con enlace al historial. Precios y pertenencia al catálogo se comprueban en servidor; operación mediante el mismo RPC que Flutter, sin service role. Recuperación de recibo confirmado aunque cambie el catálogo; snapshot de productos durante reintentos. Hasta 500 productos, 50 líneas; sin promociones, pagos mixtos ni búsqueda remota todavía.

### Pruebas y evidencia

- `app/test/pos_checkout_layout_test.dart`: POS real con datos de prueba inyectados, selección y apertura de cobro por encima de un dock de 94 px, anchos 320/768, licencia facturar=true/stock=false. No llama a una base de datos.
- `app/test/checkout_sheet_test.dart`: efectivo insuficiente, vuelto decimal, doble confirmación, método inmutable al recuperar; teclado y texto 1.6 en 320/768 px.
- `backend/tests/erp-checkout.test.ts`: RPC con empresa/precios verificados, precio manipulado, producto ajeno/no disponible, timeout, recuperación y revocación. Mocks, no prueba de persistencia.
- Flutter: `flutter analyze --no-pub`, sin incidencias; `flutter test --no-pub`, **229 correctas**. Log local: `app/build/erp-tests-20261107.log`.
- Backend: `npm test`, **157 correctas**; ESLint y TypeScript correctos; `npm run build` correcto.
- Flutter Web: compilación final correcta con `flutter build web --no-pub --no-wasm-dry-run`. Log: `app/build/erp-web-build-20261107.log`. Sigue la advertencia preexistente de CupertinoIcons; el primer build también detectó incompatibilidades Wasm de dependencias. No se compiló APK nuevo ni se probó dispositivo físico.
- `git diff --check`: correcto (Git avisa conversión futura LF/CRLF en shell.dart, no errores de whitespace).

### Bloqueos y siguientes pasos obligatorios

1. `docker ps -a` falló: no existe el pipe del motor Docker Desktop Linux. No se ejecutó una venta persistente en laboratorio. Falta probar Auth/RLS, venta → cobro → historial → caja/reportes y concurrencia con el esquema completo. No se afirma cumplimiento del criterio de aceptación de Bodega.
2. La migración previa de precedencia sigue sin validación completa. Revisar defaults de stock, guardas de productos/pagos y `apply_stock_on_issue`: al desactivar stock en un catálogo con existencias anteriores puede intentar descontarlas y fallar. No se habilitó inventario denegado para evitar ese error.
3. Confirmar en laboratorio la semántica comercial de `facturar`, `cobros` y el permiso `collect`; el frontend no concede funciones faltantes. El RPC debe estar instalado en el entorno destino; esta intervención no lo instala.
4. El reintento conserva su clave mientras vive la pantalla. Falta recuperación persistente tras cerrar/navegar/recargar y prueba concurrente del servidor. No afirmar idempotencia extremo a extremo solo por el bloqueo de doble clic.
5. Falta prueba interactiva autenticada de la web y revisión visual de todos los módulos. Las pruebas responsive de Flutter no equivalen a pruebas en teléfono físico.
6. Fases 2–6 y los otros ocho recorridos integrales siguen pendientes. Mayorista reutiliza el POS básico, no queda completo su proceso de cotización/despacho/crédito. No se investigaron todavía los otros ocho sectores en esta intervención.

### Investigación acotada utilizada

Fuentes oficiales consultadas: [Tendi](https://tendi.pe/) y [Alegra Perú POS](https://alegra.com/peru/punto-venta/). Ambas describen conexión entre ventas, inventario y caja; se usó como referencia funcional para dar continuidad a selección → carrito → cobro, sin copiar diseño ni recursos. La guía oficial [Supabase RPC](https://supabase.com/docs/reference/javascript/rpc) se consultó para mantener la llamada autenticada existente. No se adoptaron afirmaciones comerciales de competidores como evidencia de funcionamiento de FacturaVoz.
