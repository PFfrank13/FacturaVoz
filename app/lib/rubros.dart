// Rubros v3: cada tipo de negocio es una experiencia completa (no una lista de casillas).
// Este archivo es PURO (sin pantallas): define barra de abajo, vocabulario, accesos de Inicio, áreas del Menú,
// medios de cobro, plantilla de comprobante, datos de práctica, Copiloto y la función estrella de cada rubro.
// Se prueba con `flutter test` (test/rubros_v3_test.dart). Nada se borra: lo que no es del rubro queda en
// Menú → "Otras funciones" y en el buscador.
//
// "Otro / personalizado" ya NO existe como opción. Las empresas que lo tenían eligen su rubro la próxima vez
// que el dueño abre la app (RubroGate); mientras tanto todo sigue funcionando y no se pierde ningún dato.

/// Destinos posibles de la barra de abajo (máximo 4 + micrófono).
const navDestinations = {'home', 'sell', 'clients', 'collect', 'business', 'jobs', 'agenda', 'quotes', 'fiados', 'tables', 'cash'};

class RubroNav {
  const RubroNav(this.id, this.label);
  final String id;
  final String label;
}

class RubroArea {
  const RubroArea(this.title, this.features);
  final String title;
  final List<String> features; // ids de featureCatalog()
}

class PracticeItem {
  const PracticeItem(this.name, this.price, {this.unit = 'NIU', this.cost});
  final String name;
  final double price; // sin IGV
  final String unit;
  final double? cost;
}

class RubroSpec {
  const RubroSpec({
    required this.id,
    required this.name,
    required this.pitch,
    required this.nav,
    required this.vocab,
    required this.home,
    required this.areas,
    required this.signature,
    required this.signatureTitle,
    required this.signaturePitch,
    required this.payMethods,
    required this.core,
    required this.copilotRole,
    required this.copilotStarters,
    required this.practiceProducts,
    required this.practiceClients,
    required this.notes,
    this.pdfTemplate = 'moderno',
    this.ticketWidth = 80,
    this.sensitiveData = false,
  });

  final String id;
  final String name;
  final String pitch;

  /// Barra de abajo: exactamente 4 destinos (el micrófono va al centro).
  final List<RubroNav> nav;

  /// Palabras del rubro: client/clients, job/jobs, product/products, sale.
  final Map<String, String> vocab;

  /// 3–4 accesos de Inicio (ids de funciones).
  final List<String> home;

  /// Áreas del Menú, en el orden del rubro.
  final List<RubroArea> areas;

  /// Función estrella (B3).
  final String signature;
  final String signatureTitle;
  final String signaturePitch;

  /// Medios de cobro que se ofrecen primero (claves de la tabla payments).
  final List<String> payMethods;

  /// Núcleo del rubro: funciones incluidas en TODOS los planes (igual que private.rubro_core en la base).
  final Set<String> core;

  final String copilotRole;
  final List<String> copilotStarters;
  final List<PracticeItem> practiceProducts;
  final List<String> practiceClients;

  /// Normas y avisos (con fuente en docs/RUBROS.md). Lo dudoso dice "revisa con tu contador".
  final List<String> notes;

  final String pdfTemplate; // clasico | moderno | minimal
  final int ticketWidth; // 58 | 80
  final bool sensitiveData; // datos de salud: consentimiento y acceso restringido

  String word(String key) => vocab[key] ?? _defaultVocab[key] ?? key;

  /// Funciones del rubro (las que se ven en el Menú sin abrir "Otras funciones").
  Set<String> get featureIds => {for (final a in areas) ...a.features, ...home, signature};
}

/// Funciones que existen en TODOS los rubros (gastos, caja, ajustes…). El resto solo aparece en su rubro.
const commonFeatures = <String>{
  'gastos', 'caja', 'cobranza', 'avisos', 'banco', 'negocio', 'impuestos', 'reportes', 'importar',
  'ajustes', 'equipo', 'datos', 'sunat', 'marca', 'impresora', 'medios', 'plan', 'seguridad', 'asistente', 'copiloto', 'agente',
  'me_deben', 'negocio_hub', 'alertas', 'bitacora', 'pin', 'papelera', 'modulos', 'api', 'empresas', 'escanear',
  'facturar', 'comprobantes', 'clientes',
};

/// ¿Esta función se muestra en este rubro? Sin rubro elegido (spec nulo) se muestra todo.
/// 'tipo' (cambiar de rubro) y 'presentacion' nunca: el rubro queda fijo una vez elegido.
bool rubroShows(RubroSpec? spec, String featureId) {
  if (featureId == 'tipo' || featureId == 'presentacion') return spec == null;
  if (spec == null) return true;
  return commonFeatures.contains(featureId) || spec.featureIds.contains(featureId);
}

const _defaultVocab = {
  'client': 'Cliente',
  'clients': 'Clientes',
  'job': 'Trabajo',
  'jobs': 'Trabajos',
  'product': 'Producto',
  'products': 'Productos',
  'sale': 'Venta',
};

// Áreas comunes al final de todos los menús.
const _moneyArea = RubroArea('Plata', ['cobranza', 'caja', 'gastos', 'avisos', 'banco']);
const _businessArea = RubroArea('Mi negocio', ['negocio', 'impuestos', 'reportes', 'comisiones', 'agente', 'importar']);
const _settingsArea = RubroArea('Ajustes', ['ajustes', 'equipo', 'datos', 'sunat', 'marca', 'impresora', 'medios', 'plan', 'seguridad']);

const rubros = <RubroSpec>[
  RubroSpec(
    id: 'bodega',
    name: 'Bodega o tienda',
    pitch: 'Vende rápido, anota fiados, repón a tiempo y cuadra la caja cada noche.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('sell', 'Vender'), RubroNav('fiados', 'Fiados'), RubroNav('cash', 'Caja')],
    vocab: {'client': 'Casero', 'clients': 'Caseros', 'job': 'Pedido', 'jobs': 'Pedidos'},
    home: ['pos', 'fiados', 'reponer', 'caja'],
    areas: [
      RubroArea('Tu bodega', ['pos', 'facturar', 'fiados', 'reponer', 'productos', 'compras', 'vencimientos', 'caja']),
      RubroArea('Vender más', ['tienda', 'puntos', 'precios', 'cupones', 'cotizaciones', 'cuaderno', 'avisos', 'credito', 'clientes360']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'reponer',
    signatureTitle: 'Reposición inteligente',
    signaturePitch: 'Te dice qué se te va a acabar según lo que vendes y arma el pedido para tu proveedor.',
    payMethods: ['efectivo', 'yape', 'plin', 'tarjeta'],
    core: {'stock', 'fiados', 'caja', 'avisos_pago'},
    copilotRole: 'el ayudante de una bodega de barrio: habla de ventas del día, fiados, productos que se acaban y la caja',
    copilotStarters: ['¿Cuánto vendí hoy?', '¿Quién me debe más fiado?', '¿Qué se me está acabando?'],
    practiceProducts: [PracticeItem('Arroz 1 kg', 3.81, cost: 3.1), PracticeItem('Aceite 1 L', 8.47, cost: 7.2), PracticeItem('Gaseosa 500 ml', 2.12, cost: 1.5)],
    practiceClients: ['Sra. Rosa (práctica)', 'Don Julio (práctica)'],
    notes: [
      'Si estás en el Nuevo RUS solo emites boletas y tickets (no facturas). Revisa tu régimen con tu contador.',
      'Boletas de más de S/ 700: van con nombre y DNI del comprador.',
    ],
    pdfTemplate: 'minimal',
    ticketWidth: 58,
  ),
  RubroSpec(
    id: 'restaurante',
    name: 'Restaurante o cafetería',
    pitch: 'Mesas y comandas al instante, cuenta dividida, propinas y cuánto te deja cada plato.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('tables', 'Mesas'), RubroNav('cash', 'Caja'), RubroNav('business', 'Negocio')],
    vocab: {'client': 'Comensal', 'clients': 'Comensales', 'product': 'Plato', 'products': 'Carta', 'job': 'Reserva', 'jobs': 'Reservas'},
    home: ['carta', 'platos', 'pos', 'caja'],
    areas: [
      RubroArea('Tu local', ['carta', 'pos', 'platos', 'productos', 'agenda', 'caja']),
      RubroArea('Clientes que vuelven', ['tienda', 'encuestas', 'puntos', 'avisos']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'platos',
    signatureTitle: 'Cuenta dividida, propinas y costo por plato',
    signaturePitch: 'Divide la cuenta en segundos, separa la propina y mira qué platos te dejan más.',
    payMethods: ['efectivo', 'yape', 'plin', 'tarjeta'],
    core: {'carta_qr', 'caja', 'stock'},
    copilotRole: 'el administrador de un restaurante: mesas, platos más vendidos, margen por plato, caja y propinas',
    copilotStarters: ['¿Qué plato vendí más esta semana?', '¿Cuánto entró hoy en caja?', '¿Qué plato me deja menos?'],
    practiceProducts: [PracticeItem('Lomo saltado', 25.42, cost: 11), PracticeItem('Ceviche', 27.12, cost: 12.5), PracticeItem('Chicha morada 1 L', 8.47, cost: 2)],
    practiceClients: ['Mesa 1 (práctica)'],
    notes: [
      'MYPE de restaurantes y hoteles: IGV 8 % + IPM 2 % (10 %) hasta el 31/12/2026 y 12 % + 2 % en 2027 (Ley 32219). Confirma con tu contador si calificas.',
      'La propina voluntaria es del personal: aquí se registra aparte y no se suma al comprobante. Revísalo con tu contador.',
    ],
    ticketWidth: 80,
  ),
  RubroSpec(
    id: 'servicios_tecnicos',
    name: 'Servicios técnicos e internet',
    pitch: 'Del interesado a la instalación cobrada: tablero, equipos con serie, mensualidades y corte por mora.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('jobs', 'Trabajos'), RubroNav('clients', 'Abonados'), RubroNav('collect', 'Cobrar')],
    vocab: {'client': 'Abonado', 'clients': 'Abonados', 'job': 'Instalación', 'jobs': 'Instalaciones', 'product': 'Plan o material', 'products': 'Planes y materiales'},
    home: ['trabajos', 'corte', 'recurrentes', 'agenda'],
    areas: [
      RubroArea('Tu servicio', ['trabajos', 'agenda', 'corte', 'recurrentes', 'clientes', 'productos']),
      RubroArea('Vender', ['facturar', 'cotizaciones']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'corte',
    signatureTitle: 'Mensualidades y corte por mora',
    signaturePitch: 'Ve quién pagó, avisa antes de cortar y registra corte y reconexión.',
    payMethods: ['yape', 'plin', 'transferencia', 'efectivo'],
    core: {'trabajos', 'agenda', 'recurrentes'},
    copilotRole: 'el jefe de operaciones de un proveedor de internet y servicios técnicos: instalaciones, técnicos, mensualidades y morosos',
    copilotStarters: ['¿Quién no pagó su mensualidad?', '¿Qué instalaciones hay hoy?', '¿Cuánto cobro este mes en mensualidades?'],
    practiceProducts: [PracticeItem('Plan 100 Mbps (mes)', 67.8, unit: 'ZZ'), PracticeItem('Instalación', 84.75, unit: 'ZZ'), PracticeItem('Router WiFi', 127.12, cost: 90)],
    practiceClients: ['Abonado Pérez (práctica)'],
    notes: [
      'Si eres operador registrado, las Condiciones de Uso de OSIPTEL exigen avisar al abonado antes de suspender el servicio por falta de pago. La app siempre propone el aviso previo. Revísalo con tu asesor.',
      'Servicios de más de S/ 700 pueden estar sujetos a detracción (12 % "demás servicios"). Revisa con tu contador.',
    ],
  ),
  RubroSpec(
    id: 'salon',
    name: 'Salón o barbería',
    pitch: 'Reservas en línea, menos clientes que no vienen, comisión por estilista y paquetes prepagados.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('agenda', 'Citas'), RubroNav('clients', 'Clientes'), RubroNav('cash', 'Caja')],
    vocab: {'job': 'Cita', 'jobs': 'Citas', 'product': 'Servicio', 'products': 'Servicios'},
    home: ['agenda', 'paquetes', 'pos', 'comisiones'],
    areas: [
      RubroArea('Tu salón', ['agenda', 'paquetes', 'recordatorios', 'pos', 'comisiones', 'caja']),
      RubroArea('Clientes que vuelven', ['puntos', 'encuestas', 'tienda', 'avisos']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'paquetes',
    signatureTitle: 'Paquetes, no-shows y comisiones',
    signaturePitch: 'Vende paquetes de sesiones, descuenta cada visita y mira quién falta a sus citas.',
    payMethods: ['yape', 'plin', 'efectivo', 'tarjeta'],
    core: {'agenda', 'caja'},
    copilotRole: 'el administrador de un salón de belleza o barbería: citas del día, no-shows, comisiones por estilista y paquetes',
    copilotStarters: ['¿Qué citas tengo hoy?', '¿Cuánto comisiona cada estilista este mes?', '¿Qué clientes no vienen hace un mes?'],
    practiceProducts: [PracticeItem('Corte', 21.19, unit: 'ZZ'), PracticeItem('Tinte', 76.27, unit: 'ZZ'), PracticeItem('Barba', 12.71, unit: 'ZZ')],
    practiceClients: ['Clienta Ana (práctica)'],
    notes: ['Las comisiones son un acuerdo con tu equipo: si son trabajadores en planilla o por recibo por honorarios, revísalo con tu contador.'],
  ),
  RubroSpec(
    id: 'consultorio',
    name: 'Consultorio o profesional independiente',
    pitch: 'Agenda con confirmación por WhatsApp, historial privado por paciente y sesiones prepagadas.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('agenda', 'Agenda'), RubroNav('clients', 'Pacientes'), RubroNav('collect', 'Cobrar')],
    vocab: {'client': 'Paciente', 'clients': 'Pacientes', 'job': 'Cita', 'jobs': 'Citas', 'product': 'Servicio', 'products': 'Servicios'},
    home: ['agenda', 'historial', 'paquetes', 'cobranza'],
    areas: [
      RubroArea('Tu consulta', ['agenda', 'historial', 'paquetes', 'recordatorios', 'clientes']),
      RubroArea('Cobrar y comprobantes', ['facturar', 'recurrentes', 'cobranza']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'historial',
    signatureTitle: 'Historial privado del paciente',
    signaturePitch: 'Notas que solo ves tú (y tu administrador), con consentimiento registrado.',
    payMethods: ['yape', 'plin', 'transferencia', 'efectivo', 'tarjeta'],
    core: {'agenda'},
    copilotRole: 'el asistente administrativo de un consultorio: agenda, citas por confirmar, sesiones y cobros. NUNCA habla de diagnósticos ni de notas clínicas',
    copilotStarters: ['¿Qué citas tengo mañana?', '¿Quién tiene sesiones por usar?', '¿Cuánto cobré esta semana?'],
    practiceProducts: [PracticeItem('Consulta', 67.8, unit: 'ZZ'), PracticeItem('Sesión de terapia', 50.85, unit: 'ZZ')],
    practiceClients: ['Paciente de práctica'],
    notes: [
      'Los datos de salud son "datos sensibles" (Ley 29733): necesitas el consentimiento por escrito del paciente. La app lo pide antes de la primera nota privada.',
      'Si eres profesional independiente (4.ª categoría) emites recibos por honorarios en SUNAT; aquí controlas citas y cobros. Revísalo con tu contador.',
    ],
    sensitiveData: true,
  ),
  RubroSpec(
    id: 'taller',
    name: 'Taller mecánico',
    pitch: 'Orden por placa, presupuesto por WhatsApp con fotos, repuestos del inventario y aviso de mantenimiento.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('jobs', 'Órdenes'), RubroNav('clients', 'Clientes'), RubroNav('collect', 'Cobrar')],
    vocab: {'job': 'Orden', 'jobs': 'Órdenes', 'product': 'Repuesto o servicio', 'products': 'Repuestos y servicios'},
    home: ['placas', 'trabajos', 'recordatorios', 'cotizaciones'],
    areas: [
      RubroArea('Tu taller', ['placas', 'trabajos', 'cotizaciones', 'recordatorios', 'productos']),
      RubroArea('Vender', ['facturar', 'pos']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'placas',
    signatureTitle: 'Buscar por placa y mantenimientos',
    signaturePitch: 'Escribe o dicta la placa: ves el carro, su dueño, su historial y cuándo le toca volver.',
    payMethods: ['efectivo', 'yape', 'transferencia', 'tarjeta'],
    core: {'trabajos', 'cotizaciones', 'stock'},
    copilotRole: 'el jefe de un taller mecánico: órdenes abiertas, presupuestos por aprobar, repuestos y mantenimientos que tocan',
    copilotStarters: ['¿Qué carros están listos para entregar?', '¿Qué presupuestos no aprueban aún?', '¿A quién le toca mantenimiento?'],
    practiceProducts: [PracticeItem('Cambio de aceite', 101.69, unit: 'ZZ'), PracticeItem('Filtro de aceite', 25.42, cost: 15), PracticeItem('Alineamiento', 50.85, unit: 'ZZ')],
    practiceClients: ['Carlos (práctica) · ABC-123'],
    notes: ['Mantenimiento y reparación de bienes muebles de más de S/ 700 puede tener detracción (12 %). Revísalo con tu contador.'],
  ),
  RubroSpec(
    id: 'mayorista',
    name: 'Mayorista o distribuidor',
    pitch: 'Listas de precios, crédito con límite por cliente, pedidos que se repiten y cobranza ordenada.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('quotes', 'Pedidos'), RubroNav('clients', 'Clientes'), RubroNav('collect', 'Cobranza')],
    vocab: {'job': 'Despacho', 'jobs': 'Despachos'},
    home: ['cotizaciones', 'credito', 'cobranza', 'precios'],
    areas: [
      RubroArea('Tu distribuidora', ['cotizaciones', 'credito', 'precios', 'productos', 'compras', 'recurrentes', 'cobranza']),
      RubroArea('Vender', ['facturar', 'tienda', 'comisiones']),
      _moneyArea,
      _businessArea,
      RubroArea('Conexiones', ['api']),
      _settingsArea,
    ],
    signature: 'credito',
    signatureTitle: 'Crédito con límite por cliente',
    signaturePitch: 'Cuánto le diste a cada cliente, cuánto le queda y quién ya se pasó.',
    payMethods: ['transferencia', 'yape', 'efectivo'],
    core: {'cotizaciones', 'stock', 'precios'},
    copilotRole: 'el gerente comercial de una distribuidora: pedidos, crédito por cliente, cobranza y precios por mayor',
    copilotStarters: ['¿Quién se pasó de su límite de crédito?', '¿Cuánto me deben a más de 30 días?', '¿Qué pedidos faltan despachar?'],
    practiceProducts: [PracticeItem('Caja de leche x 24', 101.69, cost: 85), PracticeItem('Saco de azúcar 50 kg', 152.54, cost: 130)],
    practiceClients: ['Minimarket Lucía (práctica)'],
    notes: [
      'Para trasladar mercadería necesitas guía de remisión ELECTRÓNICA (GRE). FacturaVoz aún no la emite: hazla gratis en SUNAT (SOL o app) y anota su número en el pedido.',
      'Si tu cliente es agente de retención, te retendrá 3 % del IGV en facturas de más de S/ 700. Revísalo con tu contador.',
    ],
    pdfTemplate: 'clasico',
  ),
  RubroSpec(
    id: 'educacion',
    name: 'Academia o educación',
    pitch: 'Matrículas, mensualidades que se cobran solas, morosidad por grupo y aviso a los apoderados.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('clients', 'Alumnos'), RubroNav('collect', 'Pensiones'), RubroNav('agenda', 'Horarios')],
    vocab: {'client': 'Alumno o apoderado', 'clients': 'Alumnos', 'job': 'Matrícula', 'jobs': 'Matrículas', 'product': 'Curso', 'products': 'Cursos'},
    home: ['morosidad', 'recurrentes', 'agenda', 'cobranza'],
    areas: [
      RubroArea('Tu academia', ['clientes', 'morosidad', 'recurrentes', 'agenda', 'paquetes']),
      RubroArea('Familias', ['encuestas', 'cobranza']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'morosidad',
    signatureTitle: 'Morosidad por grupo y apoderados',
    signaturePitch: 'Quién debe la pensión, de qué grupo, y aviso al apoderado con un toque.',
    payMethods: ['yape', 'plin', 'transferencia', 'efectivo'],
    core: {'recurrentes', 'agenda'},
    copilotRole: 'el administrador de una academia: matrículas, pensiones pendientes por grupo, apoderados y horarios',
    copilotStarters: ['¿Quién debe la pensión de este mes?', '¿Cuántos alumnos activos tengo?', '¿Qué grupo tiene más morosos?'],
    practiceProducts: [PracticeItem('Pensión mensual', 250, unit: 'ZZ'), PracticeItem('Matrícula', 100, unit: 'ZZ')],
    practiceClients: ['Apoderado de práctica'],
    notes: ['Algunos servicios educativos pueden estar exonerados o inafectos de IGV según quién los presta. Revísalo con tu contador antes de emitir.'],
  ),
  RubroSpec(
    id: 'construccion',
    name: 'Construcción o contratista',
    pitch: 'Obras por hitos, valorizaciones, adelantos, subcontratistas y margen real por obra.',
    nav: [RubroNav('home', 'Inicio'), RubroNav('jobs', 'Obras'), RubroNav('collect', 'Cobrar'), RubroNav('business', 'Negocio')],
    vocab: {'job': 'Obra', 'jobs': 'Obras', 'product': 'Partida o material', 'products': 'Partidas y materiales'},
    home: ['trabajos', 'margen_obra', 'cotizaciones', 'gastos'],
    areas: [
      RubroArea('Tus obras', ['trabajos', 'margen_obra', 'cotizaciones', 'gastos', 'productos']),
      RubroArea('Cobrar', ['facturar', 'cobranza', 'banco']),
      _moneyArea,
      _businessArea,
      _settingsArea,
    ],
    signature: 'margen_obra',
    signatureTitle: 'Margen por obra',
    signaturePitch: 'Lo cobrado, lo gastado (materiales y subcontratistas) y lo que de verdad te queda en cada obra.',
    payMethods: ['transferencia', 'efectivo', 'yape'],
    core: {'trabajos', 'cotizaciones'},
    copilotRole: 'el jefe de obra y finanzas de un contratista: hitos, valorizaciones, adelantos, gastos por obra y margen',
    copilotStarters: ['¿Qué obra me deja menos margen?', '¿Qué hitos faltan cobrar?', '¿Cuánto gasté en la obra más grande?'],
    practiceProducts: [PracticeItem('Tarrajeo m²', 33.9, unit: 'ZZ'), PracticeItem('Bolsa de cemento', 27.97, cost: 24)],
    practiceClients: ['Obra Los Pinos (práctica)'],
    notes: ['Contratos de construcción de más de S/ 700: detracción de 4 % (Anexo 3, SPOT). Revisa con tu contador.'],
    pdfTemplate: 'clasico',
  ),
];

/// Rubro de una empresa. null si no eligió (o tenía "Otro"): la app pide elegir (RubroGate).
RubroSpec? rubroFor(String? id) {
  for (final r in rubros) {
    if (r.id == id) return r;
  }
  return null;
}

/// ¿El núcleo del rubro incluye [feature]? (igual que private.rubro_core).
bool rubroIncludes(String? rubroId, String feature) => rubroFor(rubroId)?.core.contains(feature) ?? false;

/// Plan mínimo que trae [feature] (para "Disponible en el plan X").
// ───────────── Planes × rubro (misma tabla que private.plan_matrix en la base; una prueba exige que coincidan) ─────────────
// Básico = esenciales del rubro · Pro = Básico + UN módulo estrella + Copiloto · Empresa = todo + Copiloto agente.
const planCodes = ['BASICO', 'PRO', 'EMPRESA'];
const _basicCommon = {'facturar', 'clientes', 'cobros', 'voz', 'cotizaciones', 'reportes', 'avisos_pago', 'caja'};
const _basicExtra = <String, Set<String>>{
  'bodega': {'stock', 'fiados'},
  'restaurante': {'carta_qr', 'stock'},
  'servicios_tecnicos': {'trabajos', 'agenda', 'recurrentes'},
  'salon': {'agenda'},
  'consultorio': {'agenda'},
  'taller': {'trabajos', 'stock'},
  'mayorista': {'stock', 'precios'},
  'educacion': {'recurrentes', 'agenda'},
  'construccion': {'trabajos'},
};

/// Módulo estrella que desbloquea Pro en cada rubro (además del Copiloto).
const proStar = <String, String>{
  'bodega': 'fidelizacion',
  'restaurante': 'agenda',
  'servicios_tecnicos': 'portal_cliente',
  'salon': 'comisiones',
  'consultorio': 'recurrentes',
  'taller': 'agenda',
  'mayorista': 'tienda',
  'educacion': 'portal_cliente',
  'construccion': 'agenda',
};

/// Todas las funciones por plan (Empresa las tiene todas).
const allFeatureKeys = <String>{
  'facturar', 'clientes', 'cobros', 'voz', 'cotizaciones', 'tienda', 'stock', 'recurrentes', 'copiloto', 'copiloto_agente', 'trabajos',
  'agenda', 'reportes', 'multisucursal', 'fiados', 'caja', 'cuaderno_ia', 'portal_cliente', 'precios', 'fidelizacion', 'carta_qr',
  'conciliacion', 'comisiones', 'avisos_pago', 'multimoneda', 'api_publica', 'encuestas', 'antifraude',
};

/// Funciones que [plan] desbloquea para [rubro] (acumulativo). Rubro o plan desconocido → null (se usa la licencia tal cual).
Set<String>? planMatrix(String? rubro, String plan) {
  if (rubro == null || !_basicExtra.containsKey(rubro) || !planCodes.contains(plan)) return null;
  if (plan == 'EMPRESA') return allFeatureKeys;
  return {..._basicCommon, ..._basicExtra[rubro]!, if (plan == 'PRO') ...{'copiloto', proStar[rubro]!}};
}

/// Plan más bajo que trae [feature]. Con rubro conocido usa la matriz de ese rubro; si no, la lista general.
String? minPlanFor(String feature, Map<String, Map<String, dynamic>> plans, {String? rubro}) {
  if (rubro != null && _basicExtra.containsKey(rubro)) {
    for (final code in planCodes) {
      if (planMatrix(rubro, code)!.contains(feature)) return code;
    }
    return null;
  }
  for (final code in planCodes) {
    final v = plans[code]?[feature];
    if (v == true || (v is num && v != 0)) return code;
  }
  return null;
}

/// Precio mensual en soles, IGV incluido. Copia de docs/facturavoz-planes.json (confirmado en Solvex Hub): el que cobra de verdad es Solvex Hub,
/// así que si cambias un precio allá, cámbialo también aquí (una prueba compara con el JSON).
const planPrices = <String, double>{'BASICO': 39, 'PRO': 79, 'EMPRESA': 179};

/// Límites por plan (copia de docs/facturavoz-planes.json → features.max_users / max_branches; -1 = sin límite).
/// La base aplica los que entrega Solvex Hub para cada empresa (feature_limit); esto es solo para comparar planes.
const planLimits = <String, ({int users, int branches})>{
  'BASICO': (users: 2, branches: 1),
  'PRO': (users: 5, branches: 1),
  'EMPRESA': (users: 20, branches: 5),
};

/// Días de prueba gratis configurados por plan (docs/facturavoz-planes.json → trial_days). Una prueba lo compara.
/// Confirmado en Solvex Hub el 22/11/2026. Si cambia allá, cámbialo en el JSON y aquí.
const planTrialDays = <String, int>{'BASICO': 7, 'PRO': 7, 'EMPRESA': 7};

String planPriceText(String code) {
  final p = planPrices[code];
  if (p == null) return '';
  return 'S/ ${p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2)} al mes';
}

/// Herramientas que trae [plan] para [rubro] y que el plan anterior no tenía (Básico: todas las suyas).
List<String> planNewTools(String? rubro, String plan) {
  final cur = planMatrix(rubro, plan);
  if (cur == null) return const [];
  final i = planCodes.indexOf(plan);
  final prev = i > 0 ? planMatrix(rubro, planCodes[i - 1]) ?? const <String>{} : const <String>{};
  return [
    for (final k in allFeatureKeys)
      if (cur.contains(k) && !prev.contains(k)) k,
  ];
}

String planName(String code) => switch (code) { 'BASICO' => 'Básico', 'PRO' => 'Pro', 'EMPRESA' => 'Empresa', _ => code };

/// Funciones por plan (copia de docs/facturavoz-planes.json; el Hub manda, esto es solo para los textos de "mejora tu plan").
const planFeatures = <String, Map<String, dynamic>>{
  'BASICO': {'facturar': true, 'clientes': true, 'cobros': true, 'voz': true, 'cotizaciones': true, 'stock': true, 'reportes': true, 'fiados': true, 'caja': true, 'avisos_pago': true},
  'PRO': {
    'facturar': true, 'clientes': true, 'cobros': true, 'voz': true, 'cotizaciones': true, 'tienda': true, 'stock': true, 'recurrentes': true,
    'copiloto': true, 'trabajos': true, 'agenda': true, 'reportes': true, 'fiados': true, 'caja': true, 'cuaderno_ia': true, 'portal_cliente': true,
    'precios': true, 'fidelizacion': true, 'carta_qr': true, 'comisiones': true, 'avisos_pago': true, 'multimoneda': true, 'encuestas': true,
  },
  'EMPRESA': {
    'copiloto_agente': true, 'facturar': true, 'clientes': true, 'cobros': true, 'voz': true, 'cotizaciones': true, 'tienda': true, 'stock': true, 'recurrentes': true,
    'copiloto': true, 'trabajos': true, 'agenda': true, 'reportes': true, 'multisucursal': true, 'fiados': true, 'caja': true, 'cuaderno_ia': true,
    'portal_cliente': true, 'precios': true, 'fidelizacion': true, 'carta_qr': true, 'conciliacion': true, 'comisiones': true, 'avisos_pago': true,
    'multimoneda': true, 'api_publica': true, 'encuestas': true, 'antifraude': true,
  },
};
