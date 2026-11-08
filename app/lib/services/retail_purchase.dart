// Retail receipts: one immutable local snapshot per company/account, then one
// idempotent PostgreSQL RPC. No local stock write or multi-request fallback.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import 'repo.dart';

class RetailPurchaseLine {
  const RetailPurchaseLine({
    required this.productId,
    required this.quantity,
    required this.unitCostCents,
  });
  final String productId;
  final double quantity;
  final int unitCostCents;

  int get lineTotalCents {
    // Currency arithmetic never multiplies binary floating-point values.
    // Quantity is represented to two decimals: 1.25 units -> 125 hundredths.
    final hundredths = int.parse(quantity.toStringAsFixed(2).replaceAll('.', ''));
    return (hundredths * unitCostCents + 50) ~/ 100;
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': double.parse(quantity.toStringAsFixed(2)),
        'unit_cost_cents': unitCostCents,
      };

  factory RetailPurchaseLine.fromJson(Map<String, dynamic> j) => RetailPurchaseLine(
        productId: j['product_id'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unitCostCents: (j['unit_cost_cents'] as num).toInt(),
      );
}

class PendingRetailPurchase {
  const PendingRetailPurchase({
    required this.orgId,
    required this.userId,
    required this.requestId,
    required this.supplier,
    required this.reference,
    required this.paymentMethod,
    required this.lines,
  });
  final String orgId;
  final String userId;
  final String requestId;
  final String supplier;
  final String reference;
  final String paymentMethod;
  final List<RetailPurchaseLine> lines;

  int get totalCents => lines.fold<int>(0, (sum, line) => sum + line.lineTotalCents);

  Map<String, dynamic> toJson() => {
        'v': 1, 'org_id': orgId, 'user_id': userId, 'request_id': requestId,
        'supplier': supplier, 'reference': reference, 'payment_method': paymentMethod,
        'items': [for (final line in lines) line.toJson()],
      };

  factory PendingRetailPurchase.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1 || json['items'] is! List) {
      throw const FormatException('Solicitud de compra inválida');
    }
    final lines = (json['items'] as List)
        .map((e) => RetailPurchaseLine.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final receipt = PendingRetailPurchase(
      orgId: json['org_id'] as String,
      userId: json['user_id'] as String,
      requestId: json['request_id'] as String,
      supplier: json['supplier'] as String,
      reference: json['reference'] as String,
      paymentMethod: json['payment_method'] as String,
      lines: lines,
    );
    if (receipt.orgId.isEmpty || receipt.userId.isEmpty || receipt.requestId.isEmpty ||
        receipt.supplier.trim().isEmpty || receipt.supplier.length > 120 ||
        receipt.reference.length > 40 ||
        !const {'pendiente','efectivo','yape','plin','tarjeta','transferencia'}
            .contains(receipt.paymentMethod) ||
        lines.isEmpty || lines.length > 50 || receipt.totalCents <= 0 ||
        receipt.totalCents > 10000000000 ||
        lines.map((x) => x.productId).toSet().length != lines.length ||
        lines.any((x) => x.productId.isEmpty ||
            !x.quantity.isFinite || x.quantity <= 0 || x.quantity > 100000 ||
            x.quantity != double.parse(x.quantity.toStringAsFixed(2)) ||
            x.unitCostCents < 0 || x.unitCostCents > 1000000000)) {
      throw const FormatException('La compra pendiente tiene datos inválidos');
    }
    return receipt;
  }
}

class RetailPurchaseStore {
  RetailPurchaseStore._();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static String _key(String user, String org) => 'fv_purchase_pending_v1_${user}_$org';

  static Future<PendingRetailPurchase?> load(String user, String org) async {
    final raw = await _storage.read(key: _key(user, org));
    if (raw == null) return null;
    final receipt = PendingRetailPurchase.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    if (receipt.userId != user || receipt.orgId != org) {
      throw const FormatException('La compra pertenece a otra cuenta');
    }
    return receipt;
  }

  static Future<void> save(PendingRetailPurchase purchase) async {
    final old = await load(purchase.userId, purchase.orgId);
    if (old != null && old.requestId != purchase.requestId) {
      throw StateError('Recupera la compra anterior antes de registrar otra.');
    }
    await _storage.write(key: _key(purchase.userId, purchase.orgId), value: jsonEncode(purchase.toJson()));
  }

  static Future<void> clear(PendingRetailPurchase purchase) async {
    final old = await load(purchase.userId, purchase.orgId);
    if (old != null && old.requestId != purchase.requestId) {
      throw StateError('No se eliminará una compra pendiente distinta.');
    }
    await _storage.delete(key: _key(purchase.userId, purchase.orgId));
  }
}

class RetailPurchaseRepo {
  RetailPurchaseRepo._();

  static Future<String> receive(PendingRetailPurchase purchase) async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (Repo.activeOrgId != purchase.orgId || user != purchase.userId) {
      throw AppException('Cuenta o empresa distinta de la compra pendiente.');
    }
    final result = await Supabase.instance.client.rpc('retail_receive', params: {
      'p_org': purchase.orgId,
      'p_request_id': purchase.requestId,
      'p_supplier': purchase.supplier,
      'p_reference': purchase.reference,
      'p_payment_method': purchase.paymentMethod,
      'p_items': [for (final line in purchase.lines) line.toJson()],
    });
    if (result is! List || result.isEmpty || result.first is! Map) {
      throw AppException('No llegó confirmación de la recepción. Recupera la misma compra.');
    }
    final row = Map<String, dynamic>.from(result.first as Map);
    final id = row['receipt_id'];
    if (id is! String || id.isEmpty) {
      throw AppException('La recepción no devolvió su identificador.');
    }
    return id;
  }
}

class PendingRetailSettlement {
  const PendingRetailSettlement({
    required this.orgId, required this.userId, required this.requestId,
    required this.receiptId, required this.method, required this.evidence,
  });
  final String orgId;
  final String userId;
  final String requestId;
  final String receiptId;
  final String method;
  final String evidence;

  Map<String, dynamic> toJson() => {
    'v': 1, 'org_id': orgId, 'user_id': userId, 'request_id': requestId,
    'receipt_id': receiptId, 'method': method, 'evidence': evidence,
  };
  factory PendingRetailSettlement.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1 || json['org_id'] is! String ||
        json['user_id'] is! String || json['request_id'] is! String ||
        json['receipt_id'] is! String || json['method'] is! String ||
        json['evidence'] is! String) {
      throw const FormatException('Pago pendiente inválido');
    }
    final v = PendingRetailSettlement(
      orgId: json['org_id'] as String,
      userId: json['user_id'] as String,
      requestId: json['request_id'] as String,
      receiptId: json['receipt_id'] as String,
      method: json['method'] as String,
      evidence: json['evidence'] as String,
    );
    if (v.orgId.isEmpty || v.userId.isEmpty || v.requestId.isEmpty ||
        v.receiptId.isEmpty || v.evidence.length > 200 ||
        !const {'efectivo','yape','plin','tarjeta','transferencia'}
            .contains(v.method)) {
      throw const FormatException('Pago pendiente dañado');
    }
    return v;
  }
}

class RetailSettlementStore {
  RetailSettlementStore._();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static String _key(String user, String org) => 'fv_settle_pending_v1_${user}_$org';

  static Future<PendingRetailSettlement?> load(String user, String org) async {
    final raw = await _storage.read(key: _key(user, org));
    if (raw == null) return null;
    final p = PendingRetailSettlement.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    if (p.userId != user || p.orgId != org) {
      throw const FormatException('Pago pendiente de otra sesión');
    }
    return p;
  }

  static Future<void> save(PendingRetailSettlement p) async {
    final old = await load(p.userId, p.orgId);
    if (old != null && old.requestId != p.requestId) {
      throw StateError('Primero recupera el pago pendiente anterior.');
    }
    await _storage.write(key: _key(p.userId, p.orgId), value: jsonEncode(p.toJson()));
  }

  static Future<void> clear(PendingRetailSettlement p) async {
    final old = await load(p.userId, p.orgId);
    if (old != null && old.requestId != p.requestId) {
      throw StateError('No se borrará un pago pendiente distinto.');
    }
    await _storage.delete(key: _key(p.userId, p.orgId));
  }
}

class RetailSettlementRepo {
  RetailSettlementRepo._();

  static Future<String> settle(PendingRetailSettlement p) async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (user != p.userId || Repo.activeOrgId != p.orgId) {
      throw AppException('Cuenta o empresa distinta del pago pendiente.');
    }
    final result = await Supabase.instance.client.rpc('retail_settle', params: {
      'p_org': p.orgId,
      'p_receipt': p.receiptId,
      'p_request_id': p.requestId,
      'p_method': p.method,
      'p_evidence': p.evidence,
    });
    if (result is! List || result.isEmpty || result.first is! Map) {
      throw AppException('Pago sin respuesta del servidor; reintenta la misma operación.');
    }
    final row = Map<String, dynamic>.from(result.first as Map);
    final id = row['settlement_id'];
    if (id is! String || id.isEmpty) {
      throw AppException('Pago sin identificador de confirmación.');
    }
    return id;
  }
}
