# FacturaVoz v3.1 — Fase 5 (correcciones, ritmo por rubro, salida a venta)
- **Error corregido (era mío, de la Fase 2)**: el gráfico de 14 días del Inicio se armaba con las últimas 100 facturas; con muchas ventas salía incompleto. Ahora lo calcula el servidor (`sales_series`, misma regla de ventas que la cifra del mes) y rellena con 0 los días sin ventas. Si el servidor no responde, usa el cálculo anterior como respaldo.
- **Casero / frecuente por rubro**: cada rubro tiene su ritmo y sus palabras. Bodega: 4 compras en 30 días = Frecuente, 8 = Casero. Consultorio: 2 en 180 días = Paciente recurrente, 4 = Paciente fiel. Restaurante, salón, técnicos, taller, mayorista, academia y construcción tienen sus propios umbrales (`logic/regulars.dart`, `regularRules`). Son valores iniciales: dime si quieres otros. El descuento sigue siendo solo una sugerencia.
- **Versión 3.1.0+6**.
- **`docs/CHECKLIST_SALIDA_A_VENTA.md`**: lista en orden de todo lo que falta antes de cobrar (SQL, Vercel, claves, pruebas, SUNAT, legal, costos).
- Sin SQL nuevo.
Verificado: sintaxis Dart y reglas con pruebas nuevas (`test/regulars_test.dart`). No verificado: `flutter analyze/test` ni el teléfono.
