# FacturaVoz v3.1 · Fase 17 — Avisos de `flutter analyze`

`flutter analyze` en tu máquina: 0 errores, 5 avisos. Corregidos:
- `home.dart`: `HomeHeader`, `HomeHeaderPill` e `InvoiceRow` ahora aceptan `key`.
- `menu.dart`: variable `shown` sin uso eliminada.
- `new_invoice.dart`: se comprueba `mounted` antes de abrir el segundo diálogo (después de un `await`).
Sin cambios de comportamiento. Falta tu resultado de `flutter test`.
