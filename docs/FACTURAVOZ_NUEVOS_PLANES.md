# FacturaVoz — nuevos planes, propuesta v1

Generado desde `app/tool/plans/proposal.dart`, única fuente de esta propuesta.
Regenerar desde app: `dart run tool/plans/document.dart`.
No reemplaza el contrato vigente del Hub ni la matriz histórica de compatibilidad.
No contiene precios. Ningún límite se ha publicado.

## Matriz comercial de desarrollo

- **Básico — Bodega / Tienda:** 1 usuarios, 1 sucursales. Incluye lo propuesto en planes inferiores.
- **Pro — Minimarket:** 5 usuarios, 1 sucursales. Incluye lo propuesto en planes inferiores.
- **Empresa — Hiperbodega:** 20 usuarios, 5 sucursales. Incluye lo propuesto en planes inferiores.

“Existente” significa evidencia en código, no certificación E2E ni disponibilidad automática. Las filas parciales requieren completar/validar su recorrido. Un destino listado en una fila pendiente es una dependencia existente, no la función completa.

| Función | Clave propuesta | Desde | Archivo / destino | Estado | Límite | Rol/permiso | Integración |
|---|---|---|---|---|---|---|---|
| POS y ventas | `facturar` | Básico | app/lib/screens/pos.dart — PosScreen | Existente; validar E2E | - | sell | PostgreSQL / RPC POS |
| Facturación SUNAT | `facturar` | Básico | app/lib/screens/fiscal_setup.dart — FiscalSetupScreen | Existente; requiere configuración autorizada | - | settings | SUNAT / backend fiscal |
| Facturación por voz | `voz` | Básico | app/lib/screens/new_invoice.dart — NewInvoiceScreen | Existente; también exige facturar | - | sell | Micrófono / transcripción backend |
| Productos y categorías | `facturar` | Básico | app/lib/screens/products.dart — ProductsScreen | Existente; edición exige products_edit | - | sell | PostgreSQL |
| Códigos de barras | `facturar` | Básico | app/lib/screens/pos.dart — PosScreen | Existente | - | sell | Cámara / lector |
| Unidad, paquete y caja | `presentaciones` | Básico | app/lib/screens/products.dart — ProductsScreen | PENDIENTE DE IMPLEMENTACIÓN: equivalencias paquete/caja | - | products_edit | Conversión de unidades / stock |
| Inventario esencial | `stock` | Básico | app/lib/screens/products.dart — ProductsScreen | Existente; inventario dentro de catálogo | - | products_edit | Ajuste atómico PostgreSQL |
| Clientes | `clientes` | Básico | app/lib/screens/clients_hub.dart — ClientsHubScreen | Existente | - | clients | PostgreSQL |
| Fiados y abonos | `fiados` | Básico | app/lib/screens/fiados.dart — FiadosScreen | Existente | - | collect | Libro de crédito / PostgreSQL |
| Caja y cierre diario | `caja` | Básico | app/lib/screens/cash_day.dart — CashDayScreen | Existente | - | collect | Caja / backend correo |
| Compras y proveedores esenciales | `stock` | Básico | app/lib/screens/receiving.dart — ReceivingScreen | Existente; verificar recorrido cloud | - | finance | RPC recepción / proveedores |
| Mermas | `stock` | Básico | app/lib/screens/products.dart — ProductsScreen | Existente como salida de stock | - | products_edit | Ajuste atómico de stock |
| Devoluciones | `devoluciones` | Básico | app/lib/screens/invoice_detail.dart — InvoiceDetailScreen | PENDIENTE DE IMPLEMENTACIÓN: recorrido integral; nota fiscal existente | - | finance | Nota de crédito / stock / cobro |
| Reportes esenciales | `reportes` | Básico | app/lib/screens/reports.dart — ReportsScreen | Existente | - | finance | PostgreSQL / CSV |
| Comprobantes e historial | `facturar` | Básico | app/lib/screens/home.dart — HomeScreen | Existente | - | sell | PostgreSQL / documentos fiscales |
| Correo de comprobantes | `facturar` | Básico | app/lib/screens/invoice_detail.dart — InvoiceDetailScreen | Existente; sin clave Resend en Flutter | - | sell | Resend servidor / dominio autorizado |
| Compartir por WhatsApp | `facturar` | Básico | app/lib/screens/invoice_detail.dart — InvoiceDetailScreen | Existente; no equivale a automatización | - | sell | Compartir / enlaces WhatsApp |
| Efectivo, Yape, Plin y tarjeta | `cobros` | Básico | app/lib/screens/pos.dart — PosScreen | Existente; registro manual no confirma proveedor | - | collect | Registro de pago / PostgreSQL |
| PIN y biometría | `@base` | Básico | app/lib/screens/security.dart — SecurityScreen | Existente | - | self | Seguridad local del dispositivo |
| Configuración | `@base` | Básico | app/lib/screens/settings.dart — SettingsScreen | Existente | - | settings | Perfil / configuración existente |
| Copiloto IA | `copiloto` | Pro | app/lib/screens/assistant.dart — CopilotScreen | Existente; concesión y permiso requeridos | - | finance | IA backend / Groq |
| Reposición inteligente | `reposicion_inteligente` | Pro | app/lib/screens/rubro_tools.dart — ReorderScreen | Existente; hoy comparte stock con Básico | - | finance | RPC stock / recomendación |
| Tienda online | `tienda` | Pro | app/lib/screens/store.dart — StoreScreen | Existente | - | settings | Tienda backend existente |
| Pedidos online | `tienda` | Pro | app/lib/screens/quotes.dart — QuotesScreen | Parcial; validar destino y gestión completa | - | sell | Tienda / pedidos backend |
| Fidelización | `fidelizacion` | Pro | app/lib/screens/promos.dart — LoyaltyScreen | Existente | - | clients | PostgreSQL puntos |
| Promociones avanzadas | `precios` | Pro | app/lib/screens/promos.dart — PromosScreen | Existente | - | products_edit | Motor de precios servidor |
| Reportes avanzados | `reportes_avanzados` | Pro | app/lib/screens/clients360.dart — Clients360Screen | Parcial; segmentación comparte clientes | - | finance | Agregaciones / segmentación |
| Análisis de rentabilidad | `rentabilidad` | Pro | app/lib/screens/profit.dart — ProfitScreen | Existente; hoy comparte reportes | - | finance | Costos / gastos / ventas reales |
| Lectura de factura por fotografía | `lectura_documentos` | Pro | app/lib/screens/scan.dart — ScanScreen | Existente; hoy depende del rol finance | - | finance | Cámara / IA backend |
| Importaciones inteligentes | `importacion_inteligente` | Pro | app/lib/screens/import_screen.dart — ImportScreen | Parcial; importación existe, inteligencia no acreditada | - | import | CSV/XLSX y validación existente |
| Automatizaciones de WhatsApp | `whatsapp_automatizaciones` | Pro | Sin pantalla operativa | PENDIENTE DE IMPLEMENTACIÓN: integración autorizada no acreditada | - | settings | Proveedor WhatsApp autorizado |
| Trabajadores | `@base` | Pro | app/lib/screens/team.dart — TeamScreen | Existente; controles servidor de max_users | max_users | team | Hub / miembros / invitaciones |
| Selector de sucursal | `multisucursal` | Empresa | Sin pantalla operativa | PENDIENTE DE IMPLEMENTACIÓN: Mis empresas no equivale a sucursales | max_branches | branches | Modelo sucursales / RLS |
| Inventario por sucursal | `inventario_sucursales` | Empresa | Sin pantalla operativa | PENDIENTE DE IMPLEMENTACIÓN | max_branches | branches | Stock por local / traslados / RLS |
| Ventas consolidadas | `consolidacion` | Empresa | Sin pantalla operativa | PENDIENTE DE IMPLEMENTACIÓN | max_branches | finance | Agregación autorizada entre locales |
| Gestión avanzada de cajas | `cajas_avanzadas` | Empresa | app/lib/screens/cash_day.dart — CashDayScreen | PENDIENTE DE IMPLEMENTACIÓN: existe caja diaria simple | max_branches | finance | Cajas por local / turnos |
| Permisos y auditoría avanzada | `antifraude` | Empresa | app/lib/screens/owner_control.dart — AuditScreen | Existente; permisos de rol básicos se conservan | max_users | team | Eventos / PIN dueño / equipo |
| Conciliación bancaria | `conciliacion` | Empresa | app/lib/screens/bank_recon.dart — BankReconScreen | Existente | - | finance | Importación de extractos |
| Reportes empresariales | `reportes_empresariales` | Empresa | Sin pantalla operativa | PENDIENTE DE IMPLEMENTACIÓN | max_branches | finance | Consolidación / reportes por local |
| Integraciones y API | `api_publica` | Empresa | app/lib/screens/api_access.dart — ApiAccessScreen | Existente; no crear credenciales en laboratorio | - | team | API y webhooks autorizados |
| Copiloto agente | `copiloto_agente` | Empresa | app/lib/screens/agent.dart — AgentScreen | Existente | - | settings | Tareas IA / aprobación servidor |
| Supervisión empresarial | `antifraude` | Empresa | app/lib/screens/owner_control.dart — AlertsScreen | Parcial; no acredita consolidación entre locales | - | team | Alertas / eventos |
`@base` es un marcador de la propuesta para capacidades no comercializadas como feature independiente; no se enviará al Hub. Seguridad personal permanece disponible, incluso con licencia restringida. `branches` es un permiso propuesto pendiente de contrato servidor; no habilita ningún permiso real.

## Claves nuevas y diferencias de autorización

Propuestas pendientes de aprobación y de implementación en todos los consumidores: `presentaciones`, `devoluciones`, `reposicion_inteligente`, `reportes_avanzados`, `rentabilidad`, `lectura_documentos`, `importacion_inteligente`, `whatsapp_automatizaciones`, `inventario_sucursales`, `consolidacion`, `cajas_avanzadas`, `reportes_empresariales`.

- `stock` actualmente habilita inventario y reposición. Separar reposición premium exige una clave nueva y comprobaciones de servidor, sin quitar el derecho existente a clientes actuales.
- `reportes` actualmente cubre reportes y rentabilidad. La división comercial no puede implementarse cambiando solo el menú.
- ScanScreen utiliza el permiso finance; ImportScreen utiliza import. Antes de cobrar estas capacidades por plan se necesitan guardias compatibles del backend y migración explícita.
- `multisucursal`, `max_users` y `max_branches` existen en el vocabulario histórico. OrgsScreen cambia organizaciones y no demuestra inventario ni consolidación por sucursal.
- PIN/biometría no depende de antifraude; auditoría avanzada sí. No bloquear la seguridad personal al reducir un plan.
- Roles propuestos del laboratorio: propietario y administrador tienen permisos de prueba; cajero solo sell, collect, clients y self. En producción manda my_access. No se modificaron roles reales.

## Diferencias frente al Hub observado

En la sesión autenticada revisada en Android Studio se observó Básico, Propietario, prueba activa y hasta 2 usuarios. Mostraba facturación, clientes, cobros, voz, cotizaciones, reportes, caja y avisos de pago. No mostraba fiados, stock, tienda o copiloto como incluidos.

La propuesta agrega inventario esencial, fiados, compras y proveedores a Básico; propone 1 usuario en vez de los 2 observados. Esa reducción NO debe aplicarse automáticamente a una licencia activa. Cotizaciones y avisos actualmente concedidos tampoco pueden perderse por no aparecer como objetivo explícito en el nuevo listado.

No se leyó una exportación completa de todas las licencias de Hub. Pro/Empresa vigentes y complementos de otros clientes siguen pendientes de inventario autorizado. El archivo histórico docs/facturavoz-planes.json es una propuesta anterior, no prueba del estado actual del Hub.

## Laboratorio seguro

Entrada exclusiva `app/tool/plans/main.dart`; no importada por lib/main.dart. Ejecutar desde app: `flutter run --debug -t tool/plans/main.dart`. No pasar dart-define ni credenciales.

No importa Access, Supabase, repositorios, clientes HTTP ni pantallas operativas. No modifica el singleton de permisos. El selector cambia solo PlanProposal/TrialRole locales. La entrada rechaza release y profile mediante kDebugMode; no depende de assert. El target normal de release no alcanza el laboratorio en su grafo de imports.

Inicio propuesto filtra funciones por plan y rol; no muestra candados de planes superiores. Menú permite descubrir capacidades superiores y abre Actualiza tu plan → Ver planes → comparación derivada de la misma matriz. Rol denegado muestra permiso requerido, nunca una compra. El estado pendiente tiene etiqueta explícita. Los límites alcanzados simulan incorporación de usuarios/locales, no suspenden las operaciones existentes.

Las fichas incluidas muestran el contrato y el destino real del código. Deliberadamente no ejecutan ese destino con permisos simulados: hacerlo contra los servicios actuales podría iniciar peticiones reales. La navegación operativa se mantiene en la app normal, con autorización real. Este laboratorio acredita decisiones comerciales/UI, no venta, emisión, correo ni integración cloud. No es el nuevo Inicio final; esa construcción corresponde a Fase 1A.

## Pruebas y evidencia

`app/test/plan_proposal_test.dart`: matriz progresiva; voz Básico; Copiloto bloqueado Básico; Empresa sin salto de roles; límites 1/5/20 y 1/1/5; estados pendientes; menú, modal y comparación; aislamiento de Access y cierre del grafo de imports del laboratorio; main productivo no alcanza el selector.

Resultados de ejecución y capturas auténticas: consultar `docs/FACTURAVOZ_PLANES_EVIDENCIA.md`. Las capturas de laboratorio estarán rotuladas como simulación; nunca acreditan concesiones del Hub.

## Migración futura de licencias activas (NO ejecutada)

1. Respaldar y exportar contratos/versiones, concesiones, límites, add-ons y uso actual; verificar restauración sin modificar Hub/AWS en esta fase.
2. Aprobar nombres, alcance, claves, precios y reglas de transición por separado. Versionar la oferta como propuesta v1, sin editar la matriz histórica en sitio.
3. Implementar nuevas claves y permisos en endpoints, RPC/RLS y clientes con compatibilidad hacia atrás. No derivar autorización del nombre del plan. Ensayar sobre restauración aislada.
4. Calcular un diff por licencia: derechos actuales, propuesta y excepciones. Conservar la unión de derechos contratados y add-ons durante la transición; una sustitución por clave conserva su equivalente.
5. Mantener límites contratados o excepciones explícitas: jamás bajar de 2 a 1 usuario ni de ilimitado a 20 automáticamente. No eliminar miembros, sucursales o datos para cumplir el nuevo límite. Aprobar límites al renovar según contrato.
6. Simular cambios con cohortes de prueba, comprobar claims, permisos, caché, eventos, webhooks y sincronización Hub. Cualquier eliminación o pérdida de derecho requiere revisión específica.
7. Solo con aprobación: aplicar gradualmente, con monitoreo y rollback a la versión previa más excepciones conservadas. Mantener IDs de organización, usuarios, paquetes, endpoints, secretos e históricos.

No se ha actualizado Solvex Hub, Supabase, backend productivo ni web. No publicar esta propuesta ni una APK release. Detenerse para revisión de la matriz antes de Fase 1A.
