---
name: facturavoz-commerce
description: "Implementar recorridos comerciales FacturaVoz: cliente, venta, cobro, inventario, compras, deudas y caja."
---

# facturavoz-commerce

## Archivos de entrada
- [backend/src/app/actions/invoices.ts](../../../backend/src/app/actions/invoices.ts)
- [backend/src/app/erp/receiving.ts](../../../backend/src/app/erp/receiving.ts)
- [backend/src/lib/retail/money.ts](../../../backend/src/lib/retail/money.ts)
- [backend/supabase/tests/test_cloud_checkout.sql](../../../backend/supabase/tests/test_cloud_checkout.sql)
- [app/lib/logic/retail_money.dart](../../../app/lib/logic/retail_money.dart)

## Trabajo
Prioriza Cliente → Venta → Cobro → Emisión → PDF → Historial. Identidad de producto por UUID, no descripción; servicio con stock null no exige inventario. Precio/impuesto y redondeo consistentes entre Flutter, web, SQL y PDF. Venta no equivale a cobro; recepción no equivale a compra pagada. Distingue pago digital manual, pendiente y confirmado por proveedor. No cambies descuentos a precio de catálogo a ciegas: la propuesta local retail_checkout todavía necesita política compatible de promociones. Abonos distribuyen saldo sin duplicar caja.

## Aceptación
Evidencia de datos antes/después por empresa: factura, líneas, pagos, stock, caja e historial. Reintento sin duplicados; rechazo sin residuos. Utilidad o valoración solo si existen costos/datos suficientes.
