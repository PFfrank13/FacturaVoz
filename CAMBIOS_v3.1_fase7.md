# FacturaVoz v3.1 · Fase 7 — Pantallas al sistema de diseño

- 29 pantallas de `app/lib/screens` usan ahora `Radii.sm/md/lg/xl/pill` en vez de números sueltos (8, 14, 18, 28, 99).
- Cambio mecánico y exacto: no cambia ningún tamaño visible. Los radios intermedios (12, 13, 15, 16, 20, 22, 24, 26) se dejaron como estaban para no alterar el diseño.
- Sin cambios en base de datos ni backend.
- Verificado: sintaxis Dart con tree-sitter (solo `pay_score.dart` marca falso positivo, igual que el original).
- No verificado: `flutter analyze`, `flutter test` ni pantallas en el teléfono.
