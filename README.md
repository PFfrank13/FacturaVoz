# FacturaVoz (Android · iOS · Web)

```
app/      Flutter (Android, iOS, Web): login por código, dictado, revisión, PDF en el dispositivo
backend/  Next.js: APIs y espacio ERP web /erp/[org], con Supabase Auth, RLS y licencia compartida
          backend/supabase/schema.sql + migrations/20261023_mobile_prod.sql  (base de datos)
infra/    lycet/ → Lycet (SUNAT) en tu VPS Oracle con Docker + Caddy
docs/     DESPLIEGUE.md · SEGURIDAD.md · FISCAL.md
```

**Implementación ERP local (4 noviembre 2026):** [auditoría, matriz de rubros y pendientes](docs/ERP_AUDITORIA_Y_ALCANCE.md),
[sistema visual](docs/ERP_DESIGN_SYSTEM.md) y [pruebas y límites de verificación](docs/ERP_VERIFICACION.md).
La transformación integral sigue en desarrollo. La nueva migración está preparada para revisión y no se ha aplicado en producción.

Flujo: la app graba (≤60 s) → `POST /api/parse` con el token de sesión → Groq (Whisper + Llama) →
JSON de factura → el usuario revisa → RPC `create_invoice` (atómica, RLS) → PDF generado en el teléfono.

Lee primero `docs/DESPLIEGUE.md` y `docs/SEGURIDAD.md` (incluye lo que NO está resuelto y es decisión tuya).

**Novedades v1.1 "Negocio Pro"** (cotizaciones, enlaces de cobro, cobranza automática, gastos y rentabilidad,
escáner con IA, Copiloto de voz, conciliación por foto, score de crédito, radar de stock): `docs/NEGOCIO_PRO.md`.

**Novedades v1.2 "Revolución"** (tienda en línea con pedidos, facturación recurrente, Clientes 360, meta del mes con
predicción, calculadora de margen, plan de rescate de caja con IA, nuevo Inicio): `docs/REVOLUCION.md`.

**Novedades v2.0** (app ordenada por tipo de negocio y modo simple, Ficha 360 de clientes, trabajos y agenda,
equipo con roles, venta rápida con código de barras, fiados, cierre de caja, impuestos "¿cuánto me queda?",
tickets térmicos con logo, licencias Solvex Hub, Copiloto 2.0 y 21 módulos más): **empieza por `CAMBIOS_v2.0.md`**
(qué instalar y en qué orden). Luego `docs/MAPA_DE_FUNCIONES.md`, `docs/GUIA_PRUEBAS_15MIN.md`,
`docs/SOLVEX_HUB.md` y `docs/HOJA_DE_RUTA.md`.
