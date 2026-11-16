# Bodega Básico — flujo modelo (Prompt Maestro §12)

Estado de cada paso, verificado en el código de la rama (PR #9 + esta fase).

| Módulo | Flujo pedido | Estado | Dónde |
|---|---|---|---|
| Inicio | Empresa, caja, ventas, stock, fiados, VENDER destacado; por rol | **Reconstruido.** VENDER en la cabecera; indicadores reales (ventas de hoy, estado de caja, fiados por cobrar, stock bajo) con error y reintento; accesos según el rol. El cajero ya no ve el total del mes. Bodega Pro y Empresa antes no tenían accesos (el tablero era solo para Básico): ahora todos los planes usan el mismo motor. | `role_home.dart`, `inicio.dart`, `nav/role_matrix.dart` |
| Venta | Buscar/escanear → seleccionar → cantidad → carrito | Existe (PR #9) | `pos.dart` |
| Carrito | Productos, cantidades, descuentos autorizados, subtotal, impuestos, total | Existe (PR #9). Los descuentos son cupones y promociones (`precios`, en `pos.dart`): **no vienen en Básico** según la matriz real de planes. | `pos_cart_review.dart`, `pos.dart` |
| Pago | Efectivo con vuelto; Yape/Plin/tarjeta; manual vs. confirmación bancaria | Existe y es honesto: "He verificado el abono en mi cuenta", "No se conecta automáticamente al banco". | `pos_payment.dart` |
| Confirmación | Registrar **una sola vez** → resultado real → comprobante | Existe: `fastCheckoutAtomic` con `request_id` guardado en el teléfono (`pending_checkout.dart`): un reintento no duplica la venta. | `repo.dart`, `pos_payment_success.dart` |
| Comprobantes | Emitir → historial → SUNAT → compartir | Existe (PR #9) | `retail_receipts.dart` |
| Inventario | Catálogo → detalle → alta/edición → stock | Existe | `products.dart` |
| Compras | Proveedor → productos → costos → confirmación → recepción → inventario y finanzas | Existe (PR #9), RPC idempotente. Exige administrador (la base lo exige). | `retail_purchases.dart`, `services/retail_purchase.dart` |
| Fiados | Cliente → deuda → abonos → saldo → historial | Existe | `fiados.dart` |
| Caja | Apertura → movimientos → arqueo → cierre | **Reorganizado.** Pasos visibles (1 Apertura · 2 Movimientos · 3 Arqueo · 4 Cierre); la acción principal va fija abajo ("Abrir caja" o "Cerrar caja (arqueo)"); error con Reintentar. Se respeta el **arqueo ciego**: antes del cierre no se muestran montos, tampoco en Inicio. | `cash_day.dart` |
| Reportes | Período → indicadores → detalle → exportación autorizada | Existe; solo con `reports.view` (finanzas, administrador, propietario). | `reports.dart` |

## Verificaciones transversales
- **Permisos**: cada bloque y acceso pasa por `Access.allows` (granular, denegar por defecto) y `FeatureEntry.allowed`.
- **Licencia**: `Access.has` falla cerrado (sin licencia verificada en línea no hay funciones).
- **Empresa activa**: el Inicio por rol se vuelve a crear al cambiar de empresa, rol o plan (`ValueKey`).
- **Errores y reintentos**: indicadores y Caja muestran el error con Reintentar.
- **Persistencia real**: todo lee de Supabase (`day_summary`, `day_closings`, `credit_balances`, `products`) con RLS.

## Pendiente en bodega
- Carrito y pago pasar a `DsActionBar` (hoy tienen su propio botón inferior del PR #9).
- Retirar `RetailBasicModules` del Inicio heredado (`home.dart`) cuando se retire la barra v2.
