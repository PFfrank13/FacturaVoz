# FacturaVoz v3.1 · Fase 11 — Taller (y servicios): aviso de "listo"

El taller prometía "aviso de listo" pero no existía.

- Al pasar una orden a **Listo para recoger** (taller) o **Instalado** (servicios técnicos), la app pregunta "¿Avisamos a X que ya está listo?" con el botón **Avisar**, que abre WhatsApp con el mensaje armado.
- Solo aparece si el cliente (o el contacto de la orden) tiene celular.
- No envía nada sola y no sabe si el cliente lo leyó.
- Sin cambios en base de datos ni backend.
- Archivos: `app/lib/logic/appointments.dart`, `app/lib/screens/jobs.dart`, `app/test/appointments_test.dart` (+1 prueba).
- Verificado: solo sintaxis. No verificado: `flutter analyze`, `flutter test`, teléfono.
