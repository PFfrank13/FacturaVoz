# Importador de libro Excel (A1)

Abre: Menú → Mi negocio → **Importar datos** → elige el `.xlsx`. Si el archivo tiene varias hojas, se abre el
importador de libro; si tiene una sola hoja (o es CSV) sigue funcionando el importador anterior.

## Qué hace
1. **Lee y clasifica cada hoja por sus COLUMNAS** (no por el nombre): Clientes, Comprobantes, Detalle, Catálogo.
   Las hojas de instrucciones o leyenda (p. ej. `LEEME`) se ignoran. Encuentra la fila de encabezados aunque haya
   títulos arriba. Acepta sinónimos (`cliente_nombre_razon_social`, `razon_social`, `nombre_cliente`…). Nunca usa la
   columna de id como nombre.
2. **Vista previa** antes de guardar: hojas detectadas, conteos por tipo, anulados, líneas, ventas, notas de
   crédito, **total neto**, por cobrar (por moneda) y avisos con ejemplos.
3. **Guarda por bloques** con tu sesión (RLS): clientes (1 000) → productos (500) → comprobantes con líneas y cobros
   (200 por bloque).
4. **Compara** lo esperado (archivo) con lo guardado (contado en la base) fila por fila.
5. **Deshacer**: borra solo lo que trajo ese archivo (comprobantes, sus líneas y cobros, clientes y productos nuevos
   no usados en otra parte). Lo que ya tenías no se toca. Solo dueño/administrador.

## Reglas
| Tema | Regla |
|---|---|
| Relación | Clientes por `id_cliente`; productos por `codigo_item`; líneas por `id_factura`. |
| Tipo | Factura, Boleta, Nota de crédito (también 01/03/07 y por serie F/B/FC/BC). Notas de débito: no soportadas (aviso). |
| Estado | Pagada → pagada · Parcial → emitida con cobro parcial · Pendiente → emitida · Vencida → emitida con vencimiento pasado · **Anulada → se guarda anulada y NO cuenta como venta**. |
| Pagado / saldo | `pagado` se registra como cobro (fecha de pago no viene en el archivo: se usa la fecha de emisión y se anota "fecha de pago no informada"). El saldo = total − pagado. |
| Montos | Con IGV, **tal como vienen** (subtotal, descuento, base, IGV, total se guardan exactos y "bloqueados"). Si falta un dato se deduce (base = total − IGV, o total ÷ 1,18). Si base + IGV ≠ total, se respeta el archivo y se avisa. |
| Notas de crédito | Se guardan en positivo y **restan** en todos los totales. Se enlazan al comprobante que modifican. |
| Documentos | DNI 8 dígitos, RUC con dígito verificador, CE, pasaporte. Inválidos (p. ej. `TESTDNI0000`) → "sin documento" + aviso. |
| Repetidos | Clave tipo + serie-número. Importar el mismo archivo dos veces no duplica nada. Si el número ya existe en FacturaVoz, se omite. |
| SUNAT | Los comprobantes importados ya fueron emitidos en tu sistema anterior: la app **no** los reenvía (bloqueado en el servidor). |

## Cálculo del total neto (el mismo en Inicio, Reportes, Mi negocio y Copiloto)
```
neto = Σ total (con IGV) de facturas, boletas y notas de venta  emitidas o pagadas, NO anuladas, NO rechazadas por SUNAT
     − Σ total de notas de crédito NO anuladas
     (por moneda; nunca se suman soles y dólares)
```
En la base: `private.sale_rows()` → `sales_summary`, `sales_series`, `business_snapshot`.

## Prueba con 1 500 comprobantes
El archivo real `facturas_clientes_migracion_1500.xlsx` **no llegó adjunto**; se generó uno **sintético** con la
misma estructura (`backend/tests/fixtures/make_fixture.py`): LEEME, Clientes (250), Facturas (1 500: 1 168 facturas,
274 boletas, 58 NC), Detalle_Facturas (3 738), Catalogo (14), con anuladas, parciales, vencidas, dólares, filas sin
nombre y 3 documentos `TESTDNI0000`.
- Lectura y vista previa (`backend/tests/workbook.test.ts`): 9/9 ✓ — conteos exactos y neto PEN 621 469,52 / USD 9 343,51.
- Guardado en Postgres (`backend/supabase/tests/test_v3_import.sql`): 250 clientes, 1 500 comprobantes, 3 738
  líneas, 14 productos, neto y cobrado **idénticos** a lo esperado; `sales_summary` = `sales_series` =
  `business_snapshot`; segunda importación: 1 500 repetidos, 0 nuevos; deshacer: 0 restos; otra empresa: bloqueada.
- Tiempo de guardado: **≈ 1,9 s** para los 1 500 comprobantes (5 bloques).

Para probar con TU archivo: impórtalo en una empresa de prueba y compara la pantalla final "En el archivo / Guardado".
