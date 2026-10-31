# FacturaVoz v3.1 · Fase 14 — Construcción: alerta de gasto por obra

"Margen por obra" solo mostraba un margen sobre lo facturado, que al inicio de una obra (con adelanto, comprando materiales) sale engañoso.

- Nueva señal por obra, comparando **% del contrato ya gastado** contra **% ya facturado**:
  - **Rojo**: ya gastaste todo el contrato (o más).
  - **Amarillo**: gastas más de 15 puntos por encima de lo que llevas facturado.
  - Sin contrato (sin hitos) no hay señal.
- Es una **señal para revisar**, no contabilidad: los gastos se guardan con IGV y los hitos pueden ir con o sin IGV, así que confírmalo con tu contador. Los 15 puntos son un criterio de la app (`obra.dart`), ajustable.
- Sin cambios en base de datos ni backend.
- Archivos: `app/lib/logic/obra.dart` (nuevo), `app/lib/screens/rubro_tools.dart`, `app/test/obra_test.dart` (nuevo, 4 pruebas).
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test`, teléfono.
