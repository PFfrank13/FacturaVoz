# FacturaVoz — Fase 5: distribución firmada y aceptación física (Bodega/Tienda)

Fecha: 17 de noviembre de 2026. Estado inicial: Fases 3 y 4 integradas en `main`, CI y emulador API 35 aprobados.
Alcance: **entrega Android, firma de distribución, instalación física, impresora y pruebas reales**.
No cambiar migraciones, RLS, licencias de Solvex Hub, planes comerciales ni los demás rubros.

## A. Qué es automático y qué NO lo es

**Automatizable y verificable en GitHub Actions:** invariantes de publicación, tests de preflight de seguridad, código nativo Android, pruebas Flutter, SQL, compilación APK **debug** y smoke con emulador. Esto NO equivale a una APK comercial firmada.

**Solo equipo custodio de la clave:** generar APK/AAB **release** con el keystore privado, comprobar firmas criptográficas, SHA-256 y el certificado de la misma identidad histórica. No almacenar el keystore, passwords ni `signing.properties` en GitHub, mensajería, repositorio o artefactos CI.

**Requiere hardware/cuentas reales:** instalación en teléfono físico, impresora Bluetooth o LAN ESC/POS 58/80 mm, POS y confirmación bancaria, emisión SUNAT y CDR, accesibilidad TalkBack, conectividad intermitente, latencias y actualización sobre la versión instalada del cliente.

## B. Firma y configuración (Windows, PowerShell 5.1)

1. Instalar Flutter 3.47.9, Android SDK Build Tools (incluido `apksigner.bat`), Java JDK (incluido `jarsigner`), Python 3 y, para instalación física, Android Debug Bridge (`adb`). El flujo actual usa Gradle Java 17. Verificar compatibilidad con `flutter doctor -v`.
2. Conservar la clave de firma de producción anterior: una clave **nueva** puede impedir actualizar la app ya instalada y cambia el certificado. Si es el primer lanzamiento, generar y resguardar una clave propia siguiendo la documentación de Flutter/Android y el procedimiento de custodia de la empresa.
3. Crear en el perfil de Windows `C:/Users/TU_USUARIO/FacturaVoz-Signing/signing.properties`. Ejemplo de estructura (no valores reales):
   ```properties
   storeFile=C:/Users/TU_USUARIO/FacturaVoz-Signing/facturavoz-release.jks
   storePassword=REEMPLAZAR_LOCALMENTE
   keyPassword=REEMPLAZAR_LOCALMENTE
   keyAlias=alias-release
   ```
   La ruta debe ser **absoluta, externa al repositorio**; el keystore debe existir. No usar `debug.keystore` ni `androiddebugkey`. Nunca subir ese archivo.
4. Crear `app/dart_defines.json` **local, ignorado por Git**, con solo defines públicos; `APP_VERSION` debe coincidir con el prefijo de `version:` en `app/pubspec.yaml` (actual: `3.3.0+8` → `APP_VERSION: 3.3.0`). Ejemplo:
   ```json
   {
     "SUPABASE_URL": "https://TU_PROYECTO_REAL.supabase.co",
     "SUPABASE_ANON_KEY": "sb_publishable_TU_CLAVE_PUBLICA",
     "API_BASE_URL": "https://TU_BACKEND_REAL",
     "APP_VERSION": "3.3.0"
   }
   ```
   Los textos de ejemplo **no pasan** las comprobaciones reales. NUNCA incluir `service_role`, contraseñas, URL de base de datos, claves de Groq o secretos de infraestructura: los `dart-defines` se compilan en la app.
5. Desde la raíz del repositorio, lanzar:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\release\build_signed_android.ps1 -DefinesFile .\app\dart_defines.json
   ```
   Para instalar automáticamente en **un único teléfono ADB autorizado** usar además `-InstallOnDevice`. No conectarse a dispositivos no autorizados.

El script ejecuta preflight, Flutter analyze/test, construye `app-release.apk` y `app-release.aab`, verifica la firma APK mediante `apksigner verify`, la firma del AAB mediante `jarsigner -verify`, y genera `app/build/fase5-release-evidence.json` con hashes SHA-256 y versión (no contiene contraseñas).

**Importante:** una firma verificada es necesaria, pero no garantiza que el certificado sea el histórico correcto. Comparar el SHA-256 del certificado de firma con el del APK/AAB oficial anterior o la identidad de upload key de Play Console. Si no coincide, **detener actualización y distribución**. Para instalación directa, el APK debe estar firmado con el certificado que el dispositivo espera para actualizar la app.

## C. Pruebas físicas obligatorias

| Prueba | Preparación | Criterio de aprobación |
| --- | --- | --- |
| Instalación y actualización | Un Android físico con pantalla pequeña y uno moderno; cuenta de staging | `adb install -r` instala/actualiza sin firma incompatible, inicia sesión correctamente y no borra datos no autorizados |
| Empresa A / B | Dos empresas de prueba, cuentas/cajeros propios | Datos, productos, caja e impresora de A no aparecen en B; B configura su propia impresora; no se hereda el antiguo `fv_printer_v2` |
| Ticket 58 mm y 80 mm | Dos impresoras ESC/POS reales; Bluetooth y LAN si aplica | Texto/QR legibles, corte, ancho correcto, tildes y `Ñandú`; un error de impresora ofrece PDF sin volver a crear la venta |
| Carrito/POS | Productos con/ sin stock; lector real de código | Cantidades, precio, IGV y saldo visibles; un reintento sin red no duplica venta, pago ni movimientos de stock |
| Medios de pago | Efectivo y Yape/Plin en cuentas de prueba autorizadas | Vuelto exacto; transferencia solo se registra tras revisión humana, **nunca** declara verificación bancaria automática |
| Comprobantes | Entorno SUNAT habilitado, credenciales administradas fuera del repo | Boleta/factura, envío, CDR y estado fiscal comprobados; ticket interno no se anuncia como comprobante aceptado |
| Caja | Apertura, ingreso, egreso, arqueo ciego y cierre | Registro correcto por medio de pago y empresa; cerrar de A no afecta a B |
| Accesibilidad | TalkBack, texto 1.4×, orientación y Android 10/12/14+ | Botones alcanzables, foco comprensible, sin pérdidas de datos ni desbordamientos |
| Rendimiento y conectividad | Catálogo de staging representativo, red limitada, corte de red | Medir p50/p95/p99 y tasa de fallos; no prometer métricas sin mediciones, recuperar operación con mismo id |
| Rollback | Copia de seguridad previa y APK anterior de prueba | Ruta de recuperación documentada y probada; nunca aplicar downgrade con pérdida de datos reales |

En Bodega, el SQL actual **permite stock negativo** cuando se vende sin existencias. No se puede prometer bloqueo de sobreventa; tratarlo como decisión funcional pendiente antes de publicar una política de inventario estricto.

## D. Reglas de seguridad antes de publicar

- Confirmar `npm audit --omit=dev` sin HIGH/CRITICAL y revisar alertas del resto de la cadena. La excepción temporal `picomatch` dev-only caduca el 31-12-2026 y **no** prueba que haya parche upstream.
- Verificar versiones, APK/AAB, package ID `dev.solvexsoftware.facturavoz`, huella del certificado y checksum contra la lista de distribución.
- Ejecutar pruebas de permisos Básico/Pro/Empresa y roles de Bodega sin dar acceso a Copiloto en Básico.
- Mantener la nueva configuración de impresora por empresa. **Cada negocio debe elegir y probar de nuevo su ticketera una vez**; no se importan ajustes antiguos compartidos para evitar fugas de comprobantes.
- No iniciar ventas reales, emitir en SUNAT producción o subir paquetes a Play Store sin cuentas, autorización, plan de rollback y evidencia firmada.
- Conservar registro privado de operador, fecha, dispositivo, Android OS, versión, SHA-256 del artefacto, huella de firma, resultados y fallos. No guardar información de clientes ni credenciales en informes públicos.

## E. Puerta de salida de la Fase 5

**Ingeniería lista:** CI backend/PostgreSQL/Flutter y Android emulador completos, preflight de distribución aprobado en CI y cambios fusionados.

**Distribución lista:** compilación release local firmada, huella del certificado coincidente, instalación física aprobada, impresora real verificada, SUNAT/CDR validado y checklist firmado por responsable.

Solo se puede declarar Fase 5 **completamente aceptada en producción** cuando ambas puertas estén aprobadas. CI verde sin clave privada ni hardware **no satisface** la segunda puerta.
