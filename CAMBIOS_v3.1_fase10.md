# FacturaVoz v3.1 · Fase 10 — Agenda: confirmar citas por WhatsApp

Para bajar las inasistencias en salón, consultorio, taller y servicios técnicos.

- En **Agenda**, cada cita futura, sin terminar y con celular del cliente muestra **Confirmar por WhatsApp**.
- Abre WhatsApp con el mensaje armado: nombre, negocio, qué cita, "hoy / mañana / el lunes 3/11", hora y pedido de confirmar (con aviso de liberar el horario si no puede venir).
- La app **no envía nada sola** y no sabe si el cliente respondió: no se guarda "confirmada" porque no hay forma honesta de saberlo sin que tú lo marques.
- Sin cambios en base de datos ni backend.
- Archivos: `app/lib/logic/appointments.dart` (nuevo), `app/lib/screens/jobs.dart`, `app/test/appointments_test.dart` (nuevo, 3 pruebas).
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test`, teléfono.
