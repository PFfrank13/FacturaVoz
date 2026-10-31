# FacturaVoz v3.1 · Fase 8 — Restaurante: tablero de mesas

- La pantalla Mesas/Comandas tiene ahora dos vistas: **Comandas** (como antes) y **Mesas**.
- **Mesas** muestra cada mesa con pedidos abiertos: platos, pedidos, tiempo de espera (en rojo desde 20 min si aún no está lista) y el paso más atrasado (Nuevo / Preparando / Listo).
- Los pedidos para llevar o delivery no entran en las mesas; se avisa cuántos hay.
- Solo lee los pedidos que ya llegan por la carta QR. No guarda nada nuevo ni cambia la base de datos.
- Archivos: `app/lib/logic/tables.dart` (nuevo), `app/lib/screens/kitchen.dart`, `app/test/tables_test.dart` (nuevo, 3 pruebas).
- No cobra por mesa ni divide cuenta desde la mesa: eso sigue en "Cuentas y costo por plato".
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test` ni el teléfono.
