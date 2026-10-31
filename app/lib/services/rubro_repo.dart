// Datos de las funciones propias de cada rubro (migración 20261115_v3_rubros.sql).
// Todo pasa por la sesión del usuario: la base aplica RLS y permisos por rol.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'repo.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _org => Repo.activeOrgId ?? '';
double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class ServicePackage {
  ServicePackage(this.id, this.clientId, this.clientName, this.name, this.total, this.used, this.price, this.expiresOn);
  final String id;
  final String clientId;
  final String clientName;
  final String name;
  final int total;
  final int used;
  final double? price;
  final String? expiresOn;
  int get left => total - used;
  bool expired(String today) => expiresOn != null && expiresOn!.compareTo(today) < 0;
  factory ServicePackage.fromJson(Map<String, dynamic> j) => ServicePackage(
        j['id'] as String,
        j['client_id'] as String,
        ((j['clients'] as Map?)?['name'] ?? '—') as String,
        j['name'] as String,
        (j['sessions_total'] as num).toInt(),
        (j['sessions_used'] as num).toInt(),
        j['price'] == null ? null : _n(j['price']),
        j['expires_on'] as String?,
      );
}

class Reminder {
  Reminder(this.id, this.clientId, this.clientName, this.clientPhone, this.dueOn, this.title, this.note, this.assetName);
  final String id;
  final String clientId;
  final String clientName;
  final String clientPhone;
  final String dueOn;
  final String title;
  final String note;
  final String assetName;
  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        j['id'] as String,
        j['client_id'] as String,
        ((j['clients'] as Map?)?['name'] ?? '—') as String,
        ((j['clients'] as Map?)?['phone'] ?? '') as String,
        j['due_on'] as String,
        j['title'] as String,
        (j['note'] ?? '') as String,
        ((j['client_assets'] as Map?)?['name'] ?? '') as String,
      );
}

class PrivateNote {
  PrivateNote(this.id, this.body, this.createdAt, this.mine);
  final String id;
  final String body;
  final DateTime createdAt;
  final bool mine;
}

class VehicleHit {
  VehicleHit(this.assetId, this.clientId, this.clientName, this.clientPhone, this.name, this.plate, this.model);
  final String assetId;
  final String clientId;
  final String clientName;
  final String clientPhone;
  final String name;
  final String plate;
  final String model;
}

class RubroRepo {
  // ───── Paquetes ─────
  static Future<List<ServicePackage>> packages() async => [
        for (final r in await _db
            .from('service_packages')
            .select('id, client_id, name, sessions_total, sessions_used, price, expires_on, clients(name)')
            .eq('org_id', _org)
            .order('created_at', ascending: false)
            .limit(300))
          ServicePackage.fromJson(Map<String, dynamic>.from(r))
      ];

  static Future<void> addPackage({required String clientId, required String name, required int sessions, double? price, String? expiresOn}) =>
      _db.from('service_packages').insert({'org_id': _org, 'client_id': clientId, 'name': name.trim(), 'sessions_total': sessions, 'price': price, 'expires_on': expiresOn});

  static Future<int> useSession(String id) async => ((await _db.rpc('use_package_session', params: {'p_package': id})) as num).toInt();

  // ───── Recordatorios de volver ─────
  static Future<List<Reminder>> reminders({int days = 30}) async => [
        for (final r in await _db
            .from('service_reminders')
            .select('id, client_id, due_on, title, note, clients(name, phone), client_assets(name)')
            .eq('org_id', _org)
            .isFilter('done_at', null)
            .lte('due_on', todayIso(DateTime.now().add(Duration(days: days))))
            .order('due_on')
            .limit(300))
          Reminder.fromJson(Map<String, dynamic>.from(r))
      ];

  static Future<void> addReminder({required String clientId, required String dueOn, required String title, String note = '', String? assetId}) =>
      _db.from('service_reminders').insert({'org_id': _org, 'client_id': clientId, 'due_on': dueOn, 'title': title.trim(), 'note': note.trim().isEmpty ? null : note.trim(), 'asset_id': assetId});

  static Future<void> doneReminder(String id) => _db.from('service_reminders').update({'done_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  // ───── Historial privado ─────
  static Future<List<PrivateNote>> privateNotes(String clientId) async {
    final me = _db.auth.currentUser?.id;
    return [
      for (final r in await _db.from('private_notes').select('id, body, created_at, author_id').eq('client_id', clientId).order('created_at', ascending: false).limit(200))
        PrivateNote(r['id'] as String, r['body'] as String, DateTime.parse(r['created_at'] as String).toLocal(), r['author_id'] == me)
    ];
  }

  static Future<void> addPrivateNote(String clientId, String body) => _db.from('private_notes').insert({'org_id': _org, 'client_id': clientId, 'body': body.trim()});
  static Future<void> deletePrivateNote(String id) => _db.from('private_notes').delete().eq('id', id);

  // ───── Placas (taller): vehículos = equipos del cliente con la placa en "serie" ─────
  static String normPlate(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static Future<List<VehicleHit>> findPlate(String q) async {
    final k = normPlate(q);
    if (k.length < 2) return const [];
    final rows = await _db
        .from('client_assets')
        .select('id, client_id, name, model, serial, clients(name, phone)')
        .eq('org_id', _org)
        .ilike('serial', '%${k.length > 3 ? '${k.substring(0, 3)}%${k.substring(3)}' : k}%')
        .limit(30);
    return [
      for (final r in rows)
        VehicleHit(r['id'] as String, r['client_id'] as String, ((r['clients'] as Map?)?['name'] ?? '—') as String, ((r['clients'] as Map?)?['phone'] ?? '') as String,
            r['name'] as String, (r['serial'] ?? '') as String, (r['model'] ?? '') as String)
    ].where((h) => normPlate(h.plate).contains(k)).toList();
  }

  // ───── Gastos por obra ─────
  static Future<Map<String, double>> expensesByJob() async {
    final out = <String, double>{};
    final rows = await _db.from('expenses').select('job_id, total').eq('org_id', _org).not('job_id', 'is', null).limit(5000);
    for (final r in rows) {
      final k = r['job_id'] as String;
      out[k] = round2((out[k] ?? 0) + _n(r['total']));
    }
    return out;
  }

  /// Gastos de los últimos 120 días que aún no están asignados a ninguna obra.
  static Future<List<Map<String, dynamic>>> unassignedExpenses() async => [
        for (final r in await _db
            .from('expenses')
            .select('id, spent_on, description, supplier_name, total, currency')
            .eq('org_id', _org)
            .isFilter('job_id', null)
            .gte('spent_on', todayIso(DateTime.now().subtract(const Duration(days: 120))))
            .order('spent_on', ascending: false)
            .limit(100))
          Map<String, dynamic>.from(r)
      ];

  static Future<void> setExpenseJob(String expenseId, String? jobId) => _db.from('expenses').update({'job_id': jobId}).eq('id', expenseId);

  /// Hitos de todas las obras (una consulta).
  static Future<List<Map<String, dynamic>>> allMilestones() async =>
      [for (final r in await _db.from('job_milestones').select('job_id, amount, status').eq('org_id', _org).limit(5000)) Map<String, dynamic>.from(r)];

  // ───── Estado del servicio del abonado (corte / reconexión) en clients.extra ─────
  static Future<void> setServiceState(String clientId, Map<String, dynamic> extra, String state) {
    final e = Map<String, dynamic>.from(extra)
      ..['servicio'] = state
      ..['servicio_fecha'] = todayIso();
    if (state == 'activo') e.remove('aviso_corte_fecha'); // reconectado: el próximo corte exige un aviso nuevo
    return _db.from('clients').update({'extra': e}).eq('id', clientId);
  }

  /// Guarda en `clients.extra[key]` la fecha de hoy (último aviso enviado, p. ej. pensión pendiente).
  static Future<void> setNoticeDate(String clientId, Map<String, dynamic> extra, String key) {
    final e = Map<String, dynamic>.from(extra)..[key] = todayIso();
    return _db.from('clients').update({'extra': e}).eq('id', clientId);
  }

  /// Guarda que hoy se envió el aviso previo al abonado (requisito para registrar el corte).
  static Future<void> setCutoffNotice(String clientId, Map<String, dynamic> extra) {
    final e = Map<String, dynamic>.from(extra)..['aviso_corte_fecha'] = todayIso();
    return _db.from('clients').update({'extra': e}).eq('id', clientId);
  }

  // ───── Datos de práctica ─────
  static Future<int> loadPractice(List<(String, double, String, double?)> products, List<String> clients) async {
    var n = 0;
    for (final p in products) {
      try {
        await _db.from('products').insert({'org_id': _org, 'user_id': _db.auth.currentUser?.id, 'name': p.$1, 'unit_price': p.$2, 'unit': p.$3, 'unit_cost': p.$4, 'category': 'Práctica'});
        n++;
      } catch (_) {}
    }
    for (final c in clients) {
      try {
        await _db.from('clients').insert({'org_id': _org, 'user_id': _db.auth.currentUser?.id, 'name': c, 'tags': ['practica']});
        n++;
      } catch (_) {}
    }
    return n;
  }

  static Future<void> clearPractice() async {
    await _db.from('products').delete().eq('org_id', _org).eq('category', 'Práctica');
    await _db.from('clients').delete().eq('org_id', _org).contains('tags', ['practica']);
  }
}
