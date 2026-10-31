# FacturaVoz v3.1 — Fase 2 (Inicio, Clientes de hoy, fiados, caseros)
- **Inicio rico** (vuelve el de la v2.0, mejorado): encabezado aurora con la cifra del mes contando hacia arriba, píldoras ("Hoy S/ X · N ventas", "N ventas emitidas", borradores, meta), gráfico de 14 días, accesos de tu rubro con color propio, sugerencias del Copiloto, buscador + filtros y lista de comprobantes.
- **Venta nueva al instante**: al guardar, el Inicio recarga sin esperar y el comprobante aparece arriba (orden por hora de creación).
- **Clientes de hoy**: quién compró, a qué hora y qué se llevó (solo ventas reales de hoy; sin borradores, anuladas ni notas de crédito).
- **Fiados por pasos** ("Se llevó fiado"): 1) cliente (con toques rápidos) → 2) monto y qué se llevó → 3) cuándo paga → anotar. "Me pagó" sigue en una sola pantalla.
- **Casero / Frecuente / Nuevo** en la ficha del cliente (6+ compras en 90 días = casero, 3–5 = frecuente) con descuento SUGERIDO (5 % / 3 %); lo decides tú, la app no lo aplica sola. Historial de compras muestra Boleta/Factura y qué compró.
- Archivos: `screens/inicio.dart` (reescrito), `screens/home.dart` (piezas públicas HomeHeader/InvoiceRow), `screens/fiados.dart`, `screens/client_profile.dart`, `logic/regulars.dart`, `models.dart` (hora de creación), `services/repo.dart`; prueba `test/regulars_test.dart`.
- No hace falta SQL nuevo.
- No verificado: compilar/correr en el teléfono (sin SDK Flutter aquí). Corre `flutter analyze` y `flutter test`.
