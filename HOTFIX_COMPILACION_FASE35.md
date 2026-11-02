# FacturaVoz — Fase 35 · Hotfix compilación Android release (02/11/2026)

Este ZIP contiene el proyecto completo de Fase 35 con **dos ajustes puntuales** para responder a los errores reales enviados desde Windows al intentar `flutter run --release`.

## Cambios

1. `app/lib/screens/pos.dart` — Se reemplazó la llamada a un componente inexistente `MarketPhotoBanner` por el componente real `SectorPhotoBanner`, con `rubro: 'bodega'`. El widget ya existe en `app/lib/ui/widgets.dart`. El banner solo se muestra cuando el rubro es bodega y el catálogo está vacío.
2. `app/lib/screens/settings.dart` — `Access.instance.rubro` puede ser `null`. Ahora se proporciona el valor predeterminado `'bodega'` al método `sectorPhotoFor()`; evita pasar un `String?` donde se requiere `String`.

## Comprobación de esta entrega

- Se revisó que el componente `SectorPhotoBanner` exista y tenga los argumentos utilizados.
- Se comprobó que las fotografías para los nueve rubros estén incluidas en `app/assets/photos/` y registradas en `pubspec.yaml`.
- Se comprobó la integridad del archivo ZIP generado.
- **No se ha ejecutado Flutter, `flutter analyze`, `flutter test` ni compilado APK**. El entorno de generación no tiene instalado el SDK Flutter. La corrección elimina los dos errores reportados, pero pueden aparecer otros al compilar nuevamente.

## Procedimiento en Windows PowerShell

1. Haz copia de tu carpeta actual. Extrae este ZIP en otra carpeta o reemplaza solamente `app/lib/screens/pos.dart` y `app/lib/screens/settings.dart` de tu copia actual.
2. Entra a `app` y ejecuta:

```powershell
flutter pub get
flutter analyze
flutter test
```

3. Ejecuta luego tu `flutter run --release` **con tus propios valores de `--dart-define`**, sin signos de Markdown `[]()` en las direcciones y sin compartir tus claves en capturas.

**No es necesario ejecutar nuevas migraciones SQL en Supabase para este hotfix visual de compilación.** La migración `20261123_v31_fast_checkout_atomic.sql` pertenece a Fase 35 y sigue teniendo sus requisitos originales de pruebas en staging.

Si aparecen más errores, envía las primeras líneas que comiencen con `lib/...:...: Error:`. No es necesario volver a pegar todo el stack trace de Gradle.
