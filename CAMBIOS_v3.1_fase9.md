# FacturaVoz v3.1 · Fase 9 — Servicios técnicos: aviso obligatorio antes del corte

Ya existían el corte/reconexión por mora y los equipos con serie. Lo que faltaba era que la app **obligara** el aviso previo.

- "Aviso previo" abre WhatsApp con el mensaje y **registra la fecha del aviso** en la ficha del abonado.
- "Registrar corte" queda **deshabilitado** hasta que exista un aviso de al menos 1 día antes (se habilita desde el día siguiente).
- Cada abonado muestra "Sin aviso previo", "Avisado hoy" o "Avisado hace N días".
- Al reconectar, el aviso se borra: el próximo corte exige un aviso nuevo.
- El plazo de 1 día es una regla de la app, no una norma legal; la constante `minNoticeDays` en `app/lib/logic/cutoff.dart` se puede subir. Revisa los plazos exigidos con tu asesor (OSIPTEL).
- Un abonado sin celular no se puede avisar por WhatsApp y por tanto no se puede cortar desde la app.
- Sin cambios en base de datos (se guarda en `clients.extra`).
- Archivos: `logic/cutoff.dart` (nuevo), `services/rubro_repo.dart`, `screens/rubro_tools.dart`, `test/cutoff_test.dart` (nuevo, 3 pruebas).
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test`, teléfono. WhatsApp no confirma que el mensaje se envió: la app registra el aviso al abrir el chat.
