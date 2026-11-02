# FacturaVoz v3.1 — Fase 36: corrección de compilación (hotfix 2)

## Síntomas

La compilación `flutter run --release` falló en las pantallas de Clientes, Vender, Ajustes, Productos y Reportes con seis errores: cinco incompatibilidades entre `String?` y `String` cuando el rubro todavía no está definido, y un `Access` no importado en `products.dart`.

## Cambios

- `app/lib/ui/widgets.dart`: las funciones visuales `sectorPhotoFor`, `sectorAccent`, `sectorIcon`, `sectorShortName` y `sectorTagline` aceptan un rubro opcional (`String?`). Los valores desconocidos o aún no cargados mantienen los valores de respaldo definidos antes. `SectorPhotoBanner` también acepta rubro opcional. Esto cubre las llamadas desde Clientes, POS/Vender, Ajustes, Reportes y el centro de ventas.
- `app/lib/screens/products.dart`: import explícito de `../access.dart` para usar `Access.instance.rubro`.
- Todos los demás archivos del ZIP original se conservan sin cambios.

No se introducen tablas, columnas, migraciones ni modificaciones de las reglas comerciales o multiempresa. No hay SQL adicional que ejecutar para este hotfix.

## Instalación en Windows

1. Guarda una copia del proyecto anterior.
2. Descomprime el ZIP completo o copia los dos archivos de `app/lib/` del ZIP de parche a las rutas correspondientes de tu proyecto.
3. Desde PowerShell en `C:\Users\pined\Documents\voice-invoice\app` ejecuta:

   ```powershell
   flutter pub get
   flutter analyze
   flutter test
   flutter run --release --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_CLAVE_PUBLICA --dart-define=API_BASE_URL=https://TU_BACKEND.vercel.app --dart-define=APP_VERSION=3.3.0
   ```

   Sustituye los marcadores de posición por tus valores anteriores. No copies los corchetes de Markdown dentro de las URLs y no compartas claves secretas privadas.

## Validación efectuada

- Revisados los puntos del registro de compilación.
- Corrección estática de los tipos de entrada opcionales y del import faltante.
- Verificación de estructura de paréntesis/corchetes/llaves y recursos fotográficos del proyecto.
- Comparación del ZIP para confirmar que solo los dos archivos Dart se editaron; se añadió este documento.

**Pendiente:** la compilación Flutter y los tests reales en un entorno con Flutter SDK y el despliegue del usuario. No se certifica todavía la capacidad de 200 empresas ni la emisión con SUNAT.
