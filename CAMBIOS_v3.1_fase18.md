# FacturaVoz v3.1 · Fase 18 — Prueba corregida

`flutter test`: 191 pruebas pasaron, 1 falló: `whenText` esperaba "el lunes 3/11" pero el 3/11/2026 es **martes**. El código estaba bien; el error era del texto esperado en la prueba. Corregido en `test/appointments_test.dart` (y en los ejemplos de los documentos).
