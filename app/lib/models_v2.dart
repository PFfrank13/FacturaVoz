// Modelos de la v2.0 (CRM, equipo, módulos de dinero y conexión). Solo datos: sin Flutter ni red.
import 'business_templates.dart';

double _n(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
double? _nn(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
String _s(dynamic v) => (v ?? '').toString();
DateTime? _d(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

// ───────────────────────── Configuración del negocio ─────────────────────────
class OrgSettings {
  OrgSettings({
    this.businessType = 'otro',
    this.simpleMode = true,
    Map<String, bool>? modules,
    List<JobStatus>? jobStatuses,
    List<ClientField>? clientFields,
    Map<String, String>? labels,
    this.onboardingDone = false,
    this.loyaltyRate = 0,
    this.birthdayGreetings = true,
    this.surveyAuto = false,
    this.dailyReport = false,
    this.dailyReportTo = '',
    this.taxRegime,
    this.exists = false,
  })  : modules = modules ?? {},
        jobStatuses = jobStatuses ?? [],
        clientFields = clientFields ?? [],
        labels = labels ?? {};

  String businessType;
  bool simpleMode;
  Map<String, bool> modules; // ajustes del usuario sobre la plantilla
  List<JobStatus> jobStatuses;
  List<ClientField> clientFields;
  Map<String, String> labels;
  bool onboardingDone;
  double loyaltyRate;
  bool birthdayGreetings;
  bool surveyAuto;
  bool dailyReport;
  String dailyReportTo;
  String? taxRegime;
  final bool exists;

  BusinessTemplate get template => templateFor(businessType);

  /// Estados efectivos: los del negocio o, si no los configuró, los de su plantilla.
  List<JobStatus> get statuses => jobStatuses.isNotEmpty ? jobStatuses : template.statuses;
  List<ClientField> get fields => clientFields.isNotEmpty ? clientFields : template.clientFields;
  String get jobWord => labels['job'] ?? template.jobWord;
  String get jobsWord => labels['jobs'] ?? template.jobsWord;

  /// ¿Se muestra el módulo a primera vista? (en "Todas las funciones" siempre está, si el plan y el rol lo permiten).
  bool shows(String module) => modules[module] ?? template.modules.contains(module);

  JobStatus statusOf(String key) => statuses.firstWhere((s) => s.key == key, orElse: () => JobStatus(key, key));

  factory OrgSettings.fromJson(Map<String, dynamic> j) => OrgSettings(
        businessType: _s(j['business_type']).isEmpty ? 'otro' : _s(j['business_type']),
        simpleMode: j['simple_mode'] != false,
        modules: _m(j['modules']).map((k, v) => MapEntry(k, v == true)),
        jobStatuses: ((j['job_statuses'] ?? const []) as List).map((e) => JobStatus.fromJson(_m(e))).where((s) => s.key.isNotEmpty).toList(),
        clientFields: ((j['client_fields'] ?? const []) as List).map((e) => ClientField.fromJson(_m(e))).where((f) => f.key.isNotEmpty).toList(),
        labels: _m(j['labels']).map((k, v) => MapEntry(k, v.toString())),
        onboardingDone: j['onboarding_done'] == true,
        loyaltyRate: _n(j['loyalty_rate']),
        birthdayGreetings: j['birthday_greetings'] != false,
        surveyAuto: j['survey_auto'] == true,
        dailyReport: j['daily_report'] == true,
        dailyReportTo: _s(j['daily_report_to']),
        taxRegime: j['tax_regime'] as String?,
        exists: true,
      );

  Map<String, dynamic> toRow() => {
        'business_type': businessType,
        'simple_mode': simpleMode,
        'modules': modules,
        'job_statuses': jobStatuses.map((s) => s.toJson()).toList(),
        'client_fields': clientFields.map((f) => f.toJson()).toList(),
        'labels': labels,
        'onboarding_done': onboardingDone,
        'loyalty_rate': loyaltyRate,
        'birthday_greetings': birthdayGreetings,
      };
}

// ───────────────────────── CRM ─────────────────────────
class ClientProfile {
  ClientProfile({
    required this.id,
    required this.name,
    this.taxId = '',
    this.docType = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.district = '',
    this.reference = '',
    this.lat,
    this.lng,
    List<String>? tags,
    this.source = '',
    this.birthday,
    this.notes = '',
    this.creditLimit,
    Map<String, dynamic>? extra,
    this.lastContactAt,
    this.createdAt,
  })  : tags = tags ?? [],
        extra = extra ?? {};

  final String id;
  String name;
  String taxId;
  String docType;
  String email;
  String phone;
  String address;
  String district;
  String reference;
  double? lat;
  double? lng;
  List<String> tags;
  String source;
  String? birthday; // yyyy-MM-dd
  String notes;
  double? creditLimit;
  Map<String, dynamic> extra;
  final DateTime? lastContactAt;
  final DateTime? createdAt;

  static const columns =
      'id, name, tax_id, doc_type, email, phone, address, district, reference, lat, lng, tags, source, birthday, notes, credit_limit, extra, last_contact_at, created_at';

  factory ClientProfile.fromJson(Map<String, dynamic> j) => ClientProfile(
        id: _s(j['id']),
        name: _s(j['name']),
        taxId: _s(j['tax_id']),
        docType: _s(j['doc_type']),
        email: _s(j['email']),
        phone: _s(j['phone']),
        address: _s(j['address']),
        district: _s(j['district']),
        reference: _s(j['reference']),
        lat: _nn(j['lat']),
        lng: _nn(j['lng']),
        tags: ((j['tags'] ?? const []) as List).map((e) => e.toString()).toList(),
        source: _s(j['source']),
        birthday: j['birthday'] as String?,
        notes: _s(j['notes']),
        creditLimit: _nn(j['credit_limit']),
        extra: _m(j['extra']),
        lastContactAt: _d(j['last_contact_at']),
        createdAt: _d(j['created_at']),
      );

  Map<String, dynamic> toRow() => {
        'name': name.trim(),
        'tax_id': taxId.trim().isEmpty ? null : taxId.trim(),
        'email': email.trim().isEmpty ? null : email.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'address': address.trim().isEmpty ? null : address.trim(),
        'district': district.trim().isEmpty ? null : district.trim(),
        'reference': reference.trim().isEmpty ? null : reference.trim(),
        'lat': lat,
        'lng': lng,
        'tags': tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().take(20).toList(),
        'source': source.isEmpty ? null : source,
        'birthday': birthday,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'credit_limit': creditLimit,
        'extra': extra,
      };

  /// Celular peruano listo para WhatsApp (51 + 9 dígitos) o '' si no hay.
  String get waPhone {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^9\d{8}$').hasMatch(d)) return '51$d';
    if (RegExp(r'^519\d{8}$').hasMatch(d)) return d;
    return '';
  }
}

const clientSources = {'whatsapp': 'WhatsApp', 'referido': 'Referido', 'web': 'Web / tienda', 'llamada': 'Llamada', 'redes': 'Redes sociales', 'paso': 'Pasó por el local', 'otro': 'Otro'};

class ClientNote {
  const ClientNote({required this.id, required this.kind, required this.body, required this.createdAt});
  final String id;
  final String kind;
  final String body;
  final DateTime? createdAt;
  factory ClientNote.fromJson(Map<String, dynamic> j) => ClientNote(id: _s(j['id']), kind: _s(j['kind']), body: _s(j['body']), createdAt: _d(j['created_at']));
}

class ClientAsset {
  const ClientAsset({required this.id, required this.name, this.model = '', this.serial = '', this.installedOn, this.warrantyUntil, this.notes = '', this.jobId});
  final String id;
  final String name;
  final String model;
  final String serial;
  final String? installedOn;
  final String? warrantyUntil;
  final String notes;
  final String? jobId;
  factory ClientAsset.fromJson(Map<String, dynamic> j) => ClientAsset(
        id: _s(j['id']),
        name: _s(j['name']),
        model: _s(j['model']),
        serial: _s(j['serial']),
        installedOn: j['installed_on'] as String?,
        warrantyUntil: j['warranty_until'] as String?,
        notes: _s(j['notes']),
        jobId: j['job_id'] as String?,
      );
}

const jobKinds = {
  'visita': 'Visita',
  'instalacion': 'Instalación',
  'servicio': 'Servicio',
  'reparacion': 'Reparación',
  'cita': 'Cita',
  'obra': 'Obra',
  'pedido': 'Pedido',
  'clase': 'Clase',
  'otro': 'Otro',
};

class Job {
  Job({
    this.id,
    this.clientId,
    this.clientName = '',
    this.clientPhone = '',
    required this.title,
    this.kind = 'servicio',
    this.status = 'nuevo',
    this.source,
    this.assignedTo,
    this.scheduledAt,
    this.durationMin,
    this.address = '',
    this.lat,
    this.lng,
    this.contactPhone = '',
    this.notes = '',
    this.techNote = '',
    this.amount,
    this.quoteId,
    this.invoiceId,
    this.recurringId,
    this.position = 0,
    this.doneAt,
    this.createdAt,
  });

  final String? id;
  String? clientId;
  String clientName;
  String clientPhone;
  String title;
  String kind;
  String status;
  String? source;
  String? assignedTo;
  DateTime? scheduledAt;
  int? durationMin;
  String address;
  double? lat;
  double? lng;
  String contactPhone;
  String notes;
  String techNote;
  double? amount;
  String? quoteId;
  String? invoiceId;
  String? recurringId;
  int position;
  final DateTime? doneAt;
  final DateTime? createdAt;

  bool get done => doneAt != null;

  static const columns =
      'id, client_id, title, kind, status, source, assigned_to, scheduled_at, duration_min, address, lat, lng, contact_phone, notes, tech_note, amount, quote_id, invoice_id, recurring_id, position, done_at, created_at, clients(name, phone)';

  factory Job.fromJson(Map<String, dynamic> j) {
    final c = _m(j['clients']);
    return Job(
      id: j['id'] as String?,
      clientId: j['client_id'] as String?,
      clientName: _s(c['name']),
      clientPhone: _s(c['phone']),
      title: _s(j['title']),
      kind: _s(j['kind']).isEmpty ? 'servicio' : _s(j['kind']),
      status: _s(j['status']).isEmpty ? 'nuevo' : _s(j['status']),
      source: j['source'] as String?,
      assignedTo: j['assigned_to'] as String?,
      scheduledAt: _d(j['scheduled_at']),
      durationMin: (j['duration_min'] as num?)?.toInt(),
      address: _s(j['address']),
      lat: _nn(j['lat']),
      lng: _nn(j['lng']),
      contactPhone: _s(j['contact_phone']),
      notes: _s(j['notes']),
      techNote: _s(j['tech_note']),
      amount: _nn(j['amount']),
      quoteId: j['quote_id'] as String?,
      invoiceId: j['invoice_id'] as String?,
      recurringId: j['recurring_id'] as String?,
      position: (j['position'] as num?)?.toInt() ?? 0,
      doneAt: _d(j['done_at']),
      createdAt: _d(j['created_at']),
    );
  }

  Map<String, dynamic> toRow() => {
        'client_id': clientId,
        'title': title.trim(),
        'kind': kind,
        'status': status,
        'source': source,
        'assigned_to': assignedTo,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'duration_min': durationMin,
        'address': address.trim().isEmpty ? null : address.trim(),
        'lat': lat,
        'lng': lng,
        'contact_phone': contactPhone.trim().isEmpty ? null : contactPhone.trim(),
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'tech_note': techNote.trim().isEmpty ? null : techNote.trim(),
        'amount': amount,
        'quote_id': quoteId,
        'invoice_id': invoiceId,
        'recurring_id': recurringId,
        'position': position,
      };
}

class JobMaterial {
  const JobMaterial({required this.id, this.productId, required this.description, required this.quantity, this.unitPrice = 0, this.discounted = false});
  final String id;
  final String? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final bool discounted;
  factory JobMaterial.fromJson(Map<String, dynamic> j) => JobMaterial(
        id: _s(j['id']),
        productId: j['product_id'] as String?,
        description: _s(j['description']),
        quantity: _n(j['quantity']),
        unitPrice: _n(j['unit_price']),
        discounted: j['discounted'] == true,
      );
}

class JobMilestone {
  const JobMilestone({required this.id, required this.title, required this.amount, this.dueDate, this.status = 'pendiente', this.invoiceId});
  final String id;
  final String title;
  final double amount;
  final String? dueDate;
  final String status; // pendiente | listo | facturado
  final String? invoiceId;
  factory JobMilestone.fromJson(Map<String, dynamic> j) => JobMilestone(
        id: _s(j['id']),
        title: _s(j['title']),
        amount: _n(j['amount']),
        dueDate: j['due_date'] as String?,
        status: _s(j['status']).isEmpty ? 'pendiente' : _s(j['status']),
        invoiceId: j['invoice_id'] as String?,
      );
}

class MediaFile {
  MediaFile({required this.id, required this.path, required this.kind, this.caption = '', this.url});
  final String id;
  final String path;
  final String kind; // foto | antes | despues | documento
  final String caption;
  String? url; // URL firmada (se pide al mostrar)
  factory MediaFile.fromJson(Map<String, dynamic> j) => MediaFile(id: _s(j['id']), path: _s(j['path']), kind: _s(j['kind']), caption: _s(j['caption']));
}

class JobEvent {
  const JobEvent({required this.from, required this.to, required this.at});
  final String from;
  final String to;
  final DateTime? at;
  factory JobEvent.fromJson(Map<String, dynamic> j) => JobEvent(from: _s(j['from_status']), to: _s(j['to_status']), at: _d(j['created_at']));
}

/// Aviso del día (daily_alerts): visitas, trabajos atrasados, clientes sin contacto, cumpleaños, fiados vencidos.
class DailyAlert {
  const DailyAlert(this.kind, this.data);
  final String kind;
  final Map<String, dynamic> data;
  String get client => _s(data['client']);
  String get phone => _s(data['phone']);
  String get title => _s(data['title']);
  DateTime? get at => _d(data['at']);
  factory DailyAlert.fromJson(Map<String, dynamic> j) => DailyAlert(_s(j['kind']), j);
}

// ───────────────────────── Equipo ─────────────────────────
class TeamMember {
  const TeamMember({required this.userId, required this.email, required this.role, this.staffRole, this.displayName = '', this.commissionPct, this.salesGoal});
  final String userId;
  final String email;
  final String role; // owner | admin | member
  final String? staffRole;
  final String displayName;
  final double? commissionPct;
  final double? salesGoal;
  String get effectiveRole => role == 'owner' || role == 'admin' ? role : (staffRole ?? 'cajero');
  String get shownName => displayName.isNotEmpty ? displayName : email.split('@').first;
  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        userId: _s(j['user_id']),
        email: _s(j['email']),
        role: _s(j['role']),
        staffRole: j['staff_role'] as String?,
        displayName: _s(j['display_name']),
        commissionPct: _nn(j['commission_pct']),
        salesGoal: _nn(j['sales_goal']),
      );
}

class TeamInvite {
  const TeamInvite({required this.id, required this.email, required this.role, this.staffRole, this.displayName = ''});
  final String id;
  final String email;
  final String role;
  final String? staffRole;
  final String displayName;
  factory TeamInvite.fromJson(Map<String, dynamic> j) =>
      TeamInvite(id: _s(j['id']), email: _s(j['email']), role: _s(j['role']), staffRole: j['staff_role'] as String?, displayName: _s(j['display_name']));
}

const staffRoles = {
  'cajero': ('Cajero', 'Vende, cobra y cierra caja. No ve gastos ni ganancias.'),
  'vendedor': ('Vendedor', 'Vende y cotiza. Ideal para comisiones y metas.'),
  'tecnico': ('Técnico', 'Solo ve sus trabajos y su agenda.'),
  'finanzas': ('Finanzas', 'Ve todo el dinero: gastos, ganancias, conciliación.'),
};

// ───────────────────────── Dinero ─────────────────────────
class CreditBalance {
  const CreditBalance({required this.clientId, required this.name, this.phone = '', required this.balance, required this.charges, required this.payments, this.lastMove, this.oldestDue, this.creditLimit});
  final String clientId;
  final String name;
  final String phone;
  final double balance;
  final double charges;
  final double payments;
  final DateTime? lastMove;
  final String? oldestDue;
  final double? creditLimit;
  bool overdue(String today) => balance > 0.004 && oldestDue != null && oldestDue!.compareTo(today) < 0;
  bool get overLimit => creditLimit != null && balance > creditLimit!;
  factory CreditBalance.fromJson(Map<String, dynamic> j) => CreditBalance(
        clientId: _s(j['client_id']),
        name: _s(j['client_name']),
        phone: _s(j['phone']),
        balance: _n(j['balance']),
        charges: _n(j['charges']),
        payments: _n(j['payments']),
        lastMove: _d(j['last_move']),
        oldestDue: j['oldest_due'] as String?,
        creditLimit: _nn(j['credit_limit']),
      );
}

class CreditMove {
  const CreditMove({required this.id, required this.kind, required this.amount, this.description = '', this.dueDate, this.method, this.createdAt});
  final String id;
  final String kind; // cargo | abono
  final double amount;
  final String description;
  final String? dueDate;
  final String? method;
  final DateTime? createdAt;
  factory CreditMove.fromJson(Map<String, dynamic> j) => CreditMove(
        id: _s(j['id']),
        kind: _s(j['kind']),
        amount: _n(j['amount']),
        description: _s(j['description']),
        dueDate: j['due_date'] as String?,
        method: j['method'] as String?,
        createdAt: _d(j['created_at']),
      );
}

class CashMove {
  const CashMove({required this.id, required this.kind, required this.amount, required this.method, this.note = '', this.createdAt});
  final String id;
  final String kind; // apertura | ingreso | egreso
  final double amount;
  final String method;
  final String note;
  final DateTime? createdAt;
  factory CashMove.fromJson(Map<String, dynamic> j) =>
      CashMove(id: _s(j['id']), kind: _s(j['kind']), amount: _n(j['amount']), method: _s(j['method']), note: _s(j['note']), createdAt: _d(j['created_at']));
}

class DaySummary {
  const DaySummary(this.raw);
  final Map<String, dynamic> raw;
  String get currency => _s(raw['currency']).isEmpty ? 'PEN' : _s(raw['currency']);
  Map<String, dynamic> get sales => _m(raw['sales']);
  double get salesTotal => _n(sales['sales_total']);
  int get salesCount => _n(sales['sales_count']).toInt();
  int get draftsCount => _n(sales['drafts_count']).toInt();
  Map<String, double> get byMethod => _m(raw['payments_by_method']).map((k, v) => MapEntry(k, _n(v)));
  double get opening => _n(raw['cash_opening']);
  double get cashSales => _n(raw['cash_sales']);
  double get cashIn => _n(raw['cash_in']);
  double get cashOut => _n(raw['cash_out']);
  double get fiadoCharged => _n(raw['fiado_charged']);
  double get fiadoPaid => _n(raw['fiado_paid']);
  double get expectedCash => _n(raw['expected_cash']);
  double? get expenses => _nn(raw['expenses']);
  double get collected => byMethod.values.fold(0.0, (a, b) => a + b);
}

class OwnerAlert {
  const OwnerAlert({required this.id, required this.kind, required this.severity, required this.title, this.body = '', this.createdAt, this.readAt, this.data = const {}});
  final String id;
  final String kind;
  final String severity;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> data;
  factory OwnerAlert.fromJson(Map<String, dynamic> j) => OwnerAlert(
        id: _s(j['id']),
        kind: _s(j['kind']),
        severity: _s(j['severity']),
        title: _s(j['title']),
        body: _s(j['body']),
        createdAt: _d(j['created_at']),
        readAt: _d(j['read_at']),
        data: _m(j['data']),
      );
}

class AuditEntry {
  const AuditEntry({required this.id, required this.action, required this.entity, required this.data, this.createdAt});
  final int id;
  final String action;
  final String entity;
  final Map<String, dynamic> data;
  final DateTime? createdAt;
  factory AuditEntry.fromJson(Map<String, dynamic> j) =>
      AuditEntry(id: (j['id'] as num?)?.toInt() ?? 0, action: _s(j['action']), entity: _s(j['entity']), data: _m(j['data']), createdAt: _d(j['created_at']));
}

class TrashItem {
  const TrashItem({required this.id, required this.table, required this.label, this.deletedAt, this.restoredAt});
  final String id;
  final String table;
  final String label;
  final DateTime? deletedAt;
  final DateTime? restoredAt;
  factory TrashItem.fromJson(Map<String, dynamic> j) =>
      TrashItem(id: _s(j['id']), table: _s(j['table_name']), label: _s(j['label']), deletedAt: _d(j['deleted_at']), restoredAt: _d(j['restored_at']));
}

const trashTables = {
  'clients': 'Cliente',
  'products': 'Producto',
  'quotes': 'Cotización',
  'expenses': 'Gasto',
  'payments': 'Cobro',
  'jobs': 'Trabajo',
  'invoices': 'Borrador de factura',
  'credit_ledger': 'Movimiento de fiado',
  'client_notes': 'Nota de cliente',
  'client_assets': 'Equipo de cliente',
  'cash_movements': 'Movimiento de caja',
};

class Coupon {
  const Coupon({required this.id, required this.code, required this.kind, required this.value, this.maxUses, this.uses = 0, this.expiresOn, this.active = true});
  final String id;
  final String code;
  final String kind;
  final double value;
  final int? maxUses;
  final int uses;
  final String? expiresOn;
  final bool active;
  factory Coupon.fromJson(Map<String, dynamic> j) => Coupon(
        id: _s(j['id']),
        code: _s(j['code']),
        kind: _s(j['kind']),
        value: _n(j['value']),
        maxUses: (j['max_uses'] as num?)?.toInt(),
        uses: (j['uses'] as num?)?.toInt() ?? 0,
        expiresOn: j['expires_on'] as String?,
        active: j['active'] != false,
      );
}

class LoyaltyBalance {
  const LoyaltyBalance({required this.clientId, required this.name, this.phone = '', required this.points});
  final String clientId;
  final String name;
  final String phone;
  final int points;
  factory LoyaltyBalance.fromJson(Map<String, dynamic> j) =>
      LoyaltyBalance(clientId: _s(j['client_id']), name: _s(j['client_name']), phone: _s(j['phone']), points: _n(j['points']).toInt());
}

class SellerRow {
  const SellerRow({required this.userId, required this.name, required this.count, required this.total, this.pct, required this.commission, this.goal});
  final String userId;
  final String name;
  final int count;
  final double total;
  final double? pct;
  final double commission;
  final double? goal;
  factory SellerRow.fromJson(Map<String, dynamic> j) => SellerRow(
        userId: _s(j['user_id']),
        name: _s(j['name']),
        count: _n(j['sales_count']).toInt(),
        total: _n(j['sales_total']),
        pct: _nn(j['commission_pct']),
        commission: _n(j['commission']),
        goal: _nn(j['goal']),
      );
}

class NoticeRow {
  const NoticeRow({required this.id, required this.app, required this.amount, this.payer = '', this.operation = '', this.status = 'nuevo', this.invoiceId, this.createdAt});
  final String id;
  final String app;
  final double amount;
  final String payer;
  final String operation;
  final String status;
  final String? invoiceId;
  final DateTime? createdAt;
  factory NoticeRow.fromJson(Map<String, dynamic> j) => NoticeRow(
        id: _s(j['id']),
        app: _s(j['app']),
        amount: _n(j['amount']),
        payer: _s(j['payer']),
        operation: _s(j['operation_code']),
        status: _s(j['status']),
        invoiceId: j['invoice_id'] as String?,
        createdAt: _d(j['created_at']),
      );
}

class ApiKeyRow {
  const ApiKeyRow({required this.id, required this.name, required this.prefix, required this.scopes, this.createdAt, this.lastUsedAt, this.revokedAt});
  final String id;
  final String name;
  final String prefix;
  final List<String> scopes;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;
  factory ApiKeyRow.fromJson(Map<String, dynamic> j) => ApiKeyRow(
        id: _s(j['id']),
        name: _s(j['name']),
        prefix: _s(j['prefix']),
        scopes: ((j['scopes'] ?? const []) as List).map((e) => e.toString()).toList(),
        createdAt: _d(j['created_at']),
        lastUsedAt: _d(j['last_used_at']),
        revokedAt: _d(j['revoked_at']),
      );
}

class WebhookRow {
  const WebhookRow({required this.id, required this.url, required this.secret, required this.events, required this.active, this.lastStatus});
  final String id;
  final String url;
  final String secret;
  final List<String> events;
  final bool active;
  final int? lastStatus;
  factory WebhookRow.fromJson(Map<String, dynamic> j) => WebhookRow(
        id: _s(j['id']),
        url: _s(j['url']),
        secret: _s(j['secret']),
        events: ((j['events'] ?? const []) as List).map((e) => e.toString()).toList(),
        active: j['active'] != false,
        lastStatus: (j['last_status'] as num?)?.toInt(),
      );
}

class SurveyRow {
  const SurveyRow({required this.token, this.invoiceId, this.score, this.comment = '', this.answeredAt, this.createdAt});
  final String token;
  final String? invoiceId;
  final int? score;
  final String comment;
  final DateTime? answeredAt;
  final DateTime? createdAt;
  factory SurveyRow.fromJson(Map<String, dynamic> j) => SurveyRow(
        token: _s(j['token']),
        invoiceId: j['invoice_id'] as String?,
        score: (j['score'] as num?)?.toInt(),
        comment: _s(j['comment']),
        answeredAt: _d(j['answered_at']),
        createdAt: _d(j['created_at']),
      );
}

class KitchenItem {
  const KitchenItem(this.description, this.quantity);
  final String description;
  final double quantity;
}

class KitchenOrder {
  const KitchenOrder({required this.id, required this.number, this.table = '', this.fulfillment = '', required this.status, this.client = '', this.notes = '', this.createdAt, this.items = const []});
  final String id;
  final String number;
  final String table;
  final String fulfillment;
  final String status; // nuevo | preparando | listo | entregado
  final String client;
  final String notes;
  final DateTime? createdAt;
  final List<KitchenItem> items;
  factory KitchenOrder.fromJson(Map<String, dynamic> j) => KitchenOrder(
        id: _s(j['id']),
        number: _s(j['number']),
        table: _s(j['table_label']),
        fulfillment: _s(j['fulfillment']),
        status: _s(j['kitchen_status']).isEmpty ? 'nuevo' : _s(j['kitchen_status']),
        client: _s(_m(j['clients'])['name']),
        notes: _s(j['notes']),
        createdAt: _d(j['created_at']),
        items: ((j['quote_items'] ?? const []) as List).map((e) {
          final m = _m(e);
          return KitchenItem(_s(m['description']), _n(m['quantity']));
        }).toList(),
      );
}

class BankLineRow {
  const BankLineRow({required this.id, required this.date, required this.description, required this.amount, this.reference = '', required this.status, this.invoiceId});
  final String id;
  final String date;
  final String description;
  final double amount;
  final String reference;
  final String status;
  final String? invoiceId;
  factory BankLineRow.fromJson(Map<String, dynamic> j) => BankLineRow(
        id: _s(j['id']),
        date: _s(j['line_date']),
        description: _s(j['description']),
        amount: _n(j['amount']),
        reference: _s(j['reference']),
        status: _s(j['status']),
        invoiceId: j['invoice_id'] as String?,
      );
}

/// Venta leída de una foto de cuaderno / nota / WhatsApp (POST /api/notebook).
class NotebookSale {
  const NotebookSale({required this.clientName, required this.clientDoc, required this.items, required this.pricesIncludeTax, required this.notes, required this.handwritten, required this.confidence});
  final String clientName;
  final String clientDoc;
  final List<({String description, double quantity, double unitPrice})> items;
  final bool pricesIncludeTax;
  final String notes;
  final bool handwritten;
  final double confidence;
  factory NotebookSale.fromJson(Map<String, dynamic> j) => NotebookSale(
        clientName: _s(j['client_name']),
        clientDoc: _s(j['client_doc']),
        items: ((j['items'] ?? const []) as List).map((e) {
          final m = _m(e);
          return (description: _s(m['description']), quantity: _n(m['quantity']), unitPrice: _n(m['unit_price']));
        }).toList(),
        pricesIncludeTax: j['prices_include_tax'] != false,
        notes: _s(j['notes']),
        handwritten: j['handwritten'] == true,
        confidence: _n(j['confidence']),
      );
}

/// Resultado de la consulta DNI/RUC (POST /api/lookup).
class DocLookup {
  const DocLookup({
    required this.kind,
    required this.number,
    required this.name,
    this.address = '',
    this.district = '',
    this.province = '',
    this.department = '',
    this.ubigeo = '',
    this.status = '',
    this.condition = '',
    this.tradeName = '',
    this.firstNames = '',
    this.lastNames = '',
    this.warning = '',
  });
  final String kind;
  final String number;
  final String name;
  final String address;
  final String district;
  final String province;
  final String department;
  final String ubigeo;
  final String status;
  final String condition;
  final String tradeName; // RUC: nombre comercial
  final String firstNames; // DNI
  final String lastNames; // DNI
  final String warning; // aviso del servidor si el RUC no está ACTIVO y HABIDO
  bool get rucActive => status.isEmpty || status == 'ACTIVO';
  bool get rucHabido => condition.isEmpty || condition == 'HABIDO';

  /// Aviso en lenguaje simple (el del servidor o, si es un servidor antiguo, uno calculado aquí).
  String get warningText {
    if (kind != 'ruc') return '';
    if (warning.isNotEmpty) return warning;
    if (!rucActive) return 'Ojo: este RUC figura como "$status" en SUNAT. Confirma con tu cliente antes de emitirle una factura.';
    if (!rucHabido) return 'Ojo: este RUC figura como "$condition" en SUNAT. Confirma la dirección con tu cliente antes de emitir.';
    return '';
  }

  String get fullAddress => [address, district, province, department].where((e) => e.trim().isNotEmpty && e.trim() != '-').join(', ');
  factory DocLookup.fromJson(Map<String, dynamic> j) => DocLookup(
        kind: _s(j['kind']),
        number: _s(j['number']),
        name: _s(j['name']),
        address: _s(j['address']),
        district: _s(j['district']),
        province: _s(j['province']),
        department: _s(j['department']),
        ubigeo: _s(j['ubigeo']),
        status: _s(j['status']),
        condition: _s(j['condition']),
        tradeName: _s(j['tradeName']),
        firstNames: _s(j['firstNames']),
        lastNames: _s(j['lastNames']),
        warning: _s(j['warning']),
      );
}
