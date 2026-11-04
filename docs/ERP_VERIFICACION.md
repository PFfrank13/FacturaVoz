# Verificación de la entrega local

4 de noviembre de 2026. Sin credenciales productivas en las pruebas.

## Resultados

| Comprobación | Resultado |
|---|---|
| `flutter analyze --no-pub` | Sin incidencias |
| `flutter test --no-pub` | 223 pruebas correctas |
| `flutter build web --no-pub` | Compilación JavaScript correcta; advertencias Wasm de dependencias existentes |
| `flutter build apk --debug --no-pub` | APK debug compilado |
| `npm test` | 151 pruebas correctas, 15 archivos |
| `npm run lint` | Correcto; excepción CommonJS limitada a scripts `.cjs` |
| `npx tsc --noEmit` / comprobación de tipos del build | Correcto |
| `npm run build` | Compilación Next.js correcta |
| PostgreSQL aislado | Error histórico reproducido y nuevas regresiones correctas |
| Revisión visual web | Acceso local observado en escritorio y móvil; 375 px de ancho sin desbordamiento horizontal |
| Accesibilidad responsive Flutter | WorkQueue a 320/768 px, texto 1.6, sin excepciones de layout y navegación por toque probada |
| `git diff --check` | Sin errores de whitespace |

APK: `app/build/app/outputs/flutter-apk/app-debug.apk`. Es una compilación de prueba, no un paquete de distribución ni una aplicación conectada y validada de extremo a extremo.

## Cobertura nueva

- Los nueve rubros, tres planes y seis roles no recuperan stock denegado u omitido.
- Flags booleanos estrictos; límites numéricos separados. Valores desconocidos, desarrollo, caché obsoleta y modos no operativos fallan cerrados.
- Misma política para navegación y ruta directa. URL de inventario denegada antes de consultar datos.
- Organización mal formada, sesión ausente y pertenencia ausente se rechazan antes de obtener licencia/datos.
- Una mutación revalida derechos; ignora `org_id` y `user_id` falsificados dentro del formulario. Ver catálogo no concede edición.
- Tablas vacías, búsqueda etiquetada, región accesible y escape de nombres con HTML.
- PostgreSQL: implementación histórica real de plan/matriz, nueva precedencia, límite omitido, -1, stock denegado/permitido, actualización de trabajo denegada, cambio entre funciones denegado y bloqueo de escritura.

## Qué demuestra la prueba SQL

El contenedor `facturavoz-erp-local-sql-20261104` se creó sin red, sin puertos publicados y sin volúmenes del host. Se usaron tablas sintéticas mínimas, funciones históricas extraídas del repositorio y la migración nueva. Todo el esquema/datos de prueba se creó dentro de una transacción terminada con rollback. El contenedor quedó detenido, sin borrar archivos del usuario.

El harness comprueba que el contenedor objetivo no tenga red ni montajes. Usa stubs para `org_mode` y `license_enforced`: **no valida autenticación Supabase, activación real, RLS multiempresa completa ni el ciclo de expiración**. Las pruebas de pertenencia web también son unitarias con mocks. Debe completarse la integración sobre una copia local del esquema antes de aprobar la migración.

Para repetirlo, crear un contenedor aislado nuevo (nombre distinto al detenido), con la imagen PostgreSQL local, sin puertos ni montajes; indicar su nombre en `FV_SQL_CONTAINER` y ejecutar `node backend/scripts/test-erp-sql.mjs`. Nunca apuntar esta prueba a Supabase Production ni reutilizar una base con datos reales.

## Limitaciones observadas

- Flutter Web compila a JavaScript; las dependencias `flutter_secure_storage_web` y `flutter_tts` advierten incompatibilidad con Wasm. También aparece una advertencia de familia CupertinoIcons no incluida. No se hizo una migración de dependencias.
- Android compila con avisos de plugins que usan Kotlin Gradle Plugin y acceso nativo Java. No se verificaron instalación, permisos de micrófono, impresión ni ejecución en teléfono físico.
- No hay compilación iOS en este host Windows.
- No se probó login real, correo OTP, Groq, SUNAT, impresión, licencias reales ni mutaciones contra Supabase Production.
- No se capturaron ni validaron visualmente todas las pantallas autenticadas. No se inventaron empresas/datos para mostrarlos como reales.
- Falta paridad funcional completa de la web y diseño específico de todos los procesos de los nueve rubros: ver `ERP_AUDITORIA_Y_ALCANCE.md`.

## Seguridad operativa

No hubo despliegue, push, actualización de secretos, cambios a licencias reales ni ejecución de migraciones remotas. El webhook y cron de sincronización permanecen intactos. La migración nueva no actualiza `org_licenses`, activaciones ni `private.app_config`, y conserva el bypass de mantenimiento y el comportamiento de la guardia cuando enforcement está desactivado.
