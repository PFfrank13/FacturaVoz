// Plantillas por tipo de negocio (Fase 1.3). Cada una define qué módulos se ven, los estados de los trabajos,
// los campos extra del cliente, las unidades y los textos. TODO es editable por el usuario y ninguna plantilla
// bloquea nada: solo ordena la pantalla para que cada negocio vea primero lo suyo.
// Lo que depende de normas (IGV exonerado, retenciones, etc.) se marca como "revisar con tu contador".
import 'package:flutter/material.dart';

class JobStatus {
  const JobStatus(this.key, this.label, {this.done = false, this.color = 0xFF6A62E2});
  final String key;
  final String label;
  final bool done;
  final int color;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'done': done, 'color': color};
  factory JobStatus.fromJson(Map<String, dynamic> j) =>
      JobStatus((j['key'] ?? '') as String, (j['label'] ?? '') as String, done: j['done'] == true, color: (j['color'] as num?)?.toInt() ?? 0xFF6A62E2);
}

class ClientField {
  const ClientField(this.key, this.label, {this.hint = ''});
  final String key;
  final String label;
  final String hint;
  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'hint': hint};
  factory ClientField.fromJson(Map<String, dynamic> j) => ClientField((j['key'] ?? '') as String, (j['label'] ?? '') as String, hint: (j['hint'] ?? '') as String);
}

class BusinessTemplate {
  const BusinessTemplate({
    required this.id,
    required this.name,
    required this.icon,
    required this.pitch,
    required this.modules,
    required this.statuses,
    this.clientFields = const [],
    this.jobWord = 'Trabajo',
    this.jobsWord = 'Trabajos',
    this.defaultJobKind = 'servicio',
    this.defaultUnit = 'NIU',
    this.tips = const [],
  });

  final String id;
  final String name;
  final IconData icon;
  final String pitch;

  /// Módulos que se ven sin buscarlos (el resto queda en "Todas las funciones").
  final Set<String> modules;
  final List<JobStatus> statuses;
  final List<ClientField> clientFields;
  final String jobWord;
  final String jobsWord;
  final String defaultJobKind;
  final String defaultUnit; // NIU producto | ZZ servicio
  final List<String> tips;
}

/// Módulos que existen en la app (claves usadas por plantillas, "Más funciones" y el buscador).
const allModules = <String, String>{
  'pos': 'Venta rápida (caja)',
  'cotizaciones': 'Cotizaciones',
  'recurrentes': 'Facturación recurrente',
  'tienda': 'Tienda en línea',
  'carta_qr': 'Carta digital y comandas',
  'trabajos': 'Trabajos y seguimiento',
  'agenda': 'Agenda y citas',
  'fiados': 'Libreta de fiados',
  'caja': 'Caja y cierre del día',
  'stock': 'Inventario',
  'gastos': 'Gastos',
  'cuaderno_ia': 'Del cuaderno a la factura',
  'precios': 'Listas de precios y promociones',
  'fidelizacion': 'Puntos y cupones',
  'conciliacion': 'Conciliación bancaria',
  'comisiones': 'Comisiones por vendedor',
  'impuestos': 'Cuánto me queda e impuestos',
  'portal_cliente': 'Portal del cliente',
  'encuestas': 'Encuestas de satisfacción',
  'avisos_pago': 'Avisos de Yape/Plin',
  'multimoneda': 'Ventas en dólares',
  'api_publica': 'API y webhooks',
  'antifraude': 'Dueño a distancia',
};

const _base = <JobStatus>[
  JobStatus('nuevo', 'Nuevo', color: 0xFF8A8CAB),
  JobStatus('en_proceso', 'En proceso', color: 0xFFC57A12),
  JobStatus('terminado', 'Terminado', done: true, color: 0xFF23956F),
];

const businessTemplates = <BusinessTemplate>[
  BusinessTemplate(
    id: 'bodega',
    name: 'Bodega o tienda',
    icon: Icons.storefront_rounded,
    pitch: 'Vende rápido, anota fiados y cuadra la caja cada noche.',
    clientFields: [ClientField('referencia', 'Referencia de la casa', hint: 'Cerca de…'), ClientField('dia_pago', 'Día en que suele pagar', hint: 'Ej. fin de mes, los sábados')],
    modules: {'pos', 'fiados', 'caja', 'stock', 'cuaderno_ia', 'tienda', 'avisos_pago', 'fidelizacion', 'impuestos'},
    statuses: [JobStatus('nuevo', 'Pedido', color: 0xFF8A8CAB), JobStatus('listo', 'Listo para recoger', color: 0xFFC57A12), JobStatus('entregado', 'Entregado', done: true, color: 0xFF23956F)],
    jobWord: 'Pedido',
    jobsWord: 'Pedidos',
    defaultJobKind: 'pedido',
    tips: ['Activa el PIN para que solo tú anules ventas.', 'Si tu negocio está en el Nuevo RUS solo emites boletas: revísalo con tu contador.'],
  ),
  BusinessTemplate(
    id: 'restaurante',
    name: 'Restaurante o cafetería',
    icon: Icons.restaurant_rounded,
    pitch: 'Carta con QR en cada mesa, comandas por área y cierre del día.',
    clientFields: [ClientField('preferencias', 'Preferencias', hint: 'Mesa favorita, cumpleaños, platos que pide')],
    modules: {'pos', 'carta_qr', 'tienda', 'caja', 'stock', 'encuestas', 'fidelizacion', 'avisos_pago', 'impuestos'},
    statuses: [JobStatus('nuevo', 'Reservado', color: 0xFF8A8CAB), JobStatus('confirmado', 'Confirmado', color: 0xFFC57A12), JobStatus('atendido', 'Atendido', done: true, color: 0xFF23956F)],
    jobWord: 'Reserva',
    jobsWord: 'Reservas',
    defaultJobKind: 'cita',
    tips: ['Imprime el QR de cada mesa desde Tienda → Carta digital.'],
  ),
  BusinessTemplate(
    id: 'servicios_tecnicos',
    name: 'Servicios técnicos e instalaciones',
    icon: Icons.router_rounded,
    pitch: 'Del interesado a la instalación cobrada: visitas, materiales, equipos y mensualidad.',
    modules: {'trabajos', 'agenda', 'cotizaciones', 'recurrentes', 'stock', 'portal_cliente', 'caja', 'impuestos'},
    statuses: [
      JobStatus('nuevo', 'Interesado', color: 0xFF8A8CAB),
      JobStatus('visita', 'Visita técnica', color: 0xFF5B8DEF),
      JobStatus('cotizado', 'Cotizado', color: 0xFF9B8CF5),
      JobStatus('pendiente', 'Instalación pendiente', color: 0xFFC57A12),
      JobStatus('en_camino', 'En camino', color: 0xFFE38B2C),
      JobStatus('instalado', 'Instalado', done: true, color: 0xFF23956F),
      JobStatus('cobrado', 'Cobrado', done: true, color: 0xFF1F7A5B),
    ],
    clientFields: [ClientField('plan', 'Plan contratado', hint: 'Ej. 100 Mbps'), ClientField('referencia', 'Referencia de la casa')],
    jobWord: 'Instalación',
    jobsWord: 'Instalaciones',
    defaultJobKind: 'instalacion',
    defaultUnit: 'ZZ',
    tips: ['Al marcar "Instalado" descuenta los materiales del inventario y registra el equipo en la ficha del cliente.'],
  ),
  BusinessTemplate(
    id: 'salon',
    name: 'Salón de belleza o barbería',
    icon: Icons.content_cut_rounded,
    pitch: 'Citas en línea, recordatorio por WhatsApp y clientes que vuelven.',
    modules: {'agenda', 'pos', 'fidelizacion', 'encuestas', 'caja', 'comisiones', 'avisos_pago'},
    statuses: [JobStatus('nuevo', 'Por confirmar', color: 0xFF8A8CAB), JobStatus('confirmado', 'Confirmada', color: 0xFFC57A12), JobStatus('atendido', 'Atendida', done: true, color: 0xFF23956F), JobStatus('no_vino', 'No vino', color: 0xFFD94A5E)],
    clientFields: [ClientField('preferencias', 'Preferencias', hint: 'Corte, tinte, alergias…')],
    jobWord: 'Cita',
    jobsWord: 'Citas',
    defaultJobKind: 'cita',
    defaultUnit: 'ZZ',
    tips: ['Comparte tu enlace de reservas en Instagram y WhatsApp.'],
  ),
  BusinessTemplate(
    id: 'consultorio',
    name: 'Consultorio o profesional independiente',
    icon: Icons.medical_services_rounded,
    pitch: 'Agenda de citas, historial por paciente o cliente y cobros ordenados.',
    modules: {'agenda', 'trabajos', 'recurrentes', 'portal_cliente', 'encuestas', 'impuestos'},
    statuses: [JobStatus('nuevo', 'Por confirmar', color: 0xFF8A8CAB), JobStatus('confirmado', 'Confirmada', color: 0xFFC57A12), JobStatus('atendido', 'Atendida', done: true, color: 0xFF23956F)],
    clientFields: [ClientField('antecedentes', 'Notas importantes', hint: 'Datos que debes recordar')],
    jobWord: 'Cita',
    jobsWord: 'Citas',
    defaultJobKind: 'cita',
    defaultUnit: 'ZZ',
    tips: ['Si emites recibos por honorarios, eso se hace en SUNAT; aquí controlas citas y cobros. Revísalo con tu contador.'],
  ),
  BusinessTemplate(
    id: 'taller',
    name: 'Taller mecánico',
    icon: Icons.car_repair_rounded,
    pitch: 'Órdenes de trabajo por vehículo, repuestos del inventario y aviso de "listo".',
    modules: {'trabajos', 'agenda', 'cotizaciones', 'stock', 'caja', 'portal_cliente', 'impuestos'},
    statuses: [
      JobStatus('nuevo', 'Recibido', color: 0xFF8A8CAB),
      JobStatus('diagnostico', 'Diagnóstico', color: 0xFF5B8DEF),
      JobStatus('cotizado', 'Presupuesto enviado', color: 0xFF9B8CF5),
      JobStatus('en_reparacion', 'En reparación', color: 0xFFC57A12),
      JobStatus('listo', 'Listo para recoger', done: true, color: 0xFF23956F),
      JobStatus('entregado', 'Entregado', done: true, color: 0xFF1F7A5B),
    ],
    clientFields: [ClientField('placa', 'Placa'), ClientField('vehiculo', 'Marca y modelo'), ClientField('km', 'Kilometraje')],
    jobWord: 'Orden',
    jobsWord: 'Órdenes de trabajo',
    defaultJobKind: 'reparacion',
    tips: ['Registra el vehículo como equipo del cliente: verás su historial en cada visita.'],
  ),
  BusinessTemplate(
    id: 'mayorista',
    name: 'Mayorista o distribuidor',
    icon: Icons.local_shipping_rounded,
    pitch: 'Precios por mayor, crédito controlado por cliente y cobranza automática.',
    clientFields: [ClientField('zona', 'Zona de reparto'), ClientField('condicion', 'Condición de pago', hint: 'Ej. contado, 15 días')],
    modules: {'cotizaciones', 'stock', 'precios', 'tienda', 'conciliacion', 'comisiones', 'multimoneda', 'api_publica', 'impuestos'},
    statuses: [JobStatus('nuevo', 'Pedido', color: 0xFF8A8CAB), JobStatus('despachado', 'Despachado', color: 0xFFC57A12), JobStatus('entregado', 'Entregado', done: true, color: 0xFF23956F)],
    jobWord: 'Pedido',
    jobsWord: 'Pedidos',
    defaultJobKind: 'pedido',
    tips: ['Fija un límite de crédito por cliente en su ficha: el Copiloto te avisa antes de pasarte.'],
  ),
  BusinessTemplate(
    id: 'educacion',
    name: 'Academia o educación',
    icon: Icons.school_rounded,
    pitch: 'Mensualidades que se facturan solas, horarios y recordatorios de pago.',
    modules: {'recurrentes', 'agenda', 'portal_cliente', 'encuestas', 'impuestos'},
    statuses: [JobStatus('nuevo', 'Inscrito', color: 0xFF8A8CAB), JobStatus('activo', 'En curso', color: 0xFFC57A12), JobStatus('terminado', 'Terminó', done: true, color: 0xFF23956F)],
    clientFields: [ClientField('alumno', 'Alumno', hint: 'Si el cliente es el apoderado'), ClientField('grupo', 'Grupo u horario')],
    jobWord: 'Matrícula',
    jobsWord: 'Matrículas',
    defaultJobKind: 'clase',
    defaultUnit: 'ZZ',
    tips: ['Algunos servicios educativos pueden estar exonerados de IGV: revísalo con tu contador.'],
  ),
  BusinessTemplate(
    id: 'construccion',
    name: 'Construcción o contratista',
    icon: Icons.engineering_rounded,
    pitch: 'Obras por avance: adelantos, hitos con fotos y cobro por etapas.',
    modules: {'trabajos', 'cotizaciones', 'agenda', 'stock', 'gastos', 'impuestos', 'conciliacion'},
    statuses: [
      JobStatus('nuevo', 'Presupuesto', color: 0xFF8A8CAB),
      JobStatus('aprobado', 'Aprobado', color: 0xFF9B8CF5),
      JobStatus('en_obra', 'En obra', color: 0xFFC57A12),
      JobStatus('terminado', 'Entregado', done: true, color: 0xFF23956F),
    ],
    clientFields: [ClientField('obra', 'Dirección de la obra')],
    jobWord: 'Obra',
    jobsWord: 'Obras',
    defaultJobKind: 'obra',
    defaultUnit: 'ZZ',
    tips: ['Divide cada obra en hitos (adelanto, avance, entrega) y factura cada uno con un toque.', 'Las detracciones dependen del tipo de servicio: revísalo con tu contador.'],
  ),
  BusinessTemplate(
    id: 'otro',
    name: 'Otro / personalizado',
    icon: Icons.tune_rounded,
    pitch: 'Bloques genéricos: clientes, productos o servicios, trabajos con estados y cobros.',
    modules: {'cotizaciones', 'trabajos', 'stock', 'caja'},
    statuses: _base,
  ),
];

BusinessTemplate templateFor(String? id) => businessTemplates.firstWhere((t) => t.id == id, orElse: () => businessTemplates.last);
