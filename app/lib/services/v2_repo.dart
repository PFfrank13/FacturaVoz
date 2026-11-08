// Acceso a datos de la v2.0. Todo pasa por RLS: la base de datos decide qué ve y qué cambia cada rol.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import '../logic/pricing.dart';
import '../models.dart';
import '../finance.dart' show addDays;
import '../growth.dart' show fillDailySeries;
import '../models_v2.dart';
import 'boot_cache.dart';
import 'repo.dart';

class V2Repo {
  static SupabaseClient get _db => Supabase.instance.client;

  static String get org {
    final o = Repo.activeOrgId;
    if (o == null) throw AppException('Elige una empresa primero.');
    return o;
  }

  static String get uid {
    final u = _db.auth.currentUser;
    if (u == null) throw AppException('Sesión caducada');
    return u.id;
  }

  static List<Map<String, dynamic>> _rows(dynamic r) => (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// ¿El error es porque falta ejecutar una migración v2? (la pantalla muestra cómo arreglarlo en vez de fallar).
  static bool missing(Object e) =>
      e is PostgrestException && (e.code == '42P01' || e.code == 'PGRST205' || e.code == 'PGRST202' || e.code == '42883' || e.code == '42703' || e.code == 'PGRST204');

  static String missingHint(Object e) => missing(e) ? 'Falta ejecutar las migraciones v2.0 (20261104 a 20261112) en Supabase.' : friendly(e);

  // ═══════════ Configuración del negocio ═══════════
  static OrgSettings? _settingsCache;
  static String? _settingsFor;

  /// Avisa a la app (shell, hubs) cuando cambia la configuración del negocio (modo simple, módulos…).
  static final ValueNotifier<int> changed = ValueNotifier(0);

  /// true cuando la tabla org_settings respondió (migraciones v2 aplicadas).
  static bool ready = false;

  static Future<OrgSettings> settings({bool refresh = false}) async {
    if (!refresh && _settingsCache != null && _settingsFor == Repo.activeOrgId) return _settingsCache!;
    try {
      final r = await _db.from('org_settings').select().eq('org_id', org).maybeSingle();
      _settingsCache = r == null ? OrgSettings() : OrgSettings.fromJson(Map<String, dynamic>.from(r));
      ready = true;
      if (r != null && Repo.activeOrgId != null) BootCache.putSettings(Repo.activeOrgId!, Map<String, dynamic>.from(r));
    } catch (_) {
      _settingsCache = OrgSettings();
      ready = false;
    }
    _settingsFor = Repo.activeOrgId;
    return _settingsCache!;
  }

  static Future<void> saveSettings(OrgSettings s, {Map<String, dynamic> extra = const {}}) async {
    await _db.from('org_settings').upsert({'org_id': org, ...s.toRow(), ...extra, 'updated_at': DateTime.now().toUtc().toIso8601String()});
    _settingsCache = s;
    _settingsFor = Repo.activeOrgId;
    changed.value++;
  }

  static Future<void> saveSettingsFields(Map<String, dynamic> fields) async {
    final s = await settings();
    await _db.from('org_settings').upsert({'org_id': org, ...s.toRow(), ...fields});
    _settingsCache = null;
    changed.value++;
  }

  static void forgetSettings() => _settingsCache = null;

  /// Configuración ya cargada de la empresa activa (null si no hay): permite abrir sin esperar a la red.
  static OrgSettings? get cachedSettings => _settingsCache != null && _settingsFor == Repo.activeOrgId ? _settingsCache : null;

  /// Arranque instantáneo: deja lista la última configuración guardada.
  static void seedSettings(String org, Map<String, dynamic> raw) {
    try {
      _settingsCache = OrgSettings.fromJson(raw);
      _settingsFor = org;
      ready = true;
    } catch (_) {}
  }

  // ═══════════ Clientes (ficha 360) ═══════════
  static Future<List<ClientProfile>> clients({String q = ''}) async {
    var b = _db.from('clients').select(ClientProfile.columns).eq('org_id', org);
    final t = q.trim().replaceAll(RegExp(r'[%,()]'), ' ');
    if (t.isNotEmpty) b = b.or('name.ilike.%$t%,tax_id.ilike.%$t%,phone.ilike.%$t%');
    final r = await b.order('name').limit(2000);
    return _rows(r).map(ClientProfile.fromJson).toList();
  }

  static Future<ClientProfile?> client(String id) async {
    final r = await _db.from('clients').select(ClientProfile.columns).eq('id', id).maybeSingle();
    return r == null ? null : ClientProfile.fromJson(Map<String, dynamic>.from(r));
  }

  static Future<ClientProfile?> clientByName(String name) async {
    final r = await _db.from('clients').select(ClientProfile.columns).eq('org_id', org).ilike('name', name.trim()).limit(1).maybeSingle();
    return r == null ? null : ClientProfile.fromJson(Map<String, dynamic>.from(r));
  }

  static Future<String> saveClient(ClientProfile c, {bool isNew = false}) async {
    if (isNew) {
      final r = await _db.from('clients').insert({...c.toRow(), 'org_id': org, 'user_id': uid}).select('id').single();
      return r['id'] as String;
    }
    await _db.from('clients').update(c.toRow()).eq('id', c.id);
    return c.id;
  }

  static Future<void> deleteClient(String id) => _db.from('clients').delete().eq('id', id);

  static Future<List<InvoiceRecord>> clientInvoices(String clientId) async {
    final r = await _db
        .from('invoices')
        .select('id, number, issue_date, status, currency, tax_rate, notes, due_date, clients(name, tax_id, doc_type, email), fiscal_documents(status, series, correlative, doc_type), invoice_items(description, quantity, unit_price, position), payments(amount)')
        .eq('client_id', clientId)
        .order('issue_date', ascending: false)
        .limit(200);
    return _rows(r).map(InvoiceRecord.fromJson).toList();
  }

  static Future<List<Map<String, dynamic>>> clientQuotes(String clientId) async =>
      _rows(await _db.from('quotes').select('id, number, issue_date, status, currency, tax_rate, quote_items(quantity, unit_price)').eq('client_id', clientId).order('issue_date', ascending: false).limit(100));

  static Future<List<ClientNote>> notes(String clientId) async =>
      _rows(await _db.from('client_notes').select('id, kind, body, created_at').eq('client_id', clientId).order('created_at', ascending: false).limit(200)).map(ClientNote.fromJson).toList();

  static Future<void> addNote(String clientId, String body, {String kind = 'nota'}) =>
      _db.from('client_notes').insert({'org_id': org, 'client_id': clientId, 'kind': kind, 'body': body.trim()});

  static Future<List<ClientAsset>> assets(String clientId) async =>
      _rows(await _db.from('client_assets').select().eq('client_id', clientId).order('created_at', ascending: false)).map(ClientAsset.fromJson).toList();

  static Future<void> addAsset({required String clientId, String? jobId, required String name, String model = '', String serial = '', String? installedOn, String? warrantyUntil, String notes = ''}) =>
      _db.from('client_assets').insert({
        'org_id': org,
        'client_id': clientId,
        'job_id': jobId,
        'name': name.trim(),
        'model': model.trim().isEmpty ? null : model.trim(),
        'serial': serial.trim().isEmpty ? null : serial.trim(),
        'installed_on': installedOn,
        'warranty_until': warrantyUntil,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      });

  static Future<void> deleteAsset(String id) => _db.from('client_assets').delete().eq('id', id);

  // ═══════════ Trabajos y agenda ═══════════
  static Future<List<Job>> jobs({String? clientId, DateTime? from, DateTime? to, bool openOnly = false, int limit = 500}) async {
    var b = _db.from('jobs').select(Job.columns).eq('org_id', org);
    if (clientId != null) b = b.eq('client_id', clientId);
    if (from != null) b = b.gte('scheduled_at', from.toUtc().toIso8601String());
    if (to != null) b = b.lt('scheduled_at', to.toUtc().toIso8601String());
    if (openOnly) b = b.isFilter('done_at', null);
    final r = from != null ? await b.order('scheduled_at').limit(limit) : await b.order('position').order('created_at', ascending: false).limit(limit);
    return _rows(r).map(Job.fromJson).toList();
  }

  static Future<Job?> job(String id) async {
    final r = await _db.from('jobs').select(Job.columns).eq('id', id).maybeSingle();
    return r == null ? null : Job.fromJson(Map<String, dynamic>.from(r));
  }

  static Future<String> saveJob(Job j) async {
    if (j.id == null) {
      final r = await _db.from('jobs').insert({...j.toRow(), 'org_id': org}).select('id').single();
      return r['id'] as String;
    }
    await _db.from('jobs').update(j.toRow()).eq('id', j.id!);
    return j.id!;
  }

  static Future<void> setJobStatus(String id, String status) => _db.from('jobs').update({'status': status}).eq('id', id);

  static Future<void> moveJob(String id, String status, int position) => _db.from('jobs').update({'status': status, 'position': position}).eq('id', id);

  static Future<void> deleteJob(String id) => _db.from('jobs').delete().eq('id', id);

  static Future<List<JobEvent>> jobEvents(String jobId) async =>
      _rows(await _db.from('job_events').select('from_status, to_status, created_at').eq('job_id', jobId).order('created_at')).map(JobEvent.fromJson).toList();

  static Future<List<JobMaterial>> materials(String jobId) async =>
      _rows(await _db.from('job_materials').select().eq('job_id', jobId).order('created_at')).map(JobMaterial.fromJson).toList();

  static Future<void> addMaterial(String jobId, {String? productId, required String description, required double quantity, double unitPrice = 0}) =>
      _db.from('job_materials').insert({'job_id': jobId, 'org_id': org, 'product_id': productId, 'description': description.trim(), 'quantity': quantity, 'unit_price': unitPrice});

  static Future<void> deleteMaterial(String id) => _db.from('job_materials').delete().eq('id', id);

  /// Descuenta del inventario los materiales aún no descontados. Devuelve cuántos.
  static Future<int> consumeMaterials(String jobId) async => ((await _db.rpc('job_consume_materials', params: {'p_job': jobId})) as num?)?.toInt() ?? 0;

  static Future<List<JobMilestone>> milestones(String jobId) async =>
      _rows(await _db.from('job_milestones').select().eq('job_id', jobId).order('position')).map(JobMilestone.fromJson).toList();

  static Future<void> addMilestone(String jobId, {required String title, required double amount, String? dueDate, int position = 0}) =>
      _db.from('job_milestones').insert({'job_id': jobId, 'org_id': org, 'title': title.trim(), 'amount': amount, 'due_date': dueDate, 'position': position});

  static Future<void> deleteMilestone(String id) => _db.from('job_milestones').delete().eq('id', id);

  /// Factura un hito en un toque (crea el borrador de factura). Devuelve el id de la factura.
  static Future<String> invoiceMilestone(String id) async => (await _db.rpc('milestone_invoice', params: {'p_milestone': id})) as String;

  // ═══════════ Fotos y archivos (Storage privado por empresa) ═══════════
  static const bucket = 'org-media';

  /// Sube una imagen ya comprimida. folder: logo | productos | trabajos | clientes. Devuelve la ruta guardada.
  static Future<String> upload(String folder, Uint8List bytes, {String ext = 'jpg', String? fixedName}) async {
    final name = fixedName ?? '${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.$ext';
    final path = '$org/$folder/$name';
    await _db.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg', upsert: true));
    return path;
  }

  // A3: el mismo enlace firmado se reutiliza mientras sea válido → la imagen sale de la caché y no se descarga de nuevo.
  static final Map<String, (String, DateTime)> _signed = {};

  static Future<String?> signedUrl(String? path, {int seconds = 3600}) async {
    if (path == null || path.isEmpty) return null;
    final hit = _signed[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    try {
      final url = await _db.storage.from(bucket).createSignedUrl(path, seconds);
      if (_signed.length > 500) _signed.clear();
      _signed[path] = (url, DateTime.now().add(Duration(seconds: seconds - 120)));
      return url;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> download(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _db.storage.from(bucket).download(path);
    } catch (_) {
      return null;
    }
  }

  static Future<List<MediaFile>> media({String? jobId, String? clientId}) async {
    var b = _db.from('media_files').select('id, path, kind, caption').eq('org_id', org);
    if (jobId != null) b = b.eq('job_id', jobId);
    if (clientId != null) b = b.eq('client_id', clientId);
    final list = _rows(await b.order('created_at', ascending: false).limit(100)).map(MediaFile.fromJson).toList();
    for (final m in list) {
      m.url = await signedUrl(m.path);
    }
    return list;
  }

  static Future<void> addMedia({String? jobId, String? clientId, required String path, String kind = 'foto', String caption = ''}) =>
      _db.from('media_files').insert({'org_id': org, 'job_id': jobId, 'client_id': clientId, 'path': path, 'kind': kind, 'caption': caption.trim().isEmpty ? null : caption.trim()});

  // ═══════════ Avisos del día ═══════════
  static Future<List<DailyAlert>> dailyAlerts() async {
    try {
      final r = await _db.rpc('daily_alerts', params: {'p_org': org});
      return (r as List).map((e) => DailyAlert.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return const [];
    }
  }

  // ═══════════ Equipo ═══════════
  static Future<List<TeamMember>> team() async => _rows(await _db.rpc('team_members', params: {'p_org': org})).map(TeamMember.fromJson).toList();

  static Future<List<TeamInvite>> invites() async =>
      _rows(await _db.from('org_invites').select('id, email, role, staff_role, display_name').eq('org_id', org).isFilter('accepted_at', null).order('created_at')).map(TeamInvite.fromJson).toList();

  /// 'added' (ya tenía cuenta) | 'invited' (entrará con "Iniciar con Empresa")
  static Future<String> invite({required String email, required String staffRole, bool admin = false, String name = ''}) async =>
      (await _db.rpc('invite_member', params: {'p_org': org, 'p_email': email.trim(), 'p_staff_role': staffRole, 'p_admin': admin, 'p_name': name.trim().isEmpty ? null : name.trim()})) as String;

  static Future<void> cancelInvite(String id) => _db.from('org_invites').delete().eq('id', id);

  static Future<void> setRole(String userId, {required String? staffRole, bool admin = false, double? commission, double? goal, String name = ''}) => _db.rpc('set_member_role', params: {
        'p_org': org,
        'p_user': userId,
        'p_staff_role': staffRole,
        'p_admin': admin,
        'p_commission': commission,
        'p_goal': goal,
        'p_name': name.trim().isEmpty ? null : name.trim(),
      });

  static Future<int> claimInvites() async {
    try {
      return ((await _db.rpc('claim_invites')) as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<SellerRow>> sellerRanking(String from, String toExclusive) async =>
      _rows(await _db.rpc('seller_ranking', params: {'p_org': org, 'p_from': from, 'p_to': toExclusive})).map(SellerRow.fromJson).toList();

  // ═══════════ Ventas (definición única) ═══════════
  static Future<Map<String, dynamic>?> salesSummary(String from, String toExclusive, String currency) async {
    try {
      final r = await _db.rpc('sales_summary', params: {'p_org': org, 'p_from': from, 'p_to': toExclusive, 'p_currency': currency});
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }

  /// Ventas de los últimos [days] días (último = hoy), calculadas en el servidor con la regla única de ventas.
  static Future<List<double>?> salesDaily(String today, String currency, {int days = 14}) async {
    try {
      final from = addDays(today, -(days - 1));
      final r = await _db.rpc('sales_series', params: {'p_org': org, 'p_from': from, 'p_to': addDays(today, 1), 'p_currency': currency, 'p_bucket': 'day'});
      return fillDailySeries(_rows(r), today: today, days: days);
    } catch (_) {
      return null;
    }
  }

  // ═══════════ Fiados ═══════════
  static Future<List<CreditBalance>> creditBalances() async => _rows(await _db.rpc('credit_balances', params: {'p_org': org})).map(CreditBalance.fromJson).toList();

  static Future<List<CreditMove>> creditMoves(String clientId) async =>
      _rows(await _db.from('credit_ledger').select('id, kind, amount, description, due_date, method, created_at').eq('client_id', clientId).order('created_at', ascending: false).limit(300)).map(CreditMove.fromJson).toList();

  static Future<void> addCredit({required String clientId, required String kind, required double amount, String description = '', String? dueDate, String? method}) => _db.from('credit_ledger').insert({
        'org_id': org,
        'client_id': clientId,
        'kind': kind,
        'amount': round2(amount),
        'description': description.trim().isEmpty ? null : description.trim(),
        'due_date': kind == 'cargo' ? dueDate : null,
        'method': kind == 'abono' ? (method ?? 'efectivo') : null,
        'user_id': uid,
      });

  static Future<void> deleteCredit(String id) => _db.from('credit_ledger').delete().eq('id', id);

  // ═══════════ Caja y cierre ═══════════
  static Future<List<CashMove>> cashMoves(String day) async =>
      _rows(await _db.from('cash_movements').select('id, kind, amount, method, note, created_at').eq('org_id', org).eq('day', day).order('created_at')).map(CashMove.fromJson).toList();

  static Future<void> addCashMove({required String kind, required double amount, String method = 'efectivo', String note = ''}) =>
      _db.from('cash_movements').insert({'org_id': org, 'kind': kind, 'amount': round2(amount), 'method': method, 'note': note.trim().isEmpty ? null : note.trim(), 'user_id': uid});

  static Future<DaySummary> daySummary(String day) async {
    final r = await _db.rpc('day_summary', params: {'p_org': org, 'p_day': day});
    return DaySummary(Map<String, dynamic>.from(r as Map));
  }

  static Future<Map<String, dynamic>?> dayClosing(String day) async {
    final r = await _db.from('day_closings').select('counted_cash, expected_cash, difference, note, created_at').eq('org_id', org).eq('day', day).maybeSingle();
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  // ═══════════ Antifraude ═══════════
  static Future<List<OwnerAlert>> alerts({int limit = 100}) async =>
      _rows(await _db.from('owner_alerts').select().eq('org_id', org).order('created_at', ascending: false).limit(limit)).map(OwnerAlert.fromJson).toList();

  static Stream<List<OwnerAlert>> watchAlerts() => _db
      .from('owner_alerts')
      .stream(primaryKey: ['id'])
      .eq('org_id', org)
      .order('created_at')
      .limit(50)
      .map((rows) => rows.map((r) => OwnerAlert.fromJson(Map<String, dynamic>.from(r))).toList()); // order() del stream es descendente por defecto

  static Future<void> markAlertsRead() => _db.from('owner_alerts').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('org_id', org).isFilter('read_at', null);

  static Future<List<AuditEntry>> audit({int limit = 200}) async =>
      _rows(await _db.from('audit_log').select('id, action, entity, data, created_at').eq('org_id', org).order('id', ascending: false).limit(limit)).map(AuditEntry.fromJson).toList();

  /// null = bitácora íntegra; si no, el número de la primera fila alterada.
  static Future<int?> auditVerify() async => ((await _db.rpc('audit_verify', params: {'p_org': org})) as num?)?.toInt();

  static Future<Map<String, dynamic>> pinStatus() async {
    try {
      final r = await _db.rpc('pin_status', params: {'p_org': org});
      return r is Map ? Map<String, dynamic>.from(r) : const {'enabled': false, 'ok': true};
    } catch (_) {
      return const {'enabled': false, 'ok': true};
    }
  }

  static Future<void> setPin(String? pin) => _db.rpc('set_admin_pin', params: {'p_org': org, 'p_pin': pin});
  static Future<bool> verifyPin(String pin) async => (await _db.rpc('verify_admin_pin', params: {'p_org': org, 'p_pin': pin})) == true;

  // ═══════════ Papelera ═══════════
  static Future<List<TrashItem>> trash() async =>
      _rows(await _db.from('trash').select('id, table_name, label, deleted_at, restored_at').eq('org_id', org).isFilter('restored_at', null).order('deleted_at', ascending: false).limit(300)).map(TrashItem.fromJson).toList();

  static Future<String> restore(String trashId) async => (await _db.rpc('restore_trash', params: {'p_id': trashId})) as String;

  /// Lo último que se borró de una fila (para el botón "Deshacer").
  static Future<String?> lastTrashFor(String rowId) async {
    final r = await _db.from('trash').select('id').eq('row_id', rowId).isFilter('restored_at', null).order('deleted_at', ascending: false).limit(1).maybeSingle();
    return r?['id'] as String?;
  }

  // ═══════════ Precios, cupones y fidelización ═══════════
  static Future<List<Promo>> promotions() async => _rows(await _db.from('promotions').select().eq('org_id', org).order('created_at', ascending: false)).map(Promo.fromJson).toList();

  static Future<void> savePromo({String? id, required String name, required String kind, required double value, List<String> productIds = const [], double? minQty, String? startsOn, String? endsOn, bool active = true}) async {
    final row = {'name': name.trim(), 'kind': kind, 'value': value, 'product_ids': productIds, 'min_qty': minQty, 'starts_on': startsOn, 'ends_on': endsOn, 'active': active};
    if (id == null) {
      await _db.from('promotions').insert({...row, 'org_id': org});
    } else {
      await _db.from('promotions').update(row).eq('id', id);
    }
  }

  static Future<void> deletePromo(String id) => _db.from('promotions').delete().eq('id', id);

  static Future<List<Coupon>> coupons() async => _rows(await _db.from('coupons').select().eq('org_id', org).order('created_at', ascending: false)).map(Coupon.fromJson).toList();

  static Future<void> saveCoupon({required String code, required String kind, required double value, int? maxUses, String? expiresOn}) =>
      _db.from('coupons').insert({'org_id': org, 'code': code.trim().toUpperCase(), 'kind': kind, 'value': value, 'max_uses': maxUses, 'expires_on': expiresOn});

  static Future<void> setCouponActive(String id, bool active) => _db.from('coupons').update({'active': active}).eq('id', id);

  static Future<Map<String, dynamic>> useCoupon(String code) async => Map<String, dynamic>.from((await _db.rpc('use_coupon', params: {'p_org': org, 'p_code': code})) as Map);

  static Future<List<LoyaltyBalance>> loyalty() async => _rows(await _db.rpc('loyalty_balances', params: {'p_org': org})).map(LoyaltyBalance.fromJson).toList();

  static Future<void> redeemPoints(String clientId, int points, String reason) =>
      _db.from('loyalty_ledger').insert({'org_id': org, 'client_id': clientId, 'points': -points.abs(), 'reason': reason.trim().isEmpty ? 'Canje' : reason.trim()});

  // ═══════════ Conciliación bancaria ═══════════
  static Future<List<BankLineRow>> bankLines({bool pendingOnly = true}) async {
    var b = _db.from('bank_lines').select('id, line_date, description, amount, reference, status, invoice_id').eq('org_id', org);
    if (pendingOnly) b = b.eq('status', 'pendiente');
    return _rows(await b.order('line_date', ascending: false).limit(1000)).map(BankLineRow.fromJson).toList();
  }

  /// Inserta las líneas nuevas (las repetidas se ignoran por su huella). Devuelve cuántas entraron.
  static Future<int> importBankLines(List<Map<String, dynamic>> rows, String batch) async {
    if (rows.isEmpty) return 0;
    final r = await _db
        .from('bank_lines')
        .upsert([for (final x in rows) {...x, 'org_id': org, 'batch': batch}], onConflict: 'org_id,fingerprint', ignoreDuplicates: true)
        .select('id');
    return (r as List).length;
  }

  static Future<void> setBankLine(String id, {required String status, String? invoiceId, String? paymentId}) =>
      _db.from('bank_lines').update({'status': status, 'invoice_id': invoiceId, 'payment_id': paymentId}).eq('id', id);

  // ═══════════ Avisos de pago ═══════════
  static Future<List<NoticeRow>> notices() async =>
      _rows(await _db.from('payment_notices').select().eq('org_id', org).order('created_at', ascending: false).limit(200)).map(NoticeRow.fromJson).toList();

  static Future<String> addNotice({required String app, required double amount, String payer = '', String operation = '', String raw = ''}) async {
    final r = await _db
        .from('payment_notices')
        .insert({'org_id': org, 'app': app, 'amount': amount, 'payer': payer.isEmpty ? null : payer, 'operation_code': operation.isEmpty ? null : operation, 'raw_text': raw.isEmpty ? null : raw})
        .select('id')
        .single();
    return r['id'] as String;
  }

  static Future<void> setNotice(String id, {required String status, String? invoiceId}) => _db.from('payment_notices').update({'status': status, 'invoice_id': invoiceId}).eq('id', id);

  // ═══════════ Portal, encuestas, API ═══════════
  static Future<String> portalToken(String invoiceId) async => (await _db.rpc('invoice_portal_link', params: {'p_invoice': invoiceId})) as String;
  static Future<String> surveyToken(String invoiceId) async => (await _db.rpc('survey_link', params: {'p_invoice': invoiceId})) as String;

  static Future<List<SurveyRow>> surveys() async =>
      _rows(await _db.from('surveys').select('token, invoice_id, score, comment, answered_at, created_at').eq('org_id', org).order('created_at', ascending: false).limit(300)).map(SurveyRow.fromJson).toList();

  static Future<List<ApiKeyRow>> apiKeys() async => _rows(await _db.from('org_api_keys').select().eq('org_id', org).order('created_at', ascending: false)).map(ApiKeyRow.fromJson).toList();
  static Future<String> createApiKey(String name, List<String> scopes) async => (await _db.rpc('create_api_key', params: {'p_org': org, 'p_name': name, 'p_scopes': scopes})) as String;
  static Future<void> revokeApiKey(String id) => _db.rpc('revoke_api_key', params: {'p_id': id});

  static Future<List<WebhookRow>> webhooks() async => _rows(await _db.from('org_webhooks').select().eq('org_id', org).order('created_at')).map(WebhookRow.fromJson).toList();
  static Future<void> addWebhook(String url, List<String> events) => _db.from('org_webhooks').insert({'org_id': org, 'url': url.trim(), 'events': events});
  static Future<void> setWebhookActive(String id, bool active) => _db.from('org_webhooks').update({'active': active}).eq('id', id);
  static Future<void> deleteWebhook(String id) => _db.from('org_webhooks').delete().eq('id', id);

  // ═══════════ Comandas persistentes desde caja (migración 20261122) ═══════════
  /// RPC transaccional con idempotencia por requestId. No registrar como venta
  /// ni asumir éxito hasta recibir un identificador válido del servidor.
  static Future<({String id, String number})> createPosKitchenOrder({
    required String requestId,
    required String table,
    required double taxRate,
    required String currency,
    required List<Map<String, dynamic>> items,
  }) async {
    final r = await _db.rpc('create_pos_kitchen_order', params: {
      'p_org': org,
      'p_request_id': requestId,
      'p_table': table.trim().isEmpty ? null : table.trim(),
      'p_tax_rate': taxRate,
      'p_currency': currency,
      'p_items': items,
    });
    final rows = _rows(r);
    if (rows.isEmpty || rows.first['quote_id'] == null) {
      throw AppException('Supabase no devolvió el pedido de cocina.');
    }
    return (id: rows.first['quote_id'] as String, number: rows.first['quote_number'] as String);
  }

  static Future<void> linkPosKitchenInvoice(String quoteId, String invoiceId) =>
      _db.rpc('link_pos_kitchen_invoice', params: {'p_quote': quoteId, 'p_invoice': invoiceId});

  // ═══════════ Comandas (carta digital / pedidos web) ═══════════
  static Future<List<KitchenOrder>> kitchen() async => _rows(await _db
          .from('quotes')
          .select('id, number, table_label, fulfillment, kitchen_status, notes, created_at, clients(name), quote_items(description, quantity, kitchen_note, position)')
          .eq('org_id', org)
          .inFilter('kitchen_status', ['nuevo', 'preparando', 'listo'])
          .order('created_at')
          .limit(100))
      .map(KitchenOrder.fromJson)
      .toList();

  static Stream<List<Map<String, dynamic>>> watchQuotes() => _db.from('quotes').stream(primaryKey: ['id']).eq('org_id', org).order('created_at').limit(50);

  static Future<void> setKitchenStatus(String quoteId, String status) => _db.from('quotes').update({'kitchen_status': status}).eq('id', quoteId);

  // ═══════════ Productos (campos de tienda) ═══════════
  static Future<Map<String, dynamic>?> productExtra(String id) async {
    try {
      final r = await _db.from('products').select('barcode, image_path, category, description, wholesale_price, wholesale_min_qty, prep_area, featured').eq('id', id).maybeSingle();
      return r == null ? null : Map<String, dynamic>.from(r);
    } catch (_) {
      return null;
    }
  }

  /// Campos v2 de TODOS los productos (código de barras, categoría, foto, precio por mayor) en una sola consulta.
  static Future<Map<String, Map<String, dynamic>>> productExtras() async {
    try {
      final r = await _db.from('products').select('id, barcode, image_path, category, wholesale_price, wholesale_min_qty, featured').eq('org_id', org).limit(2000);
      return {for (final x in _rows(r)) x['id'] as String: x};
    } catch (_) {
      return const {};
    }
  }

  static Future<void> saveProductExtra(String id, Map<String, dynamic> fields) => _db.from('products').update(fields).eq('id', id);

  static Future<Product?> productByBarcode(String code) async {
    final r = await _db.from('products').select('id, name, unit_price, unit, active, stock, reorder_point, unit_cost, in_store').eq('org_id', org).eq('barcode', code.trim()).maybeSingle();
    return r == null ? null : Product.fromJson(Map<String, dynamic>.from(r));
  }

  /// Tipo de cambio de una venta en dólares (columna invoices.exchange_rate, migración 20261109).
  static Future<void> setExchangeRate(String invoiceId, double rate) => _db.from('invoices').update({'exchange_rate': rate}).eq('id', invoiceId);

  // ═══════════ Marca (logo, plantilla PDF, ancho de ticket) ═══════════
  static Future<Map<String, dynamic>> branding() async {
    try {
      final r = await _db.from('organizations').select('logo_path, pdf_template, ticket_width, brand_color').eq('id', org).maybeSingle();
      return r == null ? const {} : Map<String, dynamic>.from(r);
    } catch (_) {
      return const {};
    }
  }

  static Future<void> saveBranding(Map<String, dynamic> fields) async {
    final r = await _db.from('organizations').update(fields).eq('id', org).select('id');
    if ((r as List).isEmpty) throw AppException('Solo el propietario o un administrador puede cambiar la marca.');
  }
}
