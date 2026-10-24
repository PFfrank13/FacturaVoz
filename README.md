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
