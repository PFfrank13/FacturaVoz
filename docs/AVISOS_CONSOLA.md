# Avisos de la consola al ejecutar `flutter run` — cuáles importan

Ninguno de estos avisos es un error de FacturaVoz. Aquí qué es cada uno y qué hacer.

| Aviso | Qué es | Qué hacer |
|---|---|---|
| `WARNING: A restricted method in java.lang.System has been called … --enable-native-access` | Es de **Gradle** (el compilador de Android), no de la app. | Opcional. En `android\\gradle.properties` **agrega al final de la línea `org.gradle.jvmargs=`** (sin borrar lo que ya tiene) ` --enable-native-access=ALL-UNNAMED`. |
| `Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): file_picker, flutter_tts, package_info_plus, record_android` | Aviso de Flutter: esos plugins aún usan la forma antigua de Kotlin. **Hoy compila bien.** | Esperar a que los autores lo migren. Hoy: `file_picker` lo corrige solo desde la v12 (pide Flutter 3.38 y cambia su API) y `record` desde la v7 (pide Flutter 3.44); `flutter_tts` y `package_info_plus` aún no lo anuncian. Migrar uno solo no quita el aviso, así que se hará junto cuando estén los cuatro. |
| `Upgrading analysis_options.yaml to exclude build and platform directories` | Flutter ajustó un archivo una sola vez. | Nada. |
| `gralloc … Pixel format 0x3b … Failed to allocate (4 x 4)`, `AHardwareBuffer`, `getInterlacedFlag`, `HWUI` | Ruido del **gráfico del teléfono** (Redmi, driver Vulkan). No afecta lo que ves. | Nada. Si molesta, prueba `flutter run --no-enable-impeller` y compara si cambia algo. |
| `I/FlutterActivityAndFragmentDelegate … --enable-dart-profiling` | Aviso de Flutter sobre una opción futura. | Nada. |
| `Skipped N frames! The application may be doing too much work on its main thread` | En **modo debug** el primer arranque es lento (compila y carga todo). | Medir con `flutter run --release`. |
| `PerfMonitor binderTransact … ITextToSpeechService` | El plugin de voz del teléfono (`flutter_tts`) se conecta al motor de voz al abrir. Es del plugin, no de nuestro código. | Nada por ahora. |
| `Geolocator … Creating service / Binding to location service` | El plugin de ubicación se registra al abrir. | Nada. |
