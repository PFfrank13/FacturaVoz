# FacturaVoz v3.1 · Fase 12 — Mayorista: aviso de límite de crédito al vender

El límite de crédito por cliente ya existía, pero solo se veía en la pantalla de Crédito. Al vender no avisaba nada.

- Al hacer una factura **Al crédito** a un cliente con límite fijado, la app suma lo que ya debe + esta venta:
  - **Cerca** (80 % o más del límite): aviso amarillo.
  - **Pasa el límite**: aviso rojo con cuánto se pasa y cuánto ya debe.
- Es **solo advertencia**: no bloquea la venta; decides tú.
- Solo cuenta deudas en la misma moneda de la factura. Clientes sin límite no muestran nada. Si falla la carga de datos, el aviso simplemente no aparece.
- La deuda se compara por nombre del cliente (igual que la pantalla de Crédito).
- Sin cambios en base de datos ni backend.
- Archivos: `app/lib/logic/credit.dart` (nuevo), `app/lib/screens/new_invoice.dart`, `app/test/credit_test.dart` (nuevo, 3 pruebas).
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test`, teléfono.
