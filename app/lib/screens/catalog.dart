// "Todas las funciones" + buscador universal (texto y voz) + menú del avatar (Fase 7).
// Un solo registro de funciones: el menú, el buscador y los atajos leen de aquí. Cada función declara:
//   módulo (si se ve a primera vista según el tipo de negocio), función del plan (licencia) y permiso del rol.
// Nada se borra: lo que el plan o el rol no permiten simplemente no aparece (y la base de datos lo bloquea igual).
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../app_state.dart';
import '../logic/search_score.dart';
import '../models.dart';
import '../models_v2.dart';
import '../rubros.dart';
import '../services/repo.dart';
import '../services/v2_api.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/retail_layout.dart';
import '../ui/widgets.dart';
import 'agent.dart';
import 'api_access.dart';
import 'bank_recon.dart';
import 'branding.dart';
import 'business_setup.dart';
import 'cash_day.dart';
import 'client_profile.dart';
import 'clients360.dart';
import 'clients_hub.dart';
import 'collections.dart';
import 'expenses.dart';
import 'fiados.dart';
import 'fiscal_setup.dart';
import 'hubs_v3.dart';
import 'import_screen.dart';
import 'invoice_detail.dart';
import 'jobs.dart';
import 'kitchen.dart';
import 'license_gate.dart';
import 'menu.dart';
import 'new_invoice.dart';
import 'notebook.dart';
import 'notices.dart';
import 'stock_lots.dart';
import 'orgs.dart';
import 'owner_control.dart';
import 'pay_settings.dart';
import 'pos.dart';
import 'products.dart';
import 'retail_purchases.dart';
import 'retail_receipts.dart';
import 'profile_form.dart';
import 'profit.dart';
import 'promos.dart';
import 'quotes.dart';
import 'recurring.dart';
import 'reports.dart';
import 'rubro_picker.dart';
import 'rubro_tools.dart';
import 'scan.dart';
import 'security.dart';
import 'settings.dart';
import 'settings_v2.dart';
import 'store.dart';
import 'surveys.dart';
import 'taxes.dart';
import 'team.dart';
import 'trash.dart';

class FeatureEntry {
  const FeatureEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.group,
    required this.builder,
    this.module,
    this.feature,
    this.perm,
    this.keywords = const [],
    this.mobileOnly = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String group;
  final WidgetBuilder builder;

  /// Módulo de la plantilla (para "se ve a primera vista").
  final String? module;

  /// Función del plan (licencia de Solvex Hub).
  final String? feature;

  /// Permiso del rol (my_access.can).
  final String? perm;
  final List<String> keywords;
  final bool mobileOnly;

  bool get allowed => roleOk && planOk;

  /// ¿El rol lo permite (y la plataforma)? Si no, no se muestra.
  bool get roleOk => rubroShows(rubroFor(Access.instance.rubro), id) &&
      (perm == null || Access.instance.can(perm!)) &&
      // Receiving and supplier-payment flow currently requires administrator access.
      // Do not advertise a shortcut that the underlying screen will reject.
      (id != 'compras' || Access.instance.isAdmin) &&
      !(mobileOnly && kIsWeb);

  /// ¿Hub lo incluye? Los menús filtran por allowed y omiten lo no contratado.
  bool get planOk => feature == null || Access.instance.has(feature!);
}

const groupOrder = ['Vender', 'Clientes y trabajos', 'Cobrar y pagar', 'Mi negocio', 'Control del dueño', 'Ajustes'];

/// Color propio por función (no por grupo): estable, siempre el mismo para la misma función. Paleta: Brand.fnPalette.
Color featureColor(String id) {
  var h = 0;
  for (final u in id.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return Brand.fnPalette[h % Brand.fnPalette.length];
}

const groupColors = <String, Color>{
  'Vender': Color(0xFFFF7E9A),
  'Clientes y trabajos': Color(0xFFD94A8E),
  'Cobrar y pagar': Color(0xFF23956F),
  'Mi negocio': Color(0xFF6A62E2),
  'Control del dueño': Color(0xFFC57A12),
  'Ajustes': Color(0xFF5B6B8C),
};

/// Registro único de funciones (el orden importa: es el orden en pantalla).
List<FeatureEntry> featureCatalog() => [
      // ───── Vender ─────
      FeatureEntry(id: 'facturar', title: 'Facturar por voz', subtitle: 'Boleta o factura dictada o escrita', icon: Icons.mic_rounded, group: 'Vender', feature: 'facturar', perm: 'sell', keywords: const ['boleta', 'factura', 'vender', 'comprobante', 'sunat'], builder: (_) => const NewInvoiceScreen()),
      FeatureEntry(id: 'comprobantes', feature: 'facturar', title: 'Comprobantes', subtitle: 'Emitir, consultar, descargar y configurar SUNAT', icon: Icons.receipt_long_rounded, group: 'Vender', keywords: const ['boletas', 'facturas', 'lista', 'historial', 'anular', 'sunat'], builder: (_) => const RetailReceiptsScreen()),
      FeatureEntry(id: 'pos', title: 'Venta rápida (caja)', subtitle: 'Toca productos o escanea su código de barras', icon: Icons.point_of_sale_rounded, group: 'Vender', module: 'pos', feature: 'facturar', perm: 'sell', keywords: const ['caja', 'pos', 'codigo de barras', 'carrito'], builder: (_) => const PosScreen()),
      FeatureEntry(id: 'cotizaciones', title: 'Cotizaciones y pedidos', subtitle: 'Cotiza, comparte y convierte en factura', icon: Icons.request_quote_rounded, group: 'Vender', module: 'cotizaciones', feature: 'cotizaciones', perm: 'sell', keywords: const ['presupuesto', 'proforma', 'pedido web'], builder: (_) => const QuotesScreen()),
      FeatureEntry(id: 'agente', title: 'Tareas del Copiloto', subtitle: 'Encárgale una tarea: la prepara y tú la apruebas', icon: Icons.smart_toy_rounded, group: 'Control del dueño', feature: 'copiloto_agente', perm: 'settings', keywords: const ['copiloto', 'agente', 'tarea', 'delegar', 'cobrar', 'automatico'], builder: (_) => const AgentScreen()),
      FeatureEntry(id: 'cuaderno', title: 'Del cuaderno a la factura', subtitle: 'Foto de tu cuaderno, nota o WhatsApp → venta', icon: Icons.menu_book_rounded, group: 'Vender', module: 'cuaderno_ia', feature: 'cuaderno_ia', perm: 'sell', keywords: const ['foto', 'nota', 'ia', 'cuaderno'], builder: (_) => const NotebookScreen()),
      FeatureEntry(id: 'recurrentes', title: 'Facturación recurrente', subtitle: 'Mensualidades que se facturan solas', icon: Icons.event_repeat_rounded, group: 'Vender', module: 'recurrentes', feature: 'recurrentes', perm: 'finance', keywords: const ['mensual', 'alquiler', 'suscripcion'], builder: (_) => const RecurringScreen()),
      FeatureEntry(id: 'productos', feature: 'stock', title: 'Productos e inventario', subtitle: 'Precios, stock, código de barras y fotos', icon: Icons.inventory_2_rounded, group: 'Vender', module: 'stock', keywords: const ['stock', 'catalogo', 'precio', 'inventario'], builder: (_) => const ProductsScreen()),
      FeatureEntry(id: 'vencimientos', title: 'Vencimientos y mermas', subtitle: 'Lo que vence pronto, lo vencido y las mermas con motivo', icon: Icons.event_busy_rounded, group: 'Vender', module: 'stock', feature: 'stock', keywords: const ['vencimiento', 'vence', 'lote', 'merma', 'perdida', 'robo', 'caducado'], builder: (_) => const StockLotsScreen()),
      FeatureEntry(id: 'compras', title: 'Compras y recepción', subtitle: 'Proveedor → productos → inventario → gasto y caja', icon: Icons.local_shipping_outlined, group: 'Vender', module: 'stock', feature: 'stock', perm: 'products_edit', keywords: const ['compras', 'proveedor', 'recibir', 'reponer', 'inventario', 'costo'], builder: (_) => const RetailPurchasesScreen()),
      FeatureEntry(id: 'tienda', title: 'Tienda en línea', subtitle: 'Tu catálogo con carrito y pedidos por WhatsApp', icon: Icons.storefront_rounded, group: 'Vender', module: 'tienda', feature: 'tienda', perm: 'settings', keywords: const ['web', 'catalogo', 'whatsapp', 'pedidos'], builder: (_) => const StoreScreen()),
      FeatureEntry(id: 'carta', title: 'Carta QR y comandas', subtitle: 'Pedidos por mesa directo a cocina', icon: Icons.restaurant_menu_rounded, group: 'Vender', module: 'carta_qr', feature: 'carta_qr', keywords: const ['restaurante', 'mesa', 'cocina', 'comanda', 'menu'], builder: (_) => const KitchenScreen()),
      FeatureEntry(id: 'precios', title: 'Precios y promociones', subtitle: 'Mayorista, "lleva 3 paga 2" y cupones', icon: Icons.local_offer_rounded, group: 'Vender', module: 'precios', feature: 'precios', perm: 'products_edit', keywords: const ['descuento', 'promocion', 'cupon', 'mayorista'], builder: (_) => const PromosScreen()),
      FeatureEntry(id: 'cupones', title: 'Cupones', subtitle: 'Códigos de descuento para premiar a quien vuelve', icon: Icons.confirmation_number_rounded, group: 'Vender', module: 'fidelizacion', feature: 'fidelizacion', perm: 'products_edit', keywords: const ['cupon', 'codigo', 'descuento', 'premio'], builder: (_) => const PromosScreen(couponsOnly: true)),
      FeatureEntry(id: 'puntos', title: 'Puntos y fidelización', subtitle: 'Premia a tus clientes frecuentes', icon: Icons.loyalty_rounded, group: 'Vender', module: 'fidelizacion', feature: 'fidelizacion', keywords: const ['puntos', 'cumpleanos', 'premio'], builder: (_) => const LoyaltyScreen()),
      FeatureEntry(id: 'reponer', title: 'Reposición inteligente', subtitle: 'Qué se te acaba y el pedido para tu proveedor', icon: Icons.shopping_cart_checkout_rounded, group: 'Vender', feature: 'stock', keywords: const ['reponer', 'comprar', 'proveedor', 'se acaba', 'pedido'], builder: (_) => const ReorderScreen()),
      FeatureEntry(id: 'platos', title: 'Cuentas y costo por plato', subtitle: 'Divide la cuenta, propina y margen de cada plato', icon: Icons.restaurant_rounded, group: 'Vender', feature: 'carta_qr', keywords: const ['dividir', 'cuenta', 'propina', 'plato', 'costo', 'margen'], builder: (_) => const DishesScreen()),
      // ───── Clientes y trabajos ─────
      FeatureEntry(id: 'clientes', feature: 'clientes', title: 'Clientes', subtitle: 'Ficha 360: deuda, historial, fotos y WhatsApp', icon: Icons.people_alt_rounded, group: 'Clientes y trabajos', perm: 'clients', keywords: const ['contacto', 'ruc', 'dni', 'ficha'], builder: (_) => const ClientsHubScreen()),
      FeatureEntry(id: 'clientes360', feature: 'clientes', title: 'Análisis de clientes', subtitle: 'Mejores clientes y los que se están yendo', icon: Icons.insights_rounded, group: 'Clientes y trabajos', perm: 'finance', keywords: const ['360', 'segmentos', 'riesgo'], builder: (_) => const Clients360Screen()),
      FeatureEntry(id: 'trabajos', title: 'Trabajos', subtitle: 'Seguimiento por estados, técnicos y fotos', icon: Icons.assignment_rounded, group: 'Clientes y trabajos', module: 'trabajos', feature: 'trabajos', perm: 'jobs', keywords: const ['instalacion', 'servicio', 'orden', 'tecnico', 'reparacion', 'obra'], builder: (_) => const JobsScreen()),
      FeatureEntry(id: 'agenda', title: 'Agenda y citas', subtitle: 'Visitas, citas y reservas en línea', icon: Icons.calendar_month_rounded, group: 'Clientes y trabajos', module: 'agenda', feature: 'agenda', perm: 'jobs', keywords: const ['cita', 'reserva', 'calendario', 'visita'], builder: (_) => const AgendaScreen()),
      FeatureEntry(id: 'encuestas', title: 'Encuestas de satisfacción', subtitle: '¿Qué tan contento quedó tu cliente?', icon: Icons.sentiment_satisfied_alt_rounded, group: 'Clientes y trabajos', module: 'encuestas', feature: 'encuestas', keywords: const ['opinion', 'calificacion', 'estrellas'], builder: (_) => const SurveysScreen()),
      FeatureEntry(id: 'paquetes', title: 'Paquetes y sesiones', subtitle: 'Sesiones prepagadas y quién falta a sus citas', icon: Icons.card_giftcard_rounded, group: 'Clientes y trabajos', feature: 'agenda', keywords: const ['paquete', 'sesiones', 'no vino', 'prepago', 'bono'], builder: (_) => const PackagesScreen()),
      FeatureEntry(id: 'historial', title: 'Historial privado', subtitle: 'Notas por paciente que solo ves tú', icon: Icons.lock_person_rounded, group: 'Clientes y trabajos', feature: 'agenda', perm: 'clients', keywords: const ['historia', 'paciente', 'nota', 'privado', 'clinica'], builder: (_) => const PrivateHistoryScreen()),
      FeatureEntry(id: 'recordatorios', feature: 'agenda', title: 'Les toca volver', subtitle: 'Mantenimientos, controles y retoques', icon: Icons.alarm_rounded, group: 'Clientes y trabajos', keywords: const ['recordatorio', 'mantenimiento', 'control', 'volver'], builder: (_) => const RemindersScreen()),
      FeatureEntry(id: 'placas', title: 'Buscar por placa', subtitle: 'El carro, su dueño y su historial', icon: Icons.directions_car_rounded, group: 'Clientes y trabajos', feature: 'trabajos', keywords: const ['placa', 'vehiculo', 'carro', 'auto', 'moto'], builder: (_) => const PlateScreen()),
      // ───── Cobrar y pagar ─────
      FeatureEntry(id: 'me_deben', feature: 'cobros', title: 'Lo que me deben', subtitle: 'Cobranza, fiados y avisos de Yape/Plin juntos', icon: Icons.request_page_rounded, group: 'Cobrar y pagar', perm: 'collect', keywords: const ['deben', 'deuda', 'cobrar', 'fiado'], builder: (_) => const OwedHubScreen()),
      FeatureEntry(id: 'cobranza', title: 'Cobranza', subtitle: 'Quién te debe y recordatorios por WhatsApp', icon: Icons.account_balance_wallet_rounded, group: 'Cobrar y pagar', feature: 'cobros', perm: 'collect', keywords: const ['deuda', 'cobrar', 'vencidas', 'recordatorio'], builder: (_) => const CollectionsScreen()),
      FeatureEntry(id: 'fiados', title: 'Libreta de fiados', subtitle: 'Anota lo que te deben y los abonos', icon: Icons.menu_book_rounded, group: 'Cobrar y pagar', module: 'fiados', feature: 'fiados', perm: 'collect', keywords: const ['fiado', 'credito', 'cuaderno', 'abono'], builder: (_) => const FiadosScreen()),
      FeatureEntry(id: 'caja', title: 'Caja y cierre del día', subtitle: 'Cuadra el efectivo y envía el reporte', icon: Icons.lock_clock_rounded, group: 'Cobrar y pagar', module: 'caja', feature: 'caja', perm: 'collect', keywords: const ['cierre', 'arqueo', 'efectivo', 'turno'], builder: (_) => const CashDayScreen()),
      FeatureEntry(id: 'avisos', title: 'Avisos de Yape y Plin', subtitle: 'Pega la notificación y se registra el cobro', icon: Icons.notifications_active_rounded, group: 'Cobrar y pagar', module: 'avisos_pago', feature: 'avisos_pago', perm: 'collect', keywords: const ['yape', 'plin', 'notificacion', 'pago'], builder: (_) => const PaymentNoticesScreen()),
      FeatureEntry(id: 'banco', title: 'Conciliación bancaria', subtitle: 'Sube tu estado de cuenta y cruza los cobros', icon: Icons.account_balance_rounded, group: 'Cobrar y pagar', module: 'conciliacion', feature: 'conciliacion', perm: 'finance', keywords: const ['banco', 'estado de cuenta', 'bcp', 'interbank', 'bbva'], builder: (_) => const BankReconScreen()),
      FeatureEntry(id: 'gastos', title: 'Gastos y pagos', subtitle: 'Compras y pagos del negocio', icon: Icons.shopping_bag_rounded, group: 'Cobrar y pagar', perm: 'finance', keywords: const ['compra', 'proveedor', 'pagar'], builder: (_) => const ExpensesScreen()),
      FeatureEntry(id: 'escanear', title: 'Escanear comprobante', subtitle: 'Foto de la factura de tu proveedor', icon: Icons.document_scanner_rounded, group: 'Cobrar y pagar', perm: 'finance', keywords: const ['ocr', 'foto', 'proveedor', 'compra'], builder: (_) => const ScanScreen()),
      FeatureEntry(id: 'corte', title: 'Mensualidades y corte', subtitle: 'Quién no pagó, aviso previo, corte y reconexión', icon: Icons.wifi_off_rounded, group: 'Cobrar y pagar', feature: 'recurrentes', perm: 'collect', keywords: const ['corte', 'moroso', 'mensualidad', 'reconexion', 'abonado'], builder: (_) => const CutoffScreen()),
      FeatureEntry(id: 'credito', feature: 'fiados', title: 'Crédito por cliente', subtitle: 'Límite, lo usado y quién se pasó', icon: Icons.credit_score_rounded, group: 'Cobrar y pagar', perm: 'finance', keywords: const ['credito', 'limite', 'linea'], builder: (_) => const CreditScreen()),
      FeatureEntry(id: 'morosidad', title: 'Pensiones pendientes', subtitle: 'Morosidad por grupo y aviso al apoderado', icon: Icons.school_rounded, group: 'Cobrar y pagar', feature: 'recurrentes', perm: 'collect', keywords: const ['pension', 'moroso', 'apoderado', 'alumno'], builder: (_) => const MorosityScreen()),
      // ───── Mi negocio ─────
      FeatureEntry(id: 'negocio_hub', feature: 'reportes', title: 'Mi negocio', subtitle: 'Ganancia, cuánto me queda, reportes y comisiones', icon: Icons.dashboard_rounded, group: 'Mi negocio', perm: 'finance', keywords: const ['resumen', 'ganancia', 'reportes'], builder: (_) => const BusinessHubScreen()),
      FeatureEntry(id: 'negocio', feature: 'reportes', title: 'Ganancia real', subtitle: 'Margen, flujo de caja y stock', icon: Icons.insights_rounded, group: 'Mi negocio', perm: 'finance', keywords: const ['ganancia', 'utilidad', 'rentabilidad'], builder: (_) => const ProfitScreen()),
      FeatureEntry(id: 'impuestos', title: '¿Cuánto me queda?', subtitle: 'Impuestos estimados y lo que debes guardar', icon: Icons.savings_rounded, group: 'Mi negocio', module: 'impuestos', feature: 'reportes', perm: 'finance', keywords: const ['igv', 'renta', 'sunat', 'impuesto', 'rus', 'mype'], builder: (_) => const TaxesScreen()),
      FeatureEntry(id: 'reportes', title: 'Reportes', subtitle: 'Ventas por mes y exportar a Excel', icon: Icons.table_view_rounded, group: 'Mi negocio', feature: 'reportes', perm: 'finance', keywords: const ['excel', 'exportar', 'contador'], builder: (_) => const ReportsScreen()),
      FeatureEntry(id: 'comisiones', title: 'Ventas por vendedor', subtitle: 'Ranking, metas y comisiones', icon: Icons.emoji_events_rounded, group: 'Mi negocio', module: 'comisiones', feature: 'comisiones', keywords: const ['comision', 'vendedor', 'meta', 'ranking'], builder: (_) => const CommissionsScreen()),
      FeatureEntry(id: 'importar', title: 'Importar datos', subtitle: 'Facturas antiguas desde Excel o CSV', icon: Icons.cloud_upload_rounded, group: 'Mi negocio', perm: 'import', keywords: const ['excel', 'csv', 'xlsx', 'migrar'], builder: (_) => const ImportScreen()),
      FeatureEntry(id: 'margen_obra', title: 'Margen por obra', subtitle: 'Cobrado, gastado y lo que te queda en cada obra', icon: Icons.engineering_rounded, group: 'Mi negocio', feature: 'trabajos', perm: 'finance', keywords: const ['obra', 'margen', 'valorizacion', 'subcontratista'], builder: (_) => const JobMarginScreen()),
      // ───── Control del dueño ─────
      FeatureEntry(id: 'alertas', title: 'Alertas del dueño', subtitle: 'Anulaciones, descuentos y caja que no cuadra', icon: Icons.shield_rounded, group: 'Control del dueño', module: 'antifraude', feature: 'antifraude', perm: 'team', keywords: const ['fraude', 'anulacion', 'distancia'], builder: (_) => const AlertsScreen()),
      FeatureEntry(id: 'bitacora', title: 'Bitácora', subtitle: 'Quién hizo qué y cuándo (no se puede alterar)', icon: Icons.history_rounded, group: 'Control del dueño', feature: 'antifraude', perm: 'team', keywords: const ['auditoria', 'historial', 'log'], builder: (_) => const AuditScreen()),
      FeatureEntry(id: 'pin', title: 'PIN del dueño', subtitle: 'Pide tu PIN para anular o borrar cobros', icon: Icons.pin_rounded, group: 'Control del dueño', perm: 'team', keywords: const ['clave', 'autorizar'], builder: (_) => const OwnerPinScreen()),
      FeatureEntry(id: 'papelera', title: 'Papelera', subtitle: 'Recupera lo borrado en los últimos 30 días', icon: Icons.restore_from_trash_rounded, group: 'Control del dueño', perm: 'finance', keywords: const ['borrado', 'recuperar', 'deshacer'], builder: (_) => const TrashScreen()),
      // ───── Ajustes ─────
      FeatureEntry(id: 'ajustes', title: 'Ajustes', subtitle: 'Todo lo de tu cuenta y tu negocio', icon: Icons.settings_rounded, group: 'Ajustes', keywords: const ['configuracion'], builder: (_) => const SettingsScreen()),
      FeatureEntry(id: 'equipo', title: 'Equipo y permisos', subtitle: 'Invita a tu gente y elige qué ve cada uno', icon: Icons.groups_rounded, group: 'Ajustes', perm: 'team', keywords: const ['empleado', 'rol', 'cajero', 'tecnico', 'usuario'], builder: (_) => const TeamScreen()),
      FeatureEntry(id: 'empresas', title: 'Mis empresas', subtitle: 'Cambia de empresa o crea otra', icon: Icons.apartment_rounded, group: 'Ajustes', keywords: const ['sucursal', 'empresa'], builder: (_) => const OrgsScreen()),
      FeatureEntry(id: 'datos', title: 'Datos del negocio', subtitle: 'Nombre, RUC, moneda e impuesto', icon: Icons.business_rounded, group: 'Ajustes', perm: 'settings', keywords: const ['ruc', 'razon social', 'direccion'], builder: (_) => const ProfileFormScreen()),
      FeatureEntry(id: 'sunat', title: 'SUNAT', subtitle: 'Usuario SOL, certificado y series', icon: Icons.verified_rounded, group: 'Ajustes', perm: 'settings', keywords: const ['sol', 'certificado', 'serie', 'electronica'], builder: (_) => const FiscalSetupScreen()),
      FeatureEntry(id: 'marca', title: 'Logo y comprobantes', subtitle: 'Tu logo, diseño del PDF y ticket', icon: Icons.palette_rounded, group: 'Ajustes', perm: 'settings', keywords: const ['logo', 'pdf', 'plantilla', 'diseno', 'ticket'], builder: (_) => const BrandingScreen()),
      FeatureEntry(id: 'impresora', title: 'Impresora de tickets', subtitle: 'Bluetooth o red, 58 u 80 mm', icon: Icons.print_rounded, group: 'Ajustes', keywords: const ['ticketera', 'bluetooth', 'termica', 'imprimir'], builder: (_) => const PrinterSettingsScreen()),
      FeatureEntry(id: 'medios', title: 'Medios de cobro', subtitle: 'Yape, Plin y banco; verificación manual del pago', icon: Icons.qr_code_2_rounded, group: 'Ajustes', perm: 'settings', keywords: const ['yape', 'plin', 'cuenta', 'mercado pago'], builder: (_) => const PaySettingsScreen()),
      FeatureEntry(id: 'tipo', title: 'Cambiar de rubro', subtitle: 'Bodega, restaurante, taller… con vista previa', icon: Icons.dashboard_customize_rounded, group: 'Ajustes', perm: 'settings', keywords: const ['rubro', 'tipo de negocio', 'plantilla', 'giro'], builder: (_) => RubroPickerScreen(current: Access.instance.rubro)),
      FeatureEntry(id: 'presentacion', title: 'Ver la presentación otra vez', subtitle: 'Rubro y modo Fácil paso a paso', icon: Icons.slideshow_rounded, group: 'Ajustes', perm: 'settings', keywords: const ['onboarding', 'presentacion', 'inicio', 'facil'], builder: (ctx) => BusinessSetupScreen(reopened: true, onDone: () => Navigator.of(ctx).pop())),
      FeatureEntry(id: 'modulos', title: 'Funciones a la vista', subtitle: 'Elige qué se ve primero', icon: Icons.tune_rounded, group: 'Ajustes', perm: 'settings', keywords: const ['modulos', 'ocultar', 'mostrar'], builder: (_) => const ModulesScreen()),
      FeatureEntry(id: 'plan', title: 'Mi plan', subtitle: 'Qué incluye, prueba gratis y pagos', icon: Icons.workspace_premium_rounded, group: 'Ajustes', keywords: const ['licencia', 'pago', 'suscripcion', 'prueba'], builder: (_) => const PlanScreen()),
      FeatureEntry(id: 'api', title: 'API y webhooks', subtitle: 'Conecta tu web o sistema', icon: Icons.integration_instructions_rounded, group: 'Ajustes', module: 'api_publica', feature: 'api_publica', perm: 'team', keywords: const ['api', 'integracion', 'webhook', 'desarrollador'], builder: (_) => const ApiAccessScreen()),
      FeatureEntry(id: 'seguridad', title: 'Seguridad', subtitle: 'PIN y huella para entrar', icon: Icons.fingerprint_rounded, group: 'Ajustes', mobileOnly: true, keywords: const ['huella', 'bloqueo', 'pin'], builder: (_) => const SecurityScreen()),
    ];

FeatureEntry? featureById(String id) {
  for (final f in featureCatalog()) {
    if (f.id == id) return f;
  }
  return null;
}

Future<void> openFeature(BuildContext context, FeatureEntry f) async {
  Haptics.tap();
  await pushPremium(context, Builder(builder: f.builder));
  AppState.instance.bump();
}

// ═════════════════════════ Todas las funciones ═════════════════════════
class AllFunctionsScreen extends StatefulWidget {
  const AllFunctionsScreen({super.key});

  @override
  State<AllFunctionsScreen> createState() => _AllFunctionsScreenState();
}

class _AllFunctionsScreenState extends State<AllFunctionsScreen> {
  OrgSettings? _settings;

  @override
  void initState() {
    super.initState();
    V2Repo.settings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = featureCatalog().where((f) => f.allowed).toList();
    final s = _settings;
    return RetailResponsiveFrame(maxWidth: 1320, child: Scaffold(
      appBar: AppBar(title: const Text('Todas las funciones'), actions: [
        IconButton(tooltip: 'Buscar', onPressed: () => openUniversalSearch(context), icon: const Icon(Icons.search_rounded)),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        if (s != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Ordenado para: ${s.template.name}. Lo marcado con ★ se ve a primera vista.', style: t.textTheme.bodySmall),
          ),
        LayoutBuilder(builder: (context, layout) {
          final columns = layout.maxWidth >= 880 ? 2 : 1;
          final itemWidth = (layout.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              for (final (gi, g) in groupOrder.indexed)
                if (all.any((f) => f.group == g))
                  SizedBox(
                    width: itemWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionTitle(g),
                        Reveal(
                          index: gi,
                          child: SoftCard(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(children: [
                              for (final f in all.where((f) => f.group == g))
                                ListTile(
                                  leading: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: (groupColors[g] ?? Brand.indigo)
                                        .withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(14)),
                                    child: Icon(f.icon,
                                      color: groupColors[g] ?? Brand.indigo, size: 21),
                                  ),
                                  title: Text.rich(TextSpan(children: [
                                    TextSpan(text: f.title),
                                    if (s != null && f.module != null &&
                                        s.shows(f.module!))
                                      const TextSpan(text: '  ★',
                                        style: TextStyle(color: Brand.warn)),
                                  ])),
                                  subtitle: Text(f.subtitle, maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () => openFeature(context, f),
                                ),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        }),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => pushPremium(context, const PlanScreen()),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text('¿Falta algo? Mira lo que incluye cada plan'),
          ),
        ),
      ]),
    ));
  }
}

/// Fila horizontal de accesos (para los hubs). Solo muestra lo que el plan y el rol permiten.
class FeatureStrip extends StatelessWidget {
  const FeatureStrip({super.key, required this.ids, this.settings});
  final List<String> ids;
  final OrgSettings? settings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = [
      for (final id in ids)
        if (featureById(id) case final f? when f.allowed) f,
    ];
    if (list.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final f = list[i];
          final c = featureColor(f.id);
          return Pressable(
            onTap: () => openFeature(context, f),
            child: Container(
              width: 112,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.withValues(alpha: 0.22)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(f.icon, color: c),
                // Una sola línea con ajuste: los textos nunca se parten en dos renglones (Fase 6, error reportado).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(f.title, maxLines: 1, softWrap: false, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ═════════════════════════ Avatar (cuenta) ═════════════════════════
class AvatarButton extends StatelessWidget {
  const AvatarButton({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final name = Access.instance.displayName.isNotEmpty ? Access.instance.displayName : email;
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Semantics(
      button: true,
      label: 'Mi cuenta, ajustes y SUNAT',
      child: Pressable(
        onTap: () => showAccountSheet(context),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onDark ? Colors.white.withValues(alpha: 0.22) : t.colorScheme.primary.withValues(alpha: 0.14),
          ),
          child: Text(letter, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 17, color: onDark ? Colors.white : t.colorScheme.primary)),
        ),
      ),
    );
  }
}

class SearchButton extends StatelessWidget {
  const SearchButton({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Buscar en toda la app',
      child: Pressable(
        onTap: () => openUniversalSearch(context),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle, color: onDark ? Colors.white.withValues(alpha: 0.18) : t.colorScheme.surfaceContainerHighest),
          child: Icon(Icons.search_rounded, color: onDark ? Colors.white : t.colorScheme.onSurface, size: 22),
        ),
      ),
    );
  }
}

Future<void> showAccountSheet(BuildContext context) {
  final nav = Navigator.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      final a = Access.instance;
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      final org = AppState.instance.activeOrg;
      void go(String id) {
        Navigator.of(ctx).pop();
        final f = featureById(id);
        if (f != null) openFeature(nav.context, f);
      }

      Widget tile(String id) {
        final f = featureById(id);
        if (f == null || !f.allowed) return const SizedBox.shrink();
        return ListTile(leading: Icon(f.icon), title: Text(f.title), subtitle: Text(f.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => go(id));
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(a.displayName.isNotEmpty ? a.displayName : email, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${org?.name ?? 'Mi empresa'} · ${a.roleLabel}'),
          ),
          const Divider(),
          tile('ajustes'),
          tile('sunat'),
          tile('datos'),
          tile('equipo'),
          tile('plan'),
          tile('empresas'),
          ListTile(
            leading: const Icon(Icons.menu_rounded),
            title: const Text('Menú (todas las funciones)'),
            onTap: () {
              Navigator.of(ctx).pop();
              pushPremium(nav.context, const MenuScreen());
            },
          ),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: t.colorScheme.error),
            title: Text('Cerrar sesión', style: TextStyle(color: t.colorScheme.error)),
            onTap: () async {
              Navigator.of(ctx).pop();
              AppState.instance.clear();
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ]),
      );
    },
  );
}

// ═════════════════════════ Buscador universal ═════════════════════════
Future<void> openUniversalSearch(BuildContext context, {bool voice = false}) => pushPremium(context, UniversalSearchScreen(startWithVoice: voice));

class _Hit {
  const _Hit(this.score, this.kind, this.title, this.subtitle, this.icon, this.open);
  final double score;
  final String kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback open;
}

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key, this.startWithVoice = false});
  final bool startWithVoice;

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  final _debounce = Debouncer(260);
  final _recorder = AudioRecorder();
  List<ClientProfile> _clients = const [];
  List<InvoiceRecord> _invoices = const [];
  List<Product> _products = const [];
  bool _loaded = false;
  bool _listening = false;
  bool _transcribing = false;
  double _level = 0;
  StreamSubscription<Amplitude>? _amp;
  Timer? _limit;

  @override
  void initState() {
    super.initState();
    _preload();
    if (widget.startWithVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _voice());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  Future<void> _preload() async {
    // Se cargan una vez y se filtra en el teléfono: la búsqueda responde al instante.
    final a = Access.instance;
    try {
      _clients = await V2Repo.clients();
    } catch (_) {}
    if (a.can('sell') || a.can('finance')) {
      try {
        _invoices = await Repo.listInvoices(limit: 300);
      } catch (_) {}
    }
    try {
      _products = await Repo.listProducts();
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    _debounce.dispose();
    _amp?.cancel();
    _limit?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _voice() async {
    if (_listening) return _stopVoice();
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permite el micrófono para buscar con la voz.')));
        return;
      }
      var path = '';
      if (!kIsWeb) path = '${(await getTemporaryDirectory()).path}/busqueda_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc, bitRate: 48000, sampleRate: 16000, numChannels: 1), path: path);
      _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
        if (mounted) setState(() => _level = ((a.current + 50) / 50).clamp(0.0, 1.0).toDouble());
      });
      _limit = Timer(const Duration(seconds: 8), _stopVoice);
      Haptics.soft();
      setState(() => _listening = true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo usar el micrófono.')));
    }
  }

  Future<void> _stopVoice() async {
    if (!_listening) return;
    _limit?.cancel();
    _amp?.cancel();
    setState(() {
      _listening = false;
      _transcribing = true;
      _level = 0;
    });
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    Uint8List? bytes;
    if (path != null && path.isNotEmpty) {
      try {
        bytes = await XFile(path).readAsBytes();
      } catch (_) {}
      if (!kIsWeb) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
    if (bytes == null) {
      if (mounted) setState(() => _transcribing = false);
      return;
    }
    try {
      final text = await V2Api.transcribe(bytes, filename: kIsWeb ? 'busqueda.webm' : 'busqueda.m4a', mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4');
      if (!mounted) return;
      _q.text = text.replaceAll(RegExp(r'[.¿?¡!]'), '').trim();
      setState(() => _transcribing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _transcribing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  List<_Hit> _hits(String q) {
    final out = <_Hit>[];
    if (q.trim().isEmpty) return out;
    for (final f in featureCatalog().where((f) => f.allowed)) {
      final s = matchScore(q, f.title, extra: [f.subtitle, ...f.keywords]);
      if (s > 0) out.add(_Hit(s + 0.2, 'Función', f.title, f.subtitle, f.icon, () => openFeature(context, f)));
    }
    for (final c in _clients) {
      final s = matchScore(q, c.name, extra: [c.taxId, c.phone, c.district, ...c.tags]);
      if (s > 0) {
        out.add(_Hit(s, 'Cliente', c.name, [c.taxId, c.phone].where((e) => e.isNotEmpty).join(' · '), Icons.person_rounded,
            () => pushPremium(context, ClientProfileScreen(clientId: c.id))));
      }
    }
    for (final i in _invoices) {
      final num = i.fiscalNumber ?? i.number;
      final s = matchScore(q, '$num ${i.clientName}', extra: [i.clientTaxId, i.issueDate]);
      if (s > 0) {
        out.add(_Hit(s * 0.9, 'Comprobante', '$num · ${i.clientName}', '${displayDate(i.issueDate)} · ${money(i.totals.total, i.currency)}', Icons.receipt_long_rounded,
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: i.id)))));
      }
    }
    for (final p in _products) {
      final s = matchScore(q, p.name);
      if (s > 0) out.add(_Hit(s * 0.85, 'Producto', p.name, money(p.unitPrice, AppState.instance.profile?.currency ?? 'PEN'), Icons.inventory_2_rounded, () => pushPremium(context, const ProductsScreen())));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(60).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hits = _hits(_q.text);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _debounce(() {
            if (mounted) setState(() {});
          }),
          decoration: const InputDecoration(hintText: 'Busca clientes, comprobantes, productos o funciones', border: InputBorder.none, filled: false, isDense: true),
        ),
        actions: [
          if (_q.text.isNotEmpty)
            IconButton(
              tooltip: 'Borrar',
              onPressed: () {
                _q.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close_rounded),
            ),
          IconButton(
            tooltip: _listening ? 'Detener' : 'Buscar con la voz',
            onPressed: _transcribing ? null : _voice,
            icon: _transcribing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_listening ? Icons.stop_circle_rounded : Icons.mic_rounded, color: _listening ? Brand.bad : null),
          ),
        ],
      ),
      body: Column(children: [
        AnimatedSize(
          duration: Motion.d(context, Motion.medium),
          child: _listening
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: Column(children: [
                    VoiceWave(level: _level, color: Brand.goldDeep),
                    const SizedBox(height: 6),
                    Text('Di lo que buscas: "Rosa", "boleta 23", "fiados"…', style: t.textTheme.bodySmall),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: _q.text.trim().isEmpty
              ? ListView(padding: const EdgeInsets.all(20), children: [
                  Text('Prueba con', style: t.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in const ['fiados', 'cierre de caja', 'impuestos', 'agenda', 'equipo', 'logo', 'impresora'])
                      ActionChip(
                        label: Text(s),
                        onPressed: () {
                          _q.text = s;
                          setState(() {});
                        },
                      ),
                  ]),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => pushPremium(context, const AllFunctionsScreen()),
                    icon: const Icon(Icons.apps_rounded),
                    label: const Text('Ver todas las funciones'),
                  ),
                ])
              : !_loaded && hits.isEmpty
                  ? const SkeletonList(count: 4)
                  : hits.isEmpty
                      ? const EmptyState(title: 'Sin resultados', body: 'Prueba con otra palabra, un DNI/RUC o el número del comprobante.')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
                          itemCount: hits.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (context, i) {
                            final h = hits[i];
                            return Reveal(
                              key: ValueKey('${h.kind}-${h.title}-$i'),
                              index: i < 10 ? i : 10,
                              child: ListTile(
                                leading: Icon(h.icon, color: t.colorScheme.primary),
                                title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text([h.kind, if (h.subtitle.isNotEmpty) h.subtitle].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: h.open,
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
