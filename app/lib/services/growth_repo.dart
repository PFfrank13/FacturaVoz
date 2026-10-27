import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../errors.dart';
import '../models.dart';
import '../models_growth.dart';
import 'repo.dart';

/// Datos de la fase "Revolución" (migración 20261102_revolucion.sql). Todo pasa por RLS.
class GrowthRepo {
  static SupabaseClient get _db => Supabase.instance.client;

  static String get _org {
    final o = Repo.activeOrgId;
    if (o == null) throw AppException('Elige una empresa primero.');
    return o;
  }

  static String get _uid {
    final u = _db.auth.currentUser;
    if (u == null) throw AppException('Sesión caducada');
    return u.id;
  }

  // ───────────── Meta mensual ─────────────
  static Future<double?> monthlyGoal() async {
    try {
      final row = await _db.from('organizations').select('monthly_goal').eq('id', _org).maybeSingle();
      final v = row?['monthly_goal'];
      return v == null ? null : (v as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setMonthlyGoal(double? goal) async {
    final rows = await _db.from('organizations').update({'monthly_goal': goal == null ? null : round2(goal)}).eq('id', _org).select('id');
    if ((rows as List).isEmpty) throw AppException('Solo el propietario o un administrador puede fijar la meta.');
  }

  // ───────────── Clientes 360 ─────────────
  static Future<List<ClientActivity>> clientActivity() async {
    final rows = await _db.rpc('client_activity', params: {'p_org': _org});
    return (rows as List).map((r) => ClientActivity.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  // ───────────── Recurrentes ─────────────
  static const _recCols = 'id, client_name, client_tax_id, items, tax_rate, currency, notes, day_of_month, due_days, next_run, active, runs, last_error';

  static Future<List<RecurringTemplate>> listRecurring() async {
    final rows = await _db.from('recurring_invoices').select(_recCols).eq('org_id', _org).order('created_at', ascending: false).limit(500);
    return (rows as List).map((r) => RecurringTemplate.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  static Future<void> saveRecurring(RecurringTemplate t) async {
    final row = t.toRow();
    if (t.id == null) {
      await _db.from('recurring_invoices').insert({...row, 'org_id': _org, 'user_id': _uid});
    } else {
      await _db.from('recurring_invoices').update(row).eq('id', t.id!);
    }
  }

  static Future<void> setRecurringActive(String id, bool active) async {
    await _db.from('recurring_invoices').update({'active': active}).eq('id', id);
  }

  static Future<void> deleteRecurring(String id) async {
    final rows = await _db.from('recurring_invoices').delete().eq('id', id).select('id');
    if ((rows as List).isEmpty) throw AppException('Solo quien la creó o un administrador puede borrarla.');
  }

  /// Genera ya las facturas que tocan hoy (además del worker diario). Devuelve cuántas creó.
  static Future<int> runRecurringNow() async {
    final r = await _db.rpc('run_my_recurring', params: {'p_org': _org});
    return (r as num).toInt();
  }

  /// Borradores creados por plantillas recurrentes (listos para emitir).
  static Future<int> countRecurringDrafts() async {
    try {
      final res = await _db.from('invoices').select('id').eq('org_id', _org).eq('status', 'draft').not('recurring_id', 'is', null).count(CountOption.exact);
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  // ───────────── Tienda en línea ─────────────
  static Future<StoreSettings> loadStore() async {
    final row = await _db.from('org_store').select('slug, enabled, headline, whatsapp').eq('org_id', _org).maybeSingle();
    return row == null ? StoreSettings() : StoreSettings.fromJson(row);
  }

  static Future<void> saveStore(StoreSettings s) async {
    String? n(String v) => v.trim().isEmpty ? null : v.trim();
    await _db.from('org_store').upsert({
      'org_id': _org,
      'slug': s.slug.trim().toLowerCase(),
      'enabled': s.enabled,
      'headline': n(s.headline),
      'whatsapp': n(s.whatsapp.replaceAll(RegExp(r'\D'), '')),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'org_id');
  }

  static String storeUrl(String slug) => '${Config.apiBase}/tienda/$slug';

  /// Pedidos web aún sin atender (últimos 7 días).
  static Future<int> countNewStoreOrders() async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
      final res = await _db
          .from('quotes')
          .select('id')
          .eq('org_id', _org)
          .eq('source', 'store')
          .eq('status', 'sent')
          .gte('created_at', since)
          .count(CountOption.exact);
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  // ───────────── Productos ─────────────
  static Future<void> setCostAndStore(String productId, {double? unitCost, required bool inStore}) async {
    await _db.from('products').update({'unit_cost': unitCost == null ? null : round2(unitCost), 'in_store': inStore}).eq('id', productId);
  }

  static Future<void> setInStore(String productId, bool inStore) async {
    await _db.from('products').update({'in_store': inStore}).eq('id', productId);
  }
}
