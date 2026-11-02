# FacturaVoz · Fase 36 — Fotografías integradas

Se incorporaron las fotografías optimizadas de los nueve rubros al proyecto Flutter real.

## Qué incluye
- Once imágenes WebP de 1280 × 720: nueve rubros, pantalla de bienvenida y mini-market.
- Imágenes guardadas en `app/assets/photos/`, declaradas en `app/pubspec.yaml`.
- Rutas conservadas: `sectorPhotoFor()` y pantallas de bienvenida, clientes, productos, Vender, reportes y ajustes.
- Capas de contraste recalibradas en banners, bienvenida, login y ajustes para mostrar más detalle sin sacrificar el texto superpuesto.
- Vista de contacto: `docs/FASE36_FOTOGRAFIAS_NUEVAS.jpg`.

## Importante
- Los assets son ilustraciones generadas con apariencia fotográfica. No son fotos verificadas de negocios reales.
- No se cambiaron migraciones SQL, backend, ventas, impuestos ni reglas de los nueve rubros.
- El ZIP se verificó por CRC y todas las imágenes se abrieron correctamente; no se pudo compilar Flutter aquí porque el SDK no está instalado.

## Compilación en Windows
Desde `app/`: `flutter pub get`, `flutter analyze`, `flutter test` y posteriormente tu comando habitual `flutter run --release`.

Para reconstruir el paquete después de mover assets, reinicia la aplicación; si ves fotos viejas en una compilación anterior, genera nuevamente el APK. No hagas cambios en Supabase por estas fotografías.
