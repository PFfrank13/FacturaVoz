# FacturaVoz v3.1 · Fase 15 — Bodega: productos que no se mueven

"Reposición inteligente" decía qué comprar, pero no qué **no** comprar.

- Nueva sección al final: **No se movieron en 30 días** — productos con stock mayor a 0 y cero ventas en 30 días (hasta 15, los de más stock primero).
- Solo muestra cantidades en stock. **No calcula plata parada** porque la app no tiene el costo de todos los productos y no se inventa.
- Un producto recién agregado también puede aparecer: el texto lo avisa.
- Sin cambios en base de datos ni backend (usa los datos que ya carga la pantalla).
- Archivos: `app/lib/logic/stagnant.dart` (nuevo), `app/lib/screens/rubro_tools.dart`, `app/test/stagnant_test.dart` (nuevo, 2 pruebas).
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test`, teléfono.
