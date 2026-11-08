# FacturaVoz — Plan Básico retail: circuito operativo y estado verificable

Fecha: 8 de noviembre de 2026.
Rama: `fix/basic-pos-crash-recovery-20261108` (PR borrador).
**No se ha desplegado nada en producción.** Cambios de backend y Flutter requieren pruebas en staging.

## Alcance y navegación

En la experiencia de **bodega/tienda** y **mayorista/distribuidor**, el circuito objetivo es:

**Comprar → Ingresar → Vender → Cobrar → Cerrar caja → Analizar → Reponer.**

Las pantallas reutilizadas siguen respetando permisos (rol) y funciones de licencia concedidas por Solvex Hub, sin crear un plan paralelo ni permitir bypass en la UI:

| Paso | Ruta de entrada | Funciones y conexión real |
| --- | --- | --- |
| Comprar / ingresar | Menú → Compras y recepción; Productos → icono Compras; Ajustes → Compras | `RetailPurchasesScreen` → `RetailPurchaseRepo.receive` → RPC `retail_receive` → encabezado, líneas y eventos de inventario → `products.stock` y `unit_cost` |
| Vender | Barra Vender → `PosScreen` | Catálogo real, cantidad, precio, producto por ID. Requiere el RPC existente `fast_checkout_atomic` de `20261123` |
| Cobrar | POS → Cobrar | Efectivo con vuelto calculado en céntimos; Yape/Plin/tarjeta/transferencia con confirmación **manual** del cajero y datos de cuenta en Ajustes → Medios de cobro |
| Registrar venta | POS → `Repo.fastCheckoutAtomic` | Factura, líneas, descuento por SKU y cobro en una sola transacción cuando la migración está instalada; mismo ID en reintento tras corte de red o reinicio |
| Fiados y clientes | Barra Fiados; Menú → Clientes / Cobranza | Flujos existentes. **Aún no** se ha incorporado fiado como opción de la misma operación atómica de POS; se registra en su módulo. |
| Caja | Barra Caja; Menú → Caja | Resumen de ventas, medios, retiros, gastos; cierre ciego por denominación PEN; el servidor obliga nota cuando existe diferencia y no permite sobreescribir un arqueo |
| Comprobantes | Menú → Comprobantes / SUNAT | Proceso fiscal preexistente. **No** equivale a certificación de SUNAT ni garantiza emisión offline. |
| Analizar | Menú → Mi negocio / Reportes | Reportes preexistentes sobre los registros reales y permisos vigentes. |

## Compras, pagos e inventario

El ingreso por compras se realiza con una operación atómica e idempotente:
- En cada renglón es obligatorio `product_id` real de la organización, cantidad positiva, costo en **céntimos enteros**.
- Solo el propietario/administrador autorizado en servidor puede mutar inventario; requiere licencia vigente con `stock=true`. Una cuenta de otro negocio no puede usar el identificador de recepción ajeno.
- Orden determinista de bloqueo de filas de productos para prevenir conflictos de SKU concurrentes.
- El sistema registra la cantidad, costo, stock antes y después, evento de recepción inmutable. El stock histórico sigue existiendo en `products.stock`; **esto NO implementa todavía un kardex universal** de todos los movimientos.
- Si la compra se marca pagada, registra el gasto una vez en la misma transacción. Si fue en efectivo, registra además `cash_movements.egreso`. No se inventa salida de caja por Yape/Plin.
- Si se marca pendiente, registra ingreso de mercadería, pero **no implementa aún cuentas por pagar ni su posterior cancelación**; por eso no debe presentarse como el módulo de compras final.
- La copia local cifrada conserva la operación que pudo haber confirmado el servidor, evitando repetirla con otro request ID al reabrir.

## Cobros y arqueo

- **Efectivo**: valida `recibido >= total` y calcula vuelto en enteros; el dato pagado registrado en backend es el total de la venta (no el recibido), y el vuelto es información del ticket/nota.
- **Yape y Plin**: el cajero ve datos guardados del negocio y debe marcar expresamente que verificó el dinero. **No existe verificación bancaria automática, webhook de confirmación ni QR interoperable generado.** No etiquetar estos pagos como comprobados por el banco.
- **Caja**: conteo ciego de billetes y monedas de S/ 200 a S/ 0.10, con diferencia mostrada después de cierre. El servidor exige explicación si diferencia supera 1 céntimo y rechaza un segundo cierre por fecha/empresa en vez de reemplazar la historia.

## Qué sigue siendo pendiente (no declarar terminado)

1. Implementación **offline-first** real en dispositivo: base transaccional local, cola de sincronización, serie por terminal, resolución de conflictos y pruebas de al menos siete días sin red. Actualmente POS usa un RPC online y detiene cobros sin conexión.
2. Kardex inmutable completo, inventario por tienda/almacén, reserva/transporte, vencimientos, conteo por escáner y reversión de ajustes de stock. Esta entrega agrega eventos únicamente de **recepciones nuevas**.
3. POS con tickets en espera, pagos mixtos y fiado en un solo checkout, costo/margen con PIN, devolución/anulación transaccional, venta bajo stock cero con regularización y cola de impresión.
4. Cuentas por pagar, proveedores maestros, recepción desde fotografía/XML de comprobante, documento SUNAT y contabilización de pago pendiente.
5. Yape/Plin con QR propio verificable y evidencia de aceptación real; terminal POS físico, SUNAT real, comprobantes con contingencia legal, impresión en terminales.
6. Reconciliación completa del módulo restaurante si el proceso muere entre factura/comanda/enlace y pruebas de privacidad multiempresa, concurrencia/stock y reconexión.
7. Diseño visual integral aprobado y los logos oficiales de pasarelas cuando existan activos/licencias verificables.
8. Aprobación de migraciones de staging, backup, medición y plan de rollback.

## Migraciones y ensayos requeridos

**Nunca ejecutar todas las migraciones históricas contra la base actual a ciegas.** Preparar entorno staging aislado y copia de estructura representativa; verificar dependencias:
- `20261122_v31_comandas_caja_persistentes.sql` para restaurante, si corresponde.
- `20261123_v31_fast_checkout_atomic.sql` para POS.
- `20261124_v31_solvex_activation_required.sql` y `20261125_v32_hub_feature_precedence.sql` para permisos Hub.
- `20261126_v32_retail_receive.sql` para compras.
- Auditorías SQL de solo lectura: `backend/supabase/tests/verify_fast_checkout_staging_readonly.sql` y `verify_retail_receive_staging_readonly.sql`.

Demostrar con dos tenants A/B y dos cajeros:
- Compra con un SKU, abono real y salida de caja solo una vez; duplicar `request_id` retorna mismo recibo.
- Corte de red antes/después de commit, reinicio y recuperación de la misma operación sin duplicar existencias ni gastos.
- Emisión en caja, inventario y cierre confrontando totales de ventas, cobros y gastos; nunca intentar RLS de usuarios reales como prueba.
- Venta rápida con dos cajas concurrentes y SKU limitado, control de duplicados, pagos por método y restauración.
- Sin permisos ni licencia válida: ninguna mutación, incluyendo invocación directa por RPC.

## Estado de integración

El PR contiene código y pruebas; CI debe ejecutar `flutter analyze`, `flutter test`, builds Android/Web y backend TypeScript/tests. Éxito de CI **no prueba** el ciclo en staging ni habilita despliegue a producción.


## Avances posteriores — 8 de noviembre de 2026

### Ticket abierto (borrador local, no venta)
`PosCartStore` conserva en almacenamiento del dispositivo el carrito, notas,
mesa y cupón por usuario y empresa, con escrituras serializadas y restauración
tras reinicio. No sobrescribe el respaldo cuando su lectura falla. Una venta
rápida confirmada borra primero el borrador editable y después la clave de
operación pendiente: si se interrumpe, se recupera **la misma operación**.
No es todavía venta ni facturación offline.

### Compra a crédito: pago posterior completo
`20261127_v32_retail_settle.sql` registra un único pago diferido por
recepción y por clave de solicitud, sin volver a ingresar el stock. Crea
el gasto y la salida de caja en una sola transacción cuando el método es
efectivo. `RetailSettlementScreen` permite pagar o recuperar el intento
anterior tras timeout; Yape/Plin se confirman **manualmente**. Recepciones
pagadas inicialmente y pagos posteriores guardan `cash_move_id` cuando
hay una salida de efectivo, para conciliarla exactamente.

**Limitación:** no hay abonos parciales, estados de cuenta de proveedores,
ni verificación bancaria automática.

### Ventas sin stock disponible
`20261128_v32_retail_sale_stock_events.sql` sustituye el rechazo por
stock insuficiente. Registra la venta, descuenta el SKU pudiendo quedar
negativo y guarda evento con stock antes/después y factura de origen.
La vista `retail_stock_flow` muestra solo eventos futuros de entradas y
salidas; **no es kardex completo**. En Productos aparece un acceso para
recibir mercadería cuando hay existencias negativas.

### Puerta de staging antes de producción
1. Preparar una **base aislada** sin datos productivos y realizar backup.
2. Revisar dependencias y migraciones 20261123 a 20261128, aplicadas en
   orden solo después de validar el esquema de ese entorno.
3. Ejecutar los verificadores de lectura:
   `verify_fast_checkout_staging_readonly.sql`,
   `verify_retail_receive_staging_readonly.sql` y
   `verify_retail_settle_staging_readonly.sql`.
4. Demostrar dos empresas aisladas por RLS; recibo duplicado con mismo
   `request_id`; pago duplicado del mismo recibo con otra solicitud;
   simultaneidad de cajeros y corte de red después del COMMIT.
5. Vender con stock cero, reponerlo y cuadrar caja, gastos y existencias.
   Probar reinicio de app, cambio de empresa, cierre ciego, impresora
   y los procedimientos legales de comprobantes SUNAT.

**No fusionar ni desplegar sin superar las pruebas.** Compilar correctamente
no demuestra funcionamiento integral con cobros ni inventarios reales.
