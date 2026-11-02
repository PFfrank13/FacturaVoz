# FacturaVoz v3.1 · Fase 20 — Arranque más rápido y avisos de consola

**Arranque** (no se pudo medir aquí; mídelo con `flutter run --release`):
- `main.dart`: el logo se dibuja **al instante**; Supabase se inicia detrás (antes la app esperaba a Supabase con la pantalla vacía).
- Carga de datos tras iniciar sesión: de **5 esperas de red en serie a 3**:
  - Invitaciones y lista de empresas a la vez (se vuelve a listar solo si de verdad se unió a una empresa).
  - Perfil de la empresa y permisos/licencia a la vez.
  - Permisos y licencia a la vez entre sí.
  - El perfil pide solo la fila de la empresa (1 llamada menos); el perfil de usuario solo si hace falta.
- Archivos: `lib/main.dart`, `lib/app_state.dart`, `lib/access.dart`, `lib/services/repo.dart`.
- No es literalmente "instantáneo": la app sigue necesitando 3 consultas a Supabase antes de mostrar tu negocio. Para ser instantánea haría falta guardar permisos y licencia en el teléfono, y eso toca la seguridad (un rol o licencia viejos); no lo hice sin que lo decidas.

**Plugins**: `flutter_tts` ^4.2.5 (misma versión mayor). `file_picker` y `record` no se migraron: la versión sin aviso exige un Flutter más nuevo y cambia su API; migrar uno solo no quita el aviso.

**Mensajes**: `docs/AVISOS_CONSOLA.md` explica cada aviso y cuál se puede apagar.

Verificado: sintaxis. Falta: `flutter pub get`, `flutter analyze`, `flutter test` y probar el arranque.
