# FacturaVoz: línea base e Inicio comercial

Fecha: 2026-11-07. Alcance: exclusivamente fases 0 y 1 del prompt definitivo.
Estado: implementación local; recorrido autenticado Básico comprobado parcialmente. Pro/Empresa y aceptación completa pendientes.
No se declara terminada la fase 1 ni los módulos comerciales.

## Línea base recuperable

- Candidato original confirmado por el propietario: `704632d` (version final 2.0).
- Restauración selectiva ya guardada en `def0a14`, independiente de esta navegación.
- Respaldo fuera del repositorio: `C:/Users/pined/Documents/FacturaVoz-Backups/20261107-161003-restauracion`.
- `history.bundle`, `working-tree.zip`, `manifest.json` y auditoría de archivos originales conservados. `phase1-before.bundle` guarda HEAD antes de esta fase.
- Backend comprobado contra el manifiesto del respaldo: cero diferencias, incluyendo los cambios locales anteriores del usuario.
- No se ejecutaron migraciones, cambios de licencias, despliegues ni escrituras de prueba en producción.

## Archivos y decisiones

| Archivo en app/ | Cambio |
| --- | --- |
| lib/screens/shell.dart | Inicio como entrada; dock original Inicio/Vender/micrófono/Fiados/Caja filtrado por permisos; sin selección sectorial. Voz revalidada al abrir y durante la ruta. |
| lib/screens/inicio.dart | Encabezado morado y servicios originales; etiquetas Básico/Pro/Empresa; prioridad de accesos según experiencia, siempre filtrados por derechos; POS directo; errores del resumen con reintento; descarte de respuestas antiguas al cambiar acceso/empresa. |
| lib/screens/home.dart | Resumen sin cifra ficticia en carga/error; Copiloto solo autorizado; enlaces a comprobantes del día y reporte mensual; consulta de fecha usa el repositorio existente. |
| lib/screens/menu.dart | Categorías comerciales, búsqueda con candados, acceso a Mi plan y actualización al cambiar permisos. |
| lib/screens/catalog.dart | Registro compartido de destinos; guardia al abrir; descubrimiento de funciones bloqueadas; búsqueda por voz autorizada; conservación de destinos históricos. |
| lib/ui/feature_access.dart | Modal Actualiza tu plan y guardia reactiva. Un rol denegado no se convierte en oferta comercial. |
| lib/ux/commerce_navigation.dart | Exclusiones de exposición sectorial, etiquetas y orden; no concede derechos ni reescribe business_type. |
| lib/screens/assistant.dart | Conserva el Copiloto existente; entrada de menú y comprobación efectiva de licencia. |
| lib/screens/business_setup.dart | Presentación comercial única; conserva la configuración histórica; informa fallos de guardado. |
| lib/screens/settings_v2.dart | Experiencia comercial vinculada a Mi plan; retira exposición de selector sectorial y flujo de trabajos; mantiene herramientas compartidas. |

Se conserva el código de restaurante, agenda, trabajos, pacientes, talleres, educación y obras. Solamente se excluyen estos identificadores de la nueva navegación: `carta`, `platos`, `paquetes`, `historial` (pacientes), `placas`, `corte`, `morosidad`, `margen_obra`, `tipo`, `trabajos`, `agenda`. Los recordatorios comerciales, compras, cobros, facturación recurrente, importación, tienda y demás herramientas compartidas siguen en el catálogo.

Los archivos locales no registrados `facturavoz_inicio_bodega.dart` y `facturavoz_inicio_preview.dart` son un diseño independiente preexistente. No están conectados a main.dart ni sustituyen la pantalla real. Se respaldaron ambos; se retiraron únicamente un import y una constante sin uso del primero para dejar limpio el análisis. No se incluyen en el commit de navegación.

## Contratos de acceso

Inventario completo: [FACTURAVOZ_FASE1_DESTINOS.csv](FACTURAVOZ_FASE1_DESTINOS.csv), 62 entradas con archivo constructor, derecho y permiso.

- `Access.has` exige verificación en línea, origen Hub, licencia aplicable y concesión explícita. No se modificó Access ni su matriz de licencias.
- `voz` y `facturar` se comprueban separadamente; `copiloto` no se concede por llamarse Pro o Empresa.
- `fiados`/`caja` exigen además `collect`; `tienda` exige `settings`; compras exige `stock` y `finance`; reportes exige `reportes` y `finance`.
- Las etiquetas Bodega/Tienda, Minimarket e Hiperbodega solo ordenan la presentación. Los complementos explícitos del Hub se respetan incluso en Básico.
- La matriz histórica de precios/planes es una propuesta, no evidencia de la oferta vigente. El modal no promete un plan mínimo calculado con ella.
- Mis empresas es selección de organizaciones existentes, no un panel consolidado de sucursales. No se inventó un panel multitienda por el derecho `multisucursal`.
- Escanear comprobante conserva su contrato actual de `finance`; esta fase no inventa una clave premium ni altera su backend.

## Evidencia y límites

- `flutter analyze --no-pub`: sin incidencias.
- `flutter test --no-pub`: 258 pruebas aprobadas.
- 14 pruebas nuevas de navegación: seis combinaciones de plan/rol, complementos, voz separada, licencia bloqueada/restringida, modal, rol denegado, invalidación de una ruta abierta y búsqueda.
- Tres pruebas nuevas del encabezado: error sin cero ficticio y reintento a 320/768 px; ocultación de finanzas sin permiso. Supabase usa un cliente local sin red en estas pruebas; no son E2E cloud.
- Prueba histórica de etiquetas actualizada para no presentar la matriz local como catálogo comercial vigente.
- APK release compilada con configuración pública autorizada y firma original. APK debug compilada para el emulador.
- Android rechazó inicialmente instalar release sobre la app del emulador: firma distinta. Se respaldó el APK instalado y se verificó que la variante debug sí coincide; `adb install -r` debug terminó con Success, sin desinstalación ni borrado de datos.
- Logs, APKs y capturas se guardan en el directorio de respaldo externo, no en Git.

## Revisión real en Android Studio

Con sesión iniciada personalmente por el usuario, se observaron Inicio morado y POS con productos existentes. Se ejecutó el recorrido Menú → búsqueda → Tienda en línea con candado → Actualiza tu plan → Ver planes → Mi plan. El destino es la pantalla real de licencia, no una maqueta.

Mi plan muestra Básico, rol Propietario y derechos de facturación, clientes, cobros, voz, cotizaciones, reportes, caja y avisos de pago. Fiados y Copiloto no se muestran como habilitados en Inicio. No se alteraron los derechos para ajustarlos a una propuesta comercial.

Capturas auténticas en el respaldo externo: `phase1-inicio-basico.jpg`, `phase1-menu-real.jpg`, `phase1-upgrade-real.jpg`, `phase1-plan-real.jpg`. Las capturas no acreditan ventas, integraciones fiscales ni permisos de otros usuarios.

## Aceptación todavía pendiente

- Completar la revisión visual autenticada del resto de destinos. Inicio, Menú y el recorrido del candado a Mi plan ya se observaron con la sesión Básico.
- Capturas reales de las tres experiencias con licencias de prueba autorizadas. La matriz local de pruebas no acredita una licencia real del Hub.
- Verificación E2E de cambios de plan/rol y complementos con cuentas de prueba; sin modificar licencias reales.
- Verificación completa de enlaces secundarios dentro de pantallas heredadas; la guardia central protege las entradas nuevas, no certifica todas las acciones históricas.
- Inventario filtrado por stock bajo y consolidación multitienda no se inventaron: deben reutilizarse o completarse en sus fases autorizadas.
- No se realizaron ventas, cobros, emisiones fiscales, envíos Resend/WhatsApp ni cambios de configuración cloud para probar navegación.

Rollback: revertir exclusivamente el commit de esta fase restaura la navegación anterior conservando `def0a14`. No requiere restaurar base de datos ni tocar infraestructura.
