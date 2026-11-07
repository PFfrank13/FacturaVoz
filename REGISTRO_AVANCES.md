# Registro de avances — Solvex Retail

## Reconstrucción operativa Flutter y Web · catálogo · 2026-11-07

Alcance de esta entrega parcial: catálogo Flutter y consulta de detalle en tablas Web. No representa la reconstrucción completa solicitada ni el cierre de la etapa 1. Se conservan las operaciones de edición/archivo, permisos y lógica cloud existentes.

- Flutter: `app/lib/screens/products.dart`. Nueva jerarquía visual, resumen del surtido, búsqueda identificada, filtros Activos/Archivados/Todos y Por reponer cuando existe permiso de stock, actualización manual y precios legibles con texto ampliado. Carga inyectable para probar el componente real con productos sintéticos; producción conserva Repo.listProducts. No se modificó persistencia ni se registraron productos reales.
- Web: `backend/src/components/erp/DataTable.tsx`, `backend/src/app/globals.css`. Acción Ver detalle en cada fila y panel contextual responsive, con cierre y campos limitados a la consulta autorizada. Búsqueda y ordenación conservadas; no añade permisos ni escrituras.
- Pruebas: `app/test/retail_catalog_test.dart` verifica búsqueda, filtros, ausencia del filtro de stock sin permiso y layout a 320/768 px con texto 1.4. Carga Inter y MaterialIcons para renders legibles. Capturas del widget Flutter ejecutado: `app/test/goldens/catalog-320.0.png` y `catalog-768.0.png`, inspeccionadas. Son renders de pruebas, no una sesión autenticada en teléfono ni Flutter Web.
- Verificación: Flutter analyze sin incidencias; suite completa **238 pruebas aprobadas** (`app/build/catalog-tests.log`). Web ESLint/TypeScript aprobados, **166 pruebas aprobadas** y build Next salida 0 (`backend/catalog-tests.log`, `backend/catalog-build.log`). `git diff --check` salida 0, con avisos LF/CRLF existentes.
- Laboratorio Web: `backend/tests/retail-preview/main.tsx` incorpora DataTable con fixtures. Servidor local arrancado y detenido. La inspección mediante navegador no pudo ejecutarse: herramienta devuelve «Local browser use is disabled in Work settings». No se certifica visualmente la tabla Web ni sus acciones con navegador.

Pendientes de la reconstrucción: ejecutar y capturar Inicio/POS/Caja/Inventario Flutter y Dashboard/POS/Compras/Inventario Web; reconstruir esas operaciones con el mismo sistema visual; verificar formularios y flujos completos. El catálogo conserva formularios heredados cuya reconstrucción sigue pendiente. No se eliminaron todavía rutas de otros rubros: primero se deben verificar sustitutos y dependencias compartidas. Continúan pendientes concurrencia, kardex auditable y jornada cloud de la etapa 1.

Sin cambios en producción, secretos, Hub o licencias reales; sin push ni despliegue.

## Decisión vigente: CLOUD-FIRST · 2026-11-07

La corrección expresa del usuario sustituye los requisitos offline-first del PDF y del registro histórico inferior. PostgreSQL cloud es la única fuente de verdad de ventas confirmadas. Localmente sólo se conservan carritos, borradores y preferencias; no hay un ERP empresarial independiente por dispositivo.

### Nuevas etapas y puerta 1

1. Tienda cloud confiable: catálogo, POS, cobros, caja, inventario auditable, usuarios/roles, transacciones PostgreSQL, recuperación, sincronización Flutter-Web y auditoría. Puerta: jornada comercial con operaciones reales y datos sintéticos en laboratorio aislado, sin pérdidas, duplicaciones ni diferencias de caja/inventario. **No requiere siete días offline.**
2. Operación completa: compras, proveedores, facturación, clientes, fiados, gastos, pagos y precios.
3. Piloto automático con decisiones y resultados verificables.
4. Minimarket profesional: cajas concurrentes, turnos, promociones e inventario avanzado.
5. Futuro: supermercados, cadenas, distribución y omnicanalidad, sin adelantar estas etapas.

### Fase de recuperación de consultas cloud

- `backend/src/components/erp/RefreshAccess.tsx`: eventos de productos, facturas, pagos, caja, gastos, permisos y configuración invalidan consultas autenticadas; canales por tabla/empresa, recarga al reconectar/activar ventana y respaldo de consulta cada 30 segundos visible. Indicador de red desconectada; estar online no se presenta como verificación de disponibilidad cloud.
- `backend/src/lib/retail/cloud-refresh.ts`: agrupa eventos en ventanas acotadas y cancela callbacks al abandonar empresa/pantalla. No convierte payloads Realtime en registros contables ni confirma ventas.
- `app/lib/services/live.dart`: reconsulta al suscribirse, reactivar la app y periódicamente en primer plano; agrupa avisos mientras una consulta está en curso. Se aplica a pantallas que usan LiveReload; no implica cobertura automática de todas las pantallas.
- `app/lib/services/repo.dart`: el checkout Flutter consulta primero el UUID bajo empresa/usuario. Recupera la factura confirmada existente; un fallo al consultar no cae en un nuevo envío. Si no hay resultado visible, usa el mismo UUID en el RPC atómico, que serializa concurrentes. No genera un UUID nuevo para reintentar una operación incierta.
- `backend/tests/cloud-refresh.test.ts` y `app/test/cloud_reload_test.dart`: eventos agrupados, pausa/reanudación, recuperación tras error y cancelación de consultas antiguas.

Validación final: web ESLint y TypeScript aprobados; 166 pruebas en 18 archivos aprobadas; build Next salida 0 (`backend/cloud-build.log`). Flutter analyze sin incidencias y suite completa de **236 pruebas aprobadas** (`app/build/cloud-tests.log`), incluidas 2 nuevas de ciclo de vida. `git diff --check` sin errores.

### Pendiente de integración; etapa 1 NO certificada

No se ejecutó una jornada comercial completa ni se probó aún Flutter-Web con dos sesiones contra Supabase aislado. No se modificaron publicaciones Realtime ni RLS; los canales requieren publicación y permisos del laboratorio. El respaldo periódico funciona sin eventos, pero no sustituye su validación integrada.

Docker está disponible. El contenedor histórico `facturavoz-erp-local-sql-20261104` no arrancó porque su comando intenta ejecutar initdb sobre un directorio ya inicializado. No se borró ese directorio ni se tocó el contenedor de restauración existente.

Se creó `solvex-cloud-lab-20261107`, PostgreSQL 17.11, red `none`, cero montajes y sin puertos publicados. `backend/scripts/test-cloud-schema.mjs` verifica ese aislamiento, carga **schema.sql y todas las migraciones locales** dentro de una transacción y ejecuta `backend/supabase/tests/test_cloud_checkout.sql`, terminando con rollback de todos los fixtures. Se conserva el contenedor local en ejecución para repetir la prueba con `node scripts/test-cloud-schema.mjs` desde backend. No contiene datos de clientes ni secretos reales.

Resultado SQL salida 0 (`backend/cloud-schema-test.log`): venta real por `fast_checkout_atomic` con rol authenticated; UUID repetido devuelve la misma factura; un único pago de S/23.60; stock 10→8 una sola vez; resumen de caja S/23.60; venta de 100 unidades rechazada sin factura, solicitud ni cambio de stock residuales; usuario de empresa B no lee producto ni solicitud de A. Se usaron el esquema y las funciones reales del repositorio, con un shim local mínimo de Auth/Storage y licencias sintéticas. No se probó la firma de JWT, transporte HTTP, Auth real, Realtime ni concurrencia entre sesiones. Esta integración parcial no certifica todavía una jornada completa.

Continúan pendientes: validación de precios dentro de la transacción (la comprobación web previa no elimina carreras), conciliación caja/kardex, autorización RPC y RLS integradas, estados persistidos de pago manual/proveedor/SUNAT, refresco seguro del POS Flutter con un ticket abierto y pruebas de integración con pérdida de respuesta. No construir persistencia offline empresarial para resolverlos.

Restricciones conservadas: sin producción, Hub, AWS, Vercel, licencias reales, secretos, push ni despliegues. Sin datos reales de clientes.

---

El resto es un registro histórico: sus requisitos offline quedan sustituidos por la decisión anterior.

## 2026-11-07 · Reanudación local

Se preservó el trabajo sin commit sobre main (base 704632d), sin reiniciar el proyecto. Este registro continúa las auditorías existentes; no las sustituye. La instrucción más reciente prioriza retail y supera el alcance anterior de nueve ERP. No se eliminaron módulos históricos.

### Fase visual y navegación: implementada parcialmente

Archivos: `app/lib/ui/{retail_identity,theme,widgets,business_header}.dart`, `app/lib/screens/{login,onboarding,shell,menu,inicio}.dart`, `app/lib/main.dart`, metadatos Android/iOS/web; `backend/src/components/retail/Brand.tsx`, `backend/src/app/layout.tsx`, `backend/src/app/globals.css`, `backend/src/app/login/page.tsx`, layouts/páginas ERP y fuentes locales.

Resultado: símbolo propio, paleta retail, acceso/onboarding reconstruidos y navegación orientada a venta/caja/herramientas. No es una certificación de todas las pantallas. Plan compatible y límites: `docs/SOLVEX_RETAIL_IDENTIDAD.md`.

### Fase POS y recuperación: implementada parcialmente

Archivos: `app/lib/screens/{pos,products,catalog}.dart`, `app/lib/ui/{pos_checkout_bar,checkout_sheet}.dart`, `app/lib/logic/retail_money.dart`; `backend/src/components/erp/PointOfSale.tsx`, `backend/src/app/erp/checkout.ts`, ruta ERP de módulo, `backend/src/lib/retail/{money,ticket-store}.ts` y controles de acceso existentes.

Resultado: cobro visible y vuelto, límites por rol/licencia, pago digital identificado como manual, cálculo web en centavos, borrador web versionado por usuario/organización y recuperación del UUID de una operación incierta. La acción verifica precios, moneda e impuesto antes de crear una venta y busca una operación previa al recuperar. El ticket Flutter todavía no tiene recuperación durable.

Correcciones al reanudar: congelar precios/condiciones desde la primera edición y también después de aceptarlos explícitamente; evitar que el replay de efectos de React StrictMode produzca un falso bloqueo entre pestañas.

### Evidencia observada

- Flutter: `flutter analyze --no-pub`, sin incidencias. Suite completa: **234 pruebas aprobadas**, log `app/build/retail-tests.log`. Incluye login/onboarding a 320 y 768 px con texto 1.6, checkout y layout POS.
- Flutter Web: `flutter build web --no-pub`, salida 0 y `Built build/web`; log `app/build/retail-web-build.log`. Avisos de Wasm en dependencias y CupertinoIcons; no se certifica Wasm, APK nuevo ni iOS.
- Web: ESLint aprobado; Vitest **163 pruebas en 17 archivos** aprobadas; log `backend/retail-tests.log`. Build Next repetido tras las correcciones finales: **salida 0**, incluidas comprobaciones de tipos y generación de rutas; log `backend/retail-build.log`.
- `git diff --check`: salida 0; únicamente aviso de normalización futura LF/CRLF en el documento histórico de verificación.
- Navegador local, componente real con productos sintéticos y checkout sustituido por fallo simulado: recuperación de dos unidades tras recarga; bloqueo de segunda pestaña; vuelto S/4.10 sobre total S/5.90 y recibido S/10; recuperación de cobro incierto sin pedir dinero otra vez. Capturas `app/build/retail-evidence/pos-recovery-{desktop,mobile}.png`. Sin desbordamiento horizontal observado a 375 px.
- Prueba adicional con StrictMode: montaje correcto, precio 2.50→3.50 conserva ticket 2.95 y bloquea cobro; aceptar actualiza a 4.13; segunda subida a 4.50 conserva 4.13 y vuelve a exigir revisión. Una segunda pestaña queda bloqueada y puede recuperar el ticket al cerrar la primera y recargar. Captura `app/build/retail-evidence/pos-price-review.png`.
- Laboratorio reproducible: desde backend, `node scripts/preview-retail.mjs`; archivos `backend/tests/retail-preview/*`. No es una ruta productiva ni evidencia de cobro real.

### Pendientes y puerta de calidad

**La etapa 1 no está terminada.** Faltan base local transaccional, ledger/kardex inmutable validado, sincronización y conflictos con versiones servidor, cierre ciego y reconciliación integral, persistencia separada de estados de pago, jornada comercial y siete días offline sin pérdida/duplicación. Falta validar Auth/RLS y RPC contra backend aislado completo; mocks y navegador no sustituyen esa evidencia.

También faltan migración monetaria completa Flutter/RPC, revisión visual de inventario/compras/reportes y dispositivos reales. No se amplían etapas superiores ni centros de distribución mientras esta puerta siga pendiente. Decisiones detalladas: `DECISIONES_PENDIENTES.md`.

Sin cambios a producción, Hub, licencias reales, secretos o identificadores externos; sin push, despliegue ni comandos destructivos. La migración SQL histórica sigue sin aplicarse y no se certifica aquí.

## Fase compras, PostgreSQL y preparación de publicación — 2026-11-07

La autorización posterior permite rama GitHub y Vercel Preview. La instrucción
más reciente exige reutilizar recursos sin tercer proyecto ni pago y conservar
Hub. Las restricciones históricas anteriores se mantienen como registro, no
como prohibición vigente de push. Cloud-first sustituye la puerta de siete días
offline: las operaciones confirmadas pertenecen a PostgreSQL.

Implementado: recepción multítem proveedor/documento, stock/costo atómico,
reintento con UUID estable, ledger y separación por organización; Flutter y web.
Archivos: app/lib/screens/receiving.dart, services/receiving_repo.dart,
backend/src/app/erp/receiving.ts, components/erp/Receiving.tsx,
backend/supabase/local/retail_receiving.sql y sus pruebas. SQL sigue siendo
propuesta local, no migración remota aplicada.

Evidencia previa conservada: Flutter analyze limpio y 240 pruebas; cuatro goldens
de recepción; build Next aprobado. Reejecutado ahora: Vitest 172 pruebas/19
archivos aprobados. Laboratorio SQL: recepción concurrente idempotente, ventas
concurrentes con stock insuficiente y conciliación 200.60 aprobados. No equivalen
a una jornada completa con Auth/Realtime alojados. Git diff --check aprobado.

Nuevos archivos de esta continuación: tools/verify_private_backup.py,
tools/inspect_private_dependencies.py, docs/SOLVEX_REUTILIZACION_INFRAESTRUCTURA.md.
Restauración real de export SQL aprobada con FK verificadas y conteos iguales;
Storage descargado y configuración exportada. Vercel oculta 20 secretos en su
export: respaldo integral y eliminación siguen sin certificarse.

Vercel: proyecto solvex-retail-control creado y configurado con Next.js/backend,
Node 24 y npm ci. Aún sin Preview funcional. No se cambió producción, Hub, AWS,
Caddy, panel ni solvexsoftware.dev. La etapa 1 permanece abierta: adaptar esquema
real restaurado, preservar contratos, validar servicios completos y jornada POS.
