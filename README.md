# FacturaVoz (Android · iOS · Web)

```
app/      Flutter (Android, iOS, Web): login por código, dictado, revisión, PDF en el dispositivo
backend/  Next.js en Vercel: SOLO la API /api/parse (guarda la clave de Groq) + web heredada
          backend/supabase/schema.sql + migrations/20261023_mobile_prod.sql  (base de datos)
infra/    lycet/ → Lycet (SUNAT) en tu VPS Oracle con Docker + Caddy
docs/     DESPLIEGUE.md · SEGURIDAD.md · FISCAL.md
```

Flujo: la app graba (≤60 s) → `POST /api/parse` con el token de sesión → Groq (Whisper + Llama) →
JSON de factura → el usuario revisa → RPC `create_invoice` (atómica, RLS) → PDF generado en el teléfono.

Lee primero `docs/DESPLIEGUE.md` y `docs/SEGURIDAD.md` (incluye lo que NO está resuelto y es decisión tuya).

**Novedades v1.1 "Negocio Pro"** (cotizaciones, enlaces de cobro, cobranza automática, gastos y rentabilidad,
escáner con IA, Copiloto de voz, conciliación por foto, score de crédito, radar de stock): `docs/NEGOCIO_PRO.md`.

**Novedades v1.2 "Revolución"** (tienda en línea con pedidos, facturación recurrente, Clientes 360, meta del mes con
predicción, calculadora de margen, plan de rescate de caja con IA, nuevo Inicio): `docs/REVOLUCION.md`.
