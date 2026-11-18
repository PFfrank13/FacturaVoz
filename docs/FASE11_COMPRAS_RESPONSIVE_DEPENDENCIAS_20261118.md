# Fase 11 · Compras Bodega adaptable y seguimiento de dependencias

Fecha: 2026-11-18. Alcance: Flutter (Compras/recepción), pruebas y mantenimiento de dependencias.

## Diseño y experiencia

- El formulario de Compras se centra con **ancho máximo de 960 dp**, medido sobre el espacio disponible mediante `LayoutBuilder`, no sobre la resolución física del dispositivo. Conserva 16 dp en pantallas pequeñas.
- Las tarjetas del catálogo reemplazan el borde violeta fijo por `colorScheme.outlineVariant`.
- La acción de añadir usa `colorScheme.primary`, accesible en tema claro y oscuro.
- El historial deja de forzar una superficie oscura fija y hereda el tema.
- No cambia el flujo transaccional de recepción, bloqueo de operación incierta, permisos, stock, facturación ni las tablas SQL.

## Dependencias

Dependabot supervisa ahora tres ecosistemas:
1. npm en `/backend` (existente).
2. pub de Flutter en `/app`.
3. GitHub Actions en `/`.

Cada actualización va por PR y requiere revisión y CI; no se autofusiona ni altera `pubspec.lock` a mano. El aviso `GHSA-fc5q-39xc-vjpf` de `picomatch` en herramientas de desarrollo permanece sin parche oficial confirmado, y debe seguirse mediante issue #14 sin desactivar `audit-gate.mjs` ni elevar la excepción a producción.

## Pruebas y comercialización

- Pruebas unitarias de anchos 320, 360, 768, 960, 1040, 1280, 1440, 1920 y 3440 dp, además de entradas no finitas.
- `flutter analyze`, `flutter test`, Flutter web, APK debug, CI backend/PostgreSQL y emulador Android antes de integrar.
- **No autorizar publicación comercial** únicamente por compilar con `example.supabase.co`: identificar el hosting Flutter real, configurar variables reales por entorno, verificación de cuentas y planes, pruebas físicas, y para Android firma release privada.
- El equipo Vercel accesible a esta sesión no identifica el proyecto FacturaVoz vinculado al repositorio. No crear un reemplazo ni apuntar a un proyecto distinto sin verificar titularidad.
