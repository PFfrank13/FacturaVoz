// The POS draft is NOT an invoice and does not evidence payment.
// It preserves an editable open cart per authenticated user and organization.
// A confirmed/uncertain checkout has a separate immutable PendingCheckout record.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PosCartDraft {
  const PosCartDraft({
    required this.orgId,
    required this.userId,
    required this.quantities,
    required this.notes,
    required this.table,
    this.couponCode,
    this.couponKind,
    this.couponValue,
  });

  final String orgId;
  final String userId;
  final Map<String, double> quantities;
  final Map<String, String> notes;
  final String table;
  final String? couponCode;
  final String? couponKind;
  final double? couponValue;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'org_id': orgId,
        'user_id': userId,
        'quantities': quantities,
        'notes': notes,
        'table': table,
        if (couponCode != null) 'coupon_code': couponCode,
        if (couponKind != null) 'coupon_kind': couponKind,
        if (couponValue != null) 'coupon_value': couponValue,
      };

  factory PosCartDraft.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1 ||
        json['org_id'] is! String ||
        json['user_id'] is! String ||
        json['quantities'] is! Map ||
        json['notes'] is! Map ||
        json['table'] is! String) {
      throw const FormatException('Formato de carrito local no válido.');
    }
    final raw = Map<String, dynamic>.from(json['quantities'] as Map);
    final notesRaw = Map<String, dynamic>.from(json['notes'] as Map);
    final quantities = <String, double>{};
    final notes = <String, String>{};
    for (final entry in raw.entries) {
      final number = entry.value;
      if (entry.key.isEmpty || number is! num || !number.isFinite) {
        throw const FormatException('Carrito local tiene artículos inválidos.');
      }
      final quantity = number.toDouble();
      if (quantity <= 0 || quantity > 100000 ||
          quantity != double.parse(quantity.toStringAsFixed(2))) {
        throw const FormatException('Cantidad del carrito local inválida.');
      }
      quantities[entry.key] = quantity;
    }
    for (final entry in notesRaw.entries) {
      if (entry.key.isEmpty || entry.value is! String ||
          (entry.value as String).length > 200 ||
          !quantities.containsKey(entry.key)) {
        throw const FormatException('Notas del carrito local inválidas.');
      }
      notes[entry.key] = entry.value as String;
    }
    final couponCode = json['coupon_code'] as String?;
    final couponKind = json['coupon_kind'] as String?;
    final couponRaw = json['coupon_value'];
    final couponValue = couponRaw is num ? couponRaw.toDouble() : null;
    if ((json['org_id'] as String).isEmpty ||
        (json['user_id'] as String).isEmpty ||
        quantities.length > 100 || notes.length > 100 ||
        (json['table'] as String).length > 100 ||
        (couponCode != null &&
            (couponCode.isEmpty || couponCode.length > 60 ||
             couponKind == null || couponValue == null ||
             !couponValue.isFinite || couponValue < 0 || couponValue > 1000000))) {
      throw const FormatException('Carrito local dañado; no se sobrescribirá.');
    }
    return PosCartDraft(
      orgId: json['org_id'] as String,
      userId: json['user_id'] as String,
      quantities: quantities,
      notes: notes,
      table: json['table'] as String,
      couponCode: couponCode,
      couponKind: couponKind,
      couponValue: couponValue,
    );
  }
}

class PosCartStore {
  PosCartStore._();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static String _key(String user, String org) => 'fv_open_cart_v1_${user}_$org';

  static Future<PosCartDraft?> load(String user, String org) async {
    final raw = await _storage.read(key: _key(user, org));
    if (raw == null) return null;
    final data = PosCartDraft.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    if (data.userId != user || data.orgId != org) {
      throw const FormatException('El carrito pertenece a otra sesión o empresa.');
    }
    return data;
  }

  static Future<void> save(PosCartDraft draft) =>
      _storage.write(key: _key(draft.userId, draft.orgId), value: jsonEncode(draft.toJson()));

  static Future<void> clear({required String userId, required String orgId}) =>
      _storage.delete(key: _key(userId, orgId));
}
