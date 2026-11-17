# Matriz de rutas únicas

> Generado por `tool/gen_matriz.py` desde `screens/catalog.dart` (registro único). Cada función tiene un id, un nombre que no se repite (prueba `navigation_contract_test`) y una sola pantalla.

## Nivel 1 · barra inferior (contratos en `nav/navigation_contract.dart`)

| Destino | Permiso | Función del plan |
|---|---|---|
| `home` | cualquier integrante | — |
| `sell` | sales.create | facturar |
| `quotes` | sales.create | cotizaciones |
| `fiados` | payments.record | fiados |
| `cash` | cash.close | caja |
| `collect` | payments.record | cobros |
| `business` | reports.profit | reportes |
| `jobs` | jobs.create | trabajos |
| `agenda` | jobs.create | agenda |
| `clients` | customers.manage | clientes |
| `tables` | sales.create | carta_qr |

## Nivel 2 · funciones

### Vender

| id | Nombre | Plan | Permiso de rol | Pantalla |
|---|---|---|---|---|
| `facturar` | Facturar por voz | facturar | sell | `NewInvoiceScreen` |
| `comprobantes` | Comprobantes | facturar | — | `RetailReceiptsScreen` |
| `pos` | Venta rápida (caja) | facturar | sell | `PosScreen` |
| `cotizaciones` | Cotizaciones y pedidos | cotizaciones | sell | `QuotesScreen` |
| `cuaderno` | Del cuaderno a la factura | cuaderno_ia | sell | `NotebookScreen` |
| `recurrentes` | Facturación recurrente | recurrentes | finance | `RecurringScreen` |
| `productos` | Productos e inventario | stock | — | `ProductsScreen` |
| `compras` | Compras y recepción | stock | products_edit | `RetailPurchasesScreen` |
| `tienda` | Tienda en línea | tienda | settings | `StoreScreen` |
| `carta` | Carta QR y comandas | carta_qr | — | `KitchenScreen` |
| `precios` | Precios y promociones | precios | products_edit | `PromosScreen` |
| `puntos` | Puntos y fidelización | fidelizacion | — | `LoyaltyScreen` |
| `reponer` | Reposición inteligente | stock | — | `ReorderScreen` |
| `platos` | Cuentas y costo por plato | carta_qr | — | `DishesScreen` |

### Control del dueño

| id | Nombre | Plan | Permiso de rol | Pantalla |
|---|---|---|---|---|
| `agente` | Tareas del Copiloto | copiloto_agente | settings | `AgentScreen` |
| `alertas` | Alertas del dueño | antifraude | team | `AlertsScreen` |
| `bitacora` | Bitácora | antifraude | team | `AuditScreen` |
| `pin` | PIN del dueño | — | team | `OwnerPinScreen` |
| `papelera` | Papelera | — | finance | `TrashScreen` |

### Clientes y trabajos

| id | Nombre | Plan | Permiso de rol | Pantalla |
|---|---|---|---|---|
| `clientes` | Clientes | clientes | clients | `ClientsHubScreen` |
| `clientes360` | Análisis de clientes | clientes | finance | `Clients360Screen` |
| `trabajos` | Trabajos | trabajos | jobs | `JobsScreen` |
| `agenda` | Agenda y citas | agenda | jobs | `AgendaScreen` |
| `encuestas` | Encuestas de satisfacción | encuestas | — | `SurveysScreen` |
| `paquetes` | Paquetes y sesiones | agenda | — | `PackagesScreen` |
| `historial` | Historial privado | agenda | clients | `PrivateHistoryScreen` |
| `recordatorios` | Les toca volver | agenda | — | `RemindersScreen` |
| `placas` | Buscar por placa | trabajos | — | `PlateScreen` |

### Cobrar y pagar

| id | Nombre | Plan | Permiso de rol | Pantalla |
|---|---|---|---|---|
| `me_deben` | Lo que me deben | cobros | collect | `OwedHubScreen` |
| `cobranza` | Cobranza | cobros | collect | `CollectionsScreen` |
| `fiados` | Libreta de fiados | fiados | collect | `FiadosScreen` |
| `caja` | Caja y cierre del día | caja | collect | `CashDayScreen` |
| `avisos` | Avisos de Yape y Plin | avisos_pago | collect | `PaymentNoticesScreen` |
| `banco` | Conciliación bancaria | conciliacion | finance | `BankReconScreen` |
| `gastos` | Gastos y pagos | — | finance | `ExpensesScreen` |
| `escanear` | Escanear comprobante | — | finance | `ScanScreen` |
| `corte` | Mensualidades y corte | recurrentes | collect | `CutoffScreen` |
| `credito` | Crédito por cliente | fiados | finance | `CreditScreen` |
| `morosidad` | Pensiones pendientes | recurrentes | collect | `MorosityScreen` |

### Mi negocio

| id | Nombre | Plan | Permiso de rol | Pantalla |
|---|---|---|---|---|
| `negocio_hub` | Mi negocio | reportes | finance | `BusinessHubScreen` |
| `negocio` | Ganancia real | reportes | finance | `ProfitScreen` |
| `impuestos` | ¿Cuánto me queda? | reportes | finance | `TaxesScreen` |
| `reportes` | Reportes | reportes | finance | `ReportsScreen` |
| `comisiones` | Ventas por vendedor | comisiones | — | `CommissionsScreen` |
| `importar` | Importar datos | — | import | `ImportScreen` |
| `margen_obra` | Margen por obra | trabajos | finance | `JobMarginScreen` |

### Ajustes

| id | Nombre | Plan | Permiso de rol | Pantalla |
|---|---|---|---|---|
| `ajustes` | Ajustes | — | — | `SettingsScreen` |
| `equipo` | Equipo y permisos | — | team | `TeamScreen` |
| `empresas` | Mis empresas | — | — | `OrgsScreen` |
| `datos` | Datos del negocio | — | settings | `ProfileFormScreen` |
| `sunat` | SUNAT | — | settings | `FiscalSetupScreen` |
| `marca` | Logo y comprobantes | — | settings | `BrandingScreen` |
| `impresora` | Impresora de tickets | — | — | `PrinterSettingsScreen` |
| `medios` | Medios de cobro | — | settings | `PaySettingsScreen` |
| `tipo` | Cambiar de rubro | — | settings | `RubroPickerScreen` |
| `presentacion` | Ver la presentación otra vez | — | settings | `BusinessSetupScreen` |
| `modulos` | Funciones a la vista | — | settings | `ModulesScreen` |
| `plan` | Mi plan | — | — | `PlanScreen` |
| `api` | API y webhooks | api_publica | team | `ApiAccessScreen` |
| `seguridad` | Seguridad | — | — | `SecurityScreen` |

