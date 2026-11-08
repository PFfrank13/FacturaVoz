// A confirmed POS transaction may outlive the Flutter process or a network timeout.
// Persist the immutable checkout request before contacting Supabase; never issue a
// new request ID until the prior one was confirmed and the recovery entry cleared.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models.dart';

class PendingCheckout {
  const PendingCheckout({
    required this.orgId,
    required this.userId,
    required this.requestId,
    required this.method,
    required this.taxRate,
    required this.currency,
    required this.notes,
    required this.items,
  });

  final String orgId;
  final String userId;
  final String requestId;
  final String method;
  final double taxRate;
  final String currency;
  final String notes;
  final List<LineItem> items;

  InvoiceDraft toDraft() => InvoiceDraft(
        taxRate: taxRate,
        currency: currency,
        notes: notes,
        transcript: 'Venta rápida',
        items: [for (final i in items) LineItem.fromJson(i.toJson())],
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'org_id': orgId,
        'user_id': userId,
        'request_id': requestId,
        'method': method,
        'tax_rate': taxRate,
        'currency': currency,
        'notes': notes,
        'items': [for (final i in items) i.toJson()],
      };

  factory PendingCheckout.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1 || json['items'] is! List) {
      throw const FormatException('Versión o artículos de cobro no válidos');
    }
    final items = (json['items'] as List)
        .map((i) => LineItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList();
    final record = PendingCheckout(
      orgId: json['org_id'] as String,
      userId: json['user_id'] as String,
      requestId: json['request_id'] as String,
      method: json['method'] as String,
      taxRate: (json['tax_rate'] as num).toDouble(),
      currency: json['currency'] as String,
      notes: json['notes'] as String,
      items: items,
    );
    if (record.orgId.isEmpty ||
        record.userId.isEmpty ||
        record.requestId.isEmpty ||
        items.isEmpty ||
        items.length > 50 ||
        items.any((i) => i.productId == null || i.quantity <= 0 || i.unitPrice < 0)) {
      throw const FormatException('Cobro pendiente dañado; no se puede reintentar automáticamente');
    }
    return record;
  }
}

class PendingCheckoutStore {
  PendingCheckoutStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _key(String userId, String orgId) => 'fv_pos_pending_v1_${userId}_${orgId}';

  static Future<PendingCheckout?> load({
    required String userId,
    required String orgId,
  }) async {
    final raw = await _storage.read(key: _key(userId, orgId));
    if (raw == null) return null;
    final parsed = PendingCheckout.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    if (parsed.userId != userId || parsed.orgId != orgId) {
      throw const FormatException('El cobro pendiente pertenece a otra sesión o empresa');
    }
    return parsed;
  }

  static Future<void> save(PendingCheckout checkout) async {
    final previous = await load(userId: checkout.userId, orgId: checkout.orgId);
    if (previous != null && previous.requestId != checkout.requestId) {
      throw StateError('Confirma el cobro pendiente antes de empezar otro.');
    }
    await _storage.write(
      key: _key(checkout.userId, checkout.orgId),
      value: jsonEncode(checkout.toJson()),
    );
  }

  static Future<void> clear(PendingCheckout checkout) async {
    final previous = await load(userId: checkout.userId, orgId: checkout.orgId);
    if (previous != null && previous.requestId != checkout.requestId) {
      throw StateError('Otro cobro ocupa la recuperación; no se eliminará.');
    }
    await _storage.delete(key: _key(checkout.userId, checkout.orgId));
  }
}
