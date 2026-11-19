// Única propuesta comercial v1. No se importa desde lib/main.dart.
// No modifica Access, no concede credenciales ni ejecuta operaciones.
enum TrialPlan { basico, pro, empresa }
enum TrialRole { propietario, cajero, administrador }
enum TrialDecision { allowed, upgrade, roleDenied, pending, limitReached }

class PlanProposal {
  const PlanProposal(this.label, this.experience, this.users, this.branches);
  final String label, experience;
  final int users, branches;
}
const proposals = {
  TrialPlan.basico: PlanProposal('Básico', 'Bodega / Tienda', 1, 1),
  TrialPlan.pro: PlanProposal('Pro', 'Minimarket', 5, 1),
  TrialPlan.empresa: PlanProposal('Empresa', 'Hiperbodega', 20, 5),
};

class ProposedFeature {
  const ProposedFeature(this.id, this.name, this.key, this.minimum, this.file,
    this.destination, this.permission, this.integration, this.status, this.limit);
  final String id, name, key, file, destination, permission, integration, status, limit;
  final TrialPlan minimum;
  bool get pending => status.startsWith('PENDIENTE');
}
const proposedFeatures = <ProposedFeature>[
  ProposedFeature("pos", "POS y ventas", "facturar", TrialPlan.basico, "pos.dart", "PosScreen", "sell", "PostgreSQL / RPC POS", "Existente; validar E2E", "-"),
  ProposedFeature("sunat", "Facturación SUNAT", "facturar", TrialPlan.basico, "fiscal_setup.dart", "FiscalSetupScreen", "settings", "SUNAT / backend fiscal", "Existente; requiere configuración autorizada", "-"),
  ProposedFeature("voz", "Facturación por voz", "voz", TrialPlan.basico, "new_invoice.dart", "NewInvoiceScreen", "sell", "Micrófono / transcripción backend", "Existente; también exige facturar", "-"),
  ProposedFeature("productos", "Productos y categorías", "facturar", TrialPlan.basico, "products.dart", "ProductsScreen", "sell", "PostgreSQL", "Existente; edición exige products_edit", "-"),
  ProposedFeature("barras", "Códigos de barras", "facturar", TrialPlan.basico, "pos.dart", "PosScreen", "sell", "Cámara / lector", "Existente", "-"),
  ProposedFeature("presentaciones", "Unidad, paquete y caja", "presentaciones", TrialPlan.basico, "products.dart", "ProductsScreen", "products_edit", "Conversión de unidades / stock", "PENDIENTE DE IMPLEMENTACIÓN: equivalencias paquete/caja", "-"),
  ProposedFeature("stock", "Inventario esencial", "stock", TrialPlan.basico, "products.dart", "ProductsScreen", "products_edit", "Ajuste atómico PostgreSQL", "Existente; inventario dentro de catálogo", "-"),
  ProposedFeature("clientes", "Clientes", "clientes", TrialPlan.basico, "clients_hub.dart", "ClientsHubScreen", "clients", "PostgreSQL", "Existente", "-"),
  ProposedFeature("fiados", "Fiados y abonos", "fiados", TrialPlan.basico, "fiados.dart", "FiadosScreen", "collect", "Libro de crédito / PostgreSQL", "Existente", "-"),
  ProposedFeature("caja", "Caja y cierre diario", "caja", TrialPlan.basico, "cash_day.dart", "CashDayScreen", "collect", "Caja / backend correo", "Existente", "-"),
  ProposedFeature("compras", "Compras y proveedores esenciales", "stock", TrialPlan.basico, "receiving.dart", "ReceivingScreen", "finance", "RPC recepción / proveedores", "Existente; verificar recorrido cloud", "-"),
  ProposedFeature("mermas", "Mermas", "stock", TrialPlan.basico, "products.dart", "ProductsScreen", "products_edit", "Ajuste atómico de stock", "Existente como salida de stock", "-"),
  ProposedFeature("devoluciones", "Devoluciones", "devoluciones", TrialPlan.basico, "invoice_detail.dart", "InvoiceDetailScreen", "finance", "Nota de crédito / stock / cobro", "PENDIENTE DE IMPLEMENTACIÓN: recorrido integral; nota fiscal existente", "-"),
  ProposedFeature("reportes", "Reportes esenciales", "reportes", TrialPlan.basico, "reports.dart", "ReportsScreen", "finance", "PostgreSQL / CSV", "Existente", "-"),
  ProposedFeature("historial", "Comprobantes e historial", "facturar", TrialPlan.basico, "home.dart", "HomeScreen", "sell", "PostgreSQL / documentos fiscales", "Existente", "-"),
  ProposedFeature("correo", "Correo de comprobantes", "facturar", TrialPlan.basico, "invoice_detail.dart", "InvoiceDetailScreen", "sell", "Resend servidor / dominio autorizado", "Existente; sin clave Resend en Flutter", "-"),
  ProposedFeature("whatsapp", "Compartir por WhatsApp", "facturar", TrialPlan.basico, "invoice_detail.dart", "InvoiceDetailScreen", "sell", "Compartir / enlaces WhatsApp", "Existente; no equivale a automatización", "-"),
  ProposedFeature("cobros", "Efectivo, Yape, Plin y tarjeta", "cobros", TrialPlan.basico, "pos.dart", "PosScreen", "collect", "Registro de pago / PostgreSQL", "Existente; registro manual no confirma proveedor", "-"),
  ProposedFeature("seguridad", "PIN y biometría", "@base", TrialPlan.basico, "security.dart", "SecurityScreen", "self", "Seguridad local del dispositivo", "Existente", "-"),
  ProposedFeature("ajustes", "Configuración", "@base", TrialPlan.basico, "settings.dart", "SettingsScreen", "settings", "Perfil / configuración existente", "Existente", "-"),
  ProposedFeature("copiloto", "Copiloto IA", "copiloto", TrialPlan.pro, "assistant.dart", "CopilotScreen", "finance", "IA backend / Groq", "Existente; concesión y permiso requeridos", "-"),
  ProposedFeature("reponer", "Reposición inteligente", "reposicion_inteligente", TrialPlan.pro, "rubro_tools.dart", "ReorderScreen", "finance", "RPC stock / recomendación", "Existente; hoy comparte stock con Básico", "-"),
  ProposedFeature("tienda", "Tienda online", "tienda", TrialPlan.pro, "store.dart", "StoreScreen", "settings", "Tienda backend existente", "Existente", "-"),
  ProposedFeature("pedidos", "Pedidos online", "tienda", TrialPlan.pro, "quotes.dart", "QuotesScreen", "sell", "Tienda / pedidos backend", "Parcial; validar destino y gestión completa", "-"),
  ProposedFeature("fidelizacion", "Fidelización", "fidelizacion", TrialPlan.pro, "promos.dart", "LoyaltyScreen", "clients", "PostgreSQL puntos", "Existente", "-"),
  ProposedFeature("promociones", "Promociones avanzadas", "precios", TrialPlan.pro, "promos.dart", "PromosScreen", "products_edit", "Motor de precios servidor", "Existente", "-"),
  ProposedFeature("reportes_avanzados", "Reportes avanzados", "reportes_avanzados", TrialPlan.pro, "clients360.dart", "Clients360Screen", "finance", "Agregaciones / segmentación", "Parcial; segmentación comparte clientes", "-"),
  ProposedFeature("rentabilidad", "Análisis de rentabilidad", "rentabilidad", TrialPlan.pro, "profit.dart", "ProfitScreen", "finance", "Costos / gastos / ventas reales", "Existente; hoy comparte reportes", "-"),
  ProposedFeature("foto", "Lectura de factura por fotografía", "lectura_documentos", TrialPlan.pro, "scan.dart", "ScanScreen", "finance", "Cámara / IA backend", "Existente; hoy depende del rol finance", "-"),
  ProposedFeature("importar", "Importaciones inteligentes", "importacion_inteligente", TrialPlan.pro, "import_screen.dart", "ImportScreen", "import", "CSV/XLSX y validación existente", "Parcial; importación existe, inteligencia no acreditada", "-"),
  ProposedFeature("whatsapp_auto", "Automatizaciones de WhatsApp", "whatsapp_automatizaciones", TrialPlan.pro, "-", "-", "settings", "Proveedor WhatsApp autorizado", "PENDIENTE DE IMPLEMENTACIÓN: integración autorizada no acreditada", "-"),
  ProposedFeature("equipo", "Trabajadores", "@base", TrialPlan.pro, "team.dart", "TeamScreen", "team", "Hub / miembros / invitaciones", "Existente; controles servidor de max_users", "max_users"),
  ProposedFeature("multisucursal", "Selector de sucursal", "multisucursal", TrialPlan.empresa, "-", "-", "branches", "Modelo sucursales / RLS", "PENDIENTE DE IMPLEMENTACIÓN: Mis empresas no equivale a sucursales", "max_branches"),
  ProposedFeature("stock_local", "Inventario por sucursal", "inventario_sucursales", TrialPlan.empresa, "-", "-", "branches", "Stock por local / traslados / RLS", "PENDIENTE DE IMPLEMENTACIÓN", "max_branches"),
  ProposedFeature("consolidacion", "Ventas consolidadas", "consolidacion", TrialPlan.empresa, "-", "-", "finance", "Agregación autorizada entre locales", "PENDIENTE DE IMPLEMENTACIÓN", "max_branches"),
  ProposedFeature("cajas", "Gestión avanzada de cajas", "cajas_avanzadas", TrialPlan.empresa, "cash_day.dart", "CashDayScreen", "finance", "Cajas por local / turnos", "PENDIENTE DE IMPLEMENTACIÓN: existe caja diaria simple", "max_branches"),
  ProposedFeature("auditoria", "Permisos y auditoría avanzada", "antifraude", TrialPlan.empresa, "owner_control.dart", "AuditScreen", "team", "Eventos / PIN dueño / equipo", "Existente; permisos de rol básicos se conservan", "max_users"),
  ProposedFeature("conciliacion", "Conciliación bancaria", "conciliacion", TrialPlan.empresa, "bank_recon.dart", "BankReconScreen", "finance", "Importación de extractos", "Existente", "-"),
  ProposedFeature("reportes_empresa", "Reportes empresariales", "reportes_empresariales", TrialPlan.empresa, "-", "-", "finance", "Consolidación / reportes por local", "PENDIENTE DE IMPLEMENTACIÓN", "max_branches"),
  ProposedFeature("api", "Integraciones y API", "api_publica", TrialPlan.empresa, "api_access.dart", "ApiAccessScreen", "team", "API y webhooks autorizados", "Existente; no crear credenciales en laboratorio", "-"),
  ProposedFeature("agente", "Copiloto agente", "copiloto_agente", TrialPlan.empresa, "agent.dart", "AgentScreen", "settings", "Tareas IA / aprobación servidor", "Existente", "-"),
  ProposedFeature("supervision", "Supervisión empresarial", "antifraude", TrialPlan.empresa, "owner_control.dart", "AlertsScreen", "team", "Alertas / eventos", "Parcial; no acredita consolidación entre locales", "-"),
 ];

bool trialRoleAllows(TrialRole role, String permission) =>
  role != TrialRole.cajero || const {'sell', 'collect', 'clients', 'self'}.contains(permission);

TrialDecision trialDecision(ProposedFeature feature, TrialPlan plan, TrialRole role,
    {int users = 0, int branches = 0}) {
  if (!trialRoleAllows(role, feature.permission)) return TrialDecision.roleDenied;
  if (plan.index < feature.minimum.index) return TrialDecision.upgrade;
  final p = proposals[plan]!;
  if ((feature.limit == 'max_users' && users >= p.users) ||
      (feature.limit == 'max_branches' && branches >= p.branches)) {
    return TrialDecision.limitReached;
  }
  return feature.pending ? TrialDecision.pending : TrialDecision.allowed;
}

// Home is a filtered presentation of the same matrix, never a grant source.
List<ProposedFeature> trialHome(TrialPlan plan, TrialRole role) => proposedFeatures
  .where((f) => plan.index >= f.minimum.index && trialRoleAllows(role, f.permission))
  .toList();
