import '../rubros.dart';

// Guía de orientación para el usuario. SOLO cambia la presentación:
// los IDs, las licencias, los permisos y los flujos de datos no se modifican.
class RubroExperience {
  const RubroExperience({required this.homeTitle, required this.homeSubtitle, required this.menuSubtitle, required this.steps});

  final String homeTitle;
  final String homeSubtitle;
  final String menuSubtitle;
  final List<String> steps;
}

const _generic = RubroExperience(
  homeTitle: 'Tu negocio, paso a paso',
  homeSubtitle: 'Empieza por una tarea y encuentra las demás en el menú.',
  menuSubtitle: 'Tus tareas diarias primero. Las opciones avanzadas están más abajo.',
  steps: ['Configura los datos de tu negocio.', 'Registra una venta o un servicio.', 'Consulta lo cobrado y lo pendiente.'],
);

const rubroExperiences = <String, RubroExperience>{
  'bodega': RubroExperience(
    homeTitle: 'Tu bodega, lista para vender',
    homeSubtitle: 'Vende, revisa tus fiados y controla lo que se está acabando.',
    menuSubtitle: 'Vende desde la caja, registra fiados y repón productos.',
    steps: ['Agrega productos con su precio y cantidad.', 'Vende desde Vender o con el micrófono.', 'Consulta los fiados y cierra la caja al final del día.'],
  ),
  'restaurante': RubroExperience(
    homeTitle: 'Mesas, pedidos y caja en orden',
    homeSubtitle: 'Organiza la carta, envía comandas y cobra sin perder pedidos.',
    menuSubtitle: 'Tu carta y tus mesas primero; el resto cuando lo necesites.',
    steps: ['Prepara la carta y organiza las mesas.', 'Toma el pedido y envía la comanda a cocina.', 'Cobra la cuenta y entrega el comprobante.'],
  ),
  'servicios_tecnicos': RubroExperience(
    homeTitle: 'Cada servicio bajo control',
    homeSubtitle: 'Sigue trabajos, clientes y pagos pendientes.',
    menuSubtitle: 'Registra el trabajo, sigue su avance y cobra al terminar.',
    steps: ['Registra al cliente y el equipo o instalación.', 'Crea el trabajo y actualiza su estado.', 'Registra el cobro o la mensualidad pendiente.'],
  ),
  'salon': RubroExperience(
    homeTitle: 'Tu agenda, siempre organizada',
    homeSubtitle: 'Citas, servicios y cobros en un mismo lugar.',
    menuSubtitle: 'Reserva una cita, atiende y cobra el servicio.',
    steps: ['Configura tus servicios y horarios.', 'Agenda la cita de cada cliente.', 'Marca el servicio realizado y registra el pago.'],
  ),
  'consultorio': RubroExperience(
    homeTitle: 'Atenciones claras y ordenadas',
    homeSubtitle: 'Agenda, pacientes y pagos con acceso protegido.',
    menuSubtitle: 'Programa consultas y registra los pagos con privacidad.',
    steps: ['Registra al paciente y programa la cita.', 'Consulta la agenda y atiende.', 'Registra el pago; protege siempre los datos de salud.'],
  ),
  'taller': RubroExperience(
    homeTitle: 'Cada vehículo con su historial',
    homeSubtitle: 'Placa, orden de trabajo, repuestos y cobro.',
    menuSubtitle: 'Busca por placa, crea la orden y controla su avance.',
    steps: ['Busca o registra la placa del vehículo.', 'Crea la orden con diagnóstico y repuestos.', 'Marca el trabajo terminado y cobra.'],
  ),
  'mayorista': RubroExperience(
    homeTitle: 'Tus pedidos, listos para entregar',
    homeSubtitle: 'Cotiza, controla precios y consulta las deudas.',
    menuSubtitle: 'Gestiona pedidos, clientes y créditos comerciales.',
    steps: ['Prepara los productos y los precios de venta.', 'Crea una cotización o pedido del cliente.', 'Registra la venta y consulta sus pagos pendientes.'],
  ),
  'educacion': RubroExperience(
    homeTitle: 'Alumnos y pagos sin enredos',
    homeSubtitle: 'Cursos, horarios y pensiones pendientes en orden.',
    menuSubtitle: 'Organiza alumnos, clases y mensualidades.',
    steps: ['Registra alumnos y cursos.', 'Organiza los horarios y mensualidades.', 'Revisa los pagos pendientes y registra los cobros.'],
  ),
  'construccion': RubroExperience(
    homeTitle: 'Cada obra, de inicio a fin',
    homeSubtitle: 'Controla órdenes, materiales, gastos y pagos.',
    menuSubtitle: 'Organiza el avance y los costos de cada obra.',
    steps: ['Crea la obra y sus trabajos.', 'Registra los materiales y los gastos.', 'Consulta lo facturado, cobrado y pendiente.'],
  ),
};

RubroExperience experienceFor(String? rubro) => rubroExperiences[rubro] ?? _generic;

/// Nombres cortos con sentido para las tarjetas pequeñas; nunca usar solo la primera palabra del título.
String shortActionLabel(String id, String fallback) => switch (id) {
  'pos' => 'Venta rápida',
  'facturar' => 'Facturar',
  'carta' => 'Carta y cocina',
  'platos' => 'Cuentas',
  'fiados' => 'Fiados',
  'reponer' => 'Reponer',
  'caja' => 'Caja',
  'trabajos' => 'Trabajos',
  'corte' => 'Mensualidades',
  'recurrentes' => 'Pagos mensuales',
  'agenda' => 'Citas',
  'paquetes' => 'Paquetes',
  'comisiones' => 'Comisiones',
  'historial' => 'Historial',
  'cobranza' => 'Cobros',
  'placas' => 'Buscar placa',
  'recordatorios' => 'Recordatorios',
  'cotizaciones' => 'Cotizar',
  'credito' => 'Créditos',
  'precios' => 'Precios',
  'morosidad' => 'Pensiones',
  'margen_obra' => 'Costos de obra',
  'gastos' => 'Gastos',
  _ => fallback,
};

/// Títulos del menú en lenguaje cotidiano; los IDs y la agrupación original se conservan.
String simpleAreaTitle(String title) => switch (title) {
  'Plata' => 'Cobros y caja',
  'Mi negocio' => 'Reportes y administración',
  'Ajustes' => 'Configuración',
  'Vender más' => 'Promociones y tienda',
  'Clientes que vuelven' => 'Clientes y promociones',
  'Familias' => 'Familias y pagos',
  'Conexiones' => 'Integraciones',
  _ => title,
};

/// Lo que no aparece en las áreas principales permanece visible en «Más herramientas».
/// La lista de funciones permitidas se calcula fuera, respetando plan y rol.
List<String> extraMenuFeatureIds(RubroSpec? spec, Iterable<String> visibleIds) {
  final listed = <String>{if (spec != null) for (final area in spec.areas) ...area.features};
  return [for (final id in visibleIds) if (!listed.contains(id)) id];
}
