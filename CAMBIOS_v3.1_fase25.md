# Fase 25 · Tiempo real en el resto de pantallas
- Reportes, Impuestos, Ganancias (refresco silencioso: no parpadea ni borra lo que ya ves), Equipo, Papelera, Encuestas, Promociones/cupones y Puntos ahora se actualizan solos.
- Ganancias: el debounce propio se reemplazó por el LiveHub (una sola vía de recarga).
- LiveHub escucha además: organization_members, org_invites, org_settings, trash, surveys, promotions, coupons, loyalty_ledger.
- Migración 20261121 publica en Realtime org_invites, trash, surveys, promotions, coupons, loyalty_ledger (ya aplicada en tu Supabase).
- Ejecutar: flutter pub get && flutter analyze && flutter test
