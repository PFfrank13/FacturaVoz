# Fase 26 · Arranque instantáneo
Problema: al abrir, la app esperaba 3 llamadas de red seguidas (empresas → perfil+permisos+licencia → configuración) antes de mostrar nada.
Solución: `services/boot_cache.dart` guarda CIFRADO (llavero de Android/Keychain) solo: empresas, perfil de la empresa activa, rol/permisos, licencia y configuración del negocio.
- Al abrir: se lee el archivo a la vez que arranca Supabase; la app entra DIRECTO a la pantalla principal y confirma con la red por detrás (si algo cambió, se actualiza sola).
- NO se guarda: clientes, facturas, montos, productos. Tampoco en web.
- Se borra al cerrar sesión y si entra otra cuenta. Si cambió de empresa activa, no se usa (no se adivinan permisos).
- Honestidad: durante ~1 s se pueden ver permisos/licencia de la última vez; la base de datos igual aplica los reales (RLS).
- Primera vez tras instalar/iniciar sesión: sigue el camino normal (con carga). Desde la segunda apertura: instantáneo.
- Supabase.initialize aún corre antes de la primera pantalla de datos (renueva la sesión si venció: puede sumar ~0,3-0,8 s con mala señal).
- Pruebas: test/boot_cache_test.dart. Ejecutar: flutter pub get && flutter analyze && flutter test

## Pantalla gris al abrir (arranque nativo)
Esa pantalla gris/blanca NO es de Flutter: es la ventana de arranque de Android, que se muestra mientras el motor de Flutter se enciende.
`tool/post_create.dart` ahora la deja del color de la app (claro #F8F6FD / oscuro #14132B, también en Android 12+), así que pasa directo al
logo o a la pantalla principal sin parpadeo gris. Es idempotente.
Aplicar (una vez, desde `app/`):
```
dart run tool/post_create.dart
flutter clean
flutter run --release --dart-define=...      # reinstala completo; el hot reload NO cambia la parte nativa
```
Nota: el tiempo que tarda el motor en encenderse (~0,3-1 s en teléfonos modestos) lo pone Android/Flutter; ya no se ve gris, pero no se puede quitar del todo.
