// Contrato de navegación (Prompt Maestro §3): una función canónica = una responsabilidad = una ruta identificable.
// Fuente de verdad de los destinos de la barra inferior y de la ACCIÓN PRINCIPAL de cada rubro.
// Es solo datos: shell.dart e inicio.dart lo leen; las pruebas verifican que todo destino exista y tenga dueño.
import 'package:flutter/material.dart';

/// Destino de nivel 1 (barra inferior).
class NavContract {
  const NavContract({
    required this.id,
    required this.goal,
    this.permission,
    required this.primaryAction,
    this.feature,
    this.keepState = const [],
    this.invalidates = const [],
  });

  final String id;

  /// Para qué existe (una sola responsabilidad).
  final String goal;

  /// Función del plan requerida (null = siempre).
  final String? feature;

  /// Permiso granular requerido (permissions.dart). null = cualquier integrante.
  final String? permission;

  /// Acción principal visible en la pantalla.
  final String primaryAction;

  /// Estado que se conserva al cambiar de pestaña.
  final List<String> keepState;

  /// Datos que se recargan al volver (otra pestaña pudo cambiarlos).
  final List<String> invalidates;
}

const navContracts = <String, NavContract>{
  'home': NavContract(id: 'home', goal: 'Ver el día y lanzar la acción principal del rubro', primaryAction: 'Acción principal del rubro', invalidates: ['ventas del día', 'caja', 'alertas']),
  'sell': NavContract(id: 'sell', goal: 'Vender: carrito → cobro → comprobante', feature: 'facturar', permission: 'sales.create', primaryAction: 'Cobrar', keepState: ['carrito'], invalidates: ['stock']),
  'quotes': NavContract(id: 'quotes', goal: 'Pedidos y cotizaciones hasta convertirlos en venta', feature: 'cotizaciones', permission: 'sales.create', primaryAction: 'Nuevo pedido'),
  'fiados': NavContract(id: 'fiados', goal: 'Libreta de lo que te deben y sus abonos', feature: 'fiados', permission: 'payments.record', primaryAction: 'Registrar abono', invalidates: ['saldos']),
  'cash': NavContract(id: 'cash', goal: 'Apertura, movimientos, arqueo y cierre de caja', feature: 'caja', permission: 'cash.close', primaryAction: 'Cerrar caja', invalidates: ['movimientos']),
  'collect': NavContract(id: 'collect', goal: 'Cobrar comprobantes pendientes', feature: 'cobros', permission: 'payments.record', primaryAction: 'Registrar cobro', invalidates: ['saldos']),
  'business': NavContract(id: 'business', goal: 'Ganancia, flujo y stock del negocio', feature: 'reportes', permission: 'reports.profit', primaryAction: 'Ver reporte'),
  'jobs': NavContract(id: 'jobs', goal: 'Órdenes / trabajos / obras por estado', feature: 'trabajos', permission: 'jobs.create', primaryAction: 'Nueva orden', keepState: ['filtro de estado']),
  'agenda': NavContract(id: 'agenda', goal: 'Citas del día y de la semana', feature: 'agenda', permission: 'jobs.create', primaryAction: 'Nueva cita', keepState: ['día visible']),
  'clients': NavContract(id: 'clients', goal: 'Ficha del cliente: deuda, historial y contacto', feature: 'clientes', permission: 'customers.manage', primaryAction: 'Nuevo cliente', keepState: ['búsqueda']),
  'tables': NavContract(id: 'tables', goal: 'Mesas, comandas y cocina', feature: 'carta_qr', permission: 'sales.create', primaryAction: 'Nuevo pedido'),
};

/// Qué hace la acción principal.
enum PrimaryKind { feature, jobForm, quote }

class PrimaryAction {
  const PrimaryAction(this.label, this.icon, this.kind, {this.featureId, this.jobKind, required this.permission, this.feature});

  /// Texto del botón (en mayúscula de oración; la pantalla decide el estilo).
  final String label;
  final IconData icon;
  final PrimaryKind kind;

  /// Para [PrimaryKind.feature]: id de featureCatalog().
  final String? featureId;

  /// Para [PrimaryKind.jobForm]: tipo de trabajo (null = el del rubro).
  final String? jobKind;

  /// Permiso granular y función del plan que habilitan el botón.
  final String permission;
  final String? feature;
}

/// Acción principal por rubro (Prompt §2: bodega VENDER, salón NUEVA CITA, taller NUEVA ORDEN, restaurante NUEVO PEDIDO…).
const primaryActions = <String, PrimaryAction>{
  'bodega': PrimaryAction('Vender', Icons.point_of_sale_rounded, PrimaryKind.feature, featureId: 'pos', permission: 'sales.create', feature: 'facturar'),
  'restaurante': PrimaryAction('Nuevo pedido', Icons.restaurant_menu_rounded, PrimaryKind.feature, featureId: 'pos', permission: 'sales.create', feature: 'facturar'),
  'servicios_tecnicos': PrimaryAction('Nueva orden', Icons.add_task_rounded, PrimaryKind.jobForm, permission: 'jobs.create', feature: 'trabajos'),
  'salon': PrimaryAction('Nueva cita', Icons.event_available_rounded, PrimaryKind.jobForm, jobKind: 'cita', permission: 'jobs.create', feature: 'agenda'),
  'consultorio': PrimaryAction('Nueva cita', Icons.event_available_rounded, PrimaryKind.jobForm, jobKind: 'cita', permission: 'jobs.create', feature: 'agenda'),
  'taller': PrimaryAction('Nueva orden', Icons.car_repair_rounded, PrimaryKind.jobForm, permission: 'jobs.create', feature: 'trabajos'),
  'mayorista': PrimaryAction('Nuevo pedido', Icons.request_quote_rounded, PrimaryKind.quote, permission: 'sales.create', feature: 'cotizaciones'),
  'educacion': PrimaryAction('Cobrar pensión', Icons.school_rounded, PrimaryKind.feature, featureId: 'morosidad', permission: 'payments.record', feature: 'recurrentes'),
  'construccion': PrimaryAction('Nueva obra', Icons.engineering_rounded, PrimaryKind.jobForm, jobKind: 'obra', permission: 'jobs.create', feature: 'trabajos'),
};

PrimaryAction? primaryActionFor(String? rubro) => rubro == null ? null : primaryActions[rubro];
