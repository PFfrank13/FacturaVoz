# FacturaVoz v3.1 · Fase 13 — Educación: pensiones con atraso y último aviso

La pantalla "Pensiones pendientes" agrupaba por grupo pero no decía desde cuándo ni si ya se había avisado.

- Cada apoderado muestra **días de atraso** (de su deuda más vieja) y, dentro de cada grupo, los **más atrasados van primero**.
- Al tocar "Avisar al apoderado" se abre WhatsApp y se **guarda la fecha del aviso**; la fila muestra "Avisado hoy" / "Avisado hace N días" para no avisar dos veces sin querer.
- No envía nada sola; WhatsApp no confirma que el mensaje se leyó.
- Sin cambios en base de datos (se guarda en `clients.extra`).
- Archivos: `logic/cutoff.dart` (+`lastNoticeText`, `pensionNoticeKey`), `services/rubro_repo.dart` (+`setNoticeDate`), `screens/rubro_tools.dart`, `test/cutoff_test.dart` (+1 prueba).
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test`, teléfono.
