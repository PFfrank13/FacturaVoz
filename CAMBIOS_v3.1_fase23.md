# FacturaVoz v3.1 · Fase 23 — Plan y precio por rubro en Ajustes

- **Ajustes → Mi plan** ahora dice el plan, su precio y el rubro: `Plan Pro · S/ 59 al mes · Bodega o tienda`.
- **Mi plan** muestra **Planes para <tu rubro>**: tres tarjetas (Básico, Pro, Empresa) con precio y las herramientas de ese rubro en cada plan.
  Básico = esenciales del rubro; Pro = "todo lo de Básico, más" módulo estrella + Copiloto; Empresa = "todo lo de Pro, más" el resto + Copiloto agente.
  Tu plan lleva borde y la marca "Tu plan"; lo que ya incluyes en verde con ✓, lo de planes superiores en gris con candado.
- "Incluido en tu plan" (lo que tu licencia da de verdad, con complementos) se mantiene; sin rubro elegido sigue saliendo la lista general de "Disponible en planes superiores".
- `rubros.dart`: `planPrices`, `planPriceText`, `planNewTools`.
- **Precios 29 / 59 / 119 soles al mes con IGV incluido: son los PROPUESTOS de `docs/facturavoz-planes.json`.** El que cobra de verdad es Solvex Hub; si cambias un precio allá, cámbialo también en `planPrices` (una prueba compara la app con el JSON y avisa si no coinciden).
- Sin cambios en base de datos ni backend.
- Pruebas nuevas: `test/plan_prices_test.dart` (4). Verificado: sintaxis y la misma lógica reproducida en Python para los 9 rubros. Falta: `flutter analyze` / `flutter test` y ver las pantallas.
