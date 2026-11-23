// Lotes con vencimiento y mermas con motivo (v3.6). Misma base que el ERP web: lot_status, record_loss,
// product_lot_add/remove. Investigación: docs/INVESTIGACION_RETAIL.md, filas 3 y 4.
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repo.dart';
import '../errors.dart';

const lossReasons = <String, String>{
  'vencido': 'Vencido',
  'danado': 'Dañado o roto',
  'robo': 'Robo o faltante',
  'consumo': 'Consumo interno',
  'canje': 'Devuelto al proveedor',
  'otro': 'Otro motivo',
};

class LotStatus {
  const LotStatus({
    required this.lotId, required this.productId, required this.productName, required this.unit, this.lotCode,
    required this.expiresOn, required this.quantity, required this.remaining, required this.daysLeft,
    this.unitCost, this.unitPrice,
  });
  final String lotId;
  final String productId;
  final String productName;
  final String unit;
  final String? lotCode;
  final DateTime expiresOn;
  final double quantity;
  final double remaining;
  final int daysLeft;
  final double? unitCost;
  final double? unitPrice;

  factory LotStatus.fromJson(Map<String, dynamic> j) => LotStatus(
        lotId: j['lot_id'] as String,
        productId: j['product_id'] as String,
        productName: (j['product_name'] ?? '') as String,
        unit: (j['unit'] ?? 'NIU') as String,
        lotCode: j['lot_code'] as String?,
        expiresOn: DateTime.parse(j['expires_on'] as String),
        quantity: (j['quantity'] as num).toDouble(),
        remaining: (j['remaining'] as num).toDouble(),
        daysLeft: (j['days_left'] as num).toInt(),
        unitCost: (j['unit_cost'] as num?)?.toDouble(),
        unitPrice: (j['unit_price'] as num?)?.toDouble(),
      );
}

/// vencido · semana (≤ 7 días) · mes (≤ 30) · ok.
String expiryBucket(int daysLeft) => daysLeft < 0 ? 'vencido' : daysLeft <= 7 ? 'semana' : daysLeft <= 30 ? 'mes' : 'ok';

/// Rebaja sugerida cerca del vencimiento: 30 % en los últimos 3 días, 15 % en la semana, nunca bajo costo + 2 %.
/// Igual que el ERP web (lib/erp/lots.ts). null si no hace falta.
double? suggestedPrice(double? price, double? cost, int daysLeft) {
  if (price == null || price <= 0 || daysLeft < 0 || daysLeft > 7) return null;
  final off = daysLeft <= 3 ? 0.3 : 0.15;
  final floor = cost != null && cost > 0 ? cost * 1.02 : 0.0;
  final v = (price * (1 - off)) > floor ? price * (1 - off) : floor;
  return v < price - 0.004 ? (v * 10).round() / 10 : null;
}

/// Primer problema de una merma, en palabras del dueño, o null.
String? lossProblem(double? quantity, String reason, String note, double? stock) {
  if (stock == null) return 'Este producto no controla stock: actívalo primero.';
  if (quantity == null || quantity <= 0 || (quantity * 100 - (quantity * 100).round()).abs() > 1e-6) {
    return 'Escribe una cantidad mayor que cero, con hasta 2 decimales.';
  }
  if (quantity > stock) return 'La merma no puede superar el stock actual (${stock.toStringAsFixed(stock == stock.roundToDouble() ? 0 : 2)}).';
  if (!lossReasons.containsKey(reason)) return 'Elige el motivo de la merma.';
  if (reason == 'otro' && note.trim().isEmpty) return 'Escribe el motivo de la merma.';
  if (note.trim().length > 200) return 'La nota admite hasta 200 caracteres.';
  return null;
}

/// Lotes con stock, lo más urgente primero.
List<LotStatus> activeLots(List<LotStatus> lots) =>
    lots.where((l) => l.remaining > 0).toList()..sort((a, b) => a.daysLeft != b.daysLeft ? a.daysLeft.compareTo(b.daysLeft) : a.productName.compareTo(b.productName));

class StockLotsRepo {
  StockLotsRepo._();
  static SupabaseClient get _db => Supabase.instance.client;
  static String get _org {
    final org = Repo.activeOrgId;
    if (org == null) throw AppException('Selecciona una empresa.');
    return org;
  }

  static Future<List<LotStatus>> status() async {
    final rows = await _db.rpc('lot_status', params: {'p_org': _org});
    return [for (final r in rows as List) LotStatus.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  /// Merma idempotente: el mismo [requestId] nunca descuenta dos veces. Devuelve el stock que queda.
  static Future<double> recordLoss({
    required String requestId, required String productId, required double quantity, required String reason,
    String? lotId, String? note,
  }) async {
    final rows = await _db.rpc('record_loss', params: {
      'p_org': _org, 'p_request_id': requestId, 'p_product': productId,
      'p_quantity': double.parse(quantity.toStringAsFixed(2)), 'p_reason': reason,
      'p_lot': lotId, 'p_note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    });
    final row = (rows as List).isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
    return ((row?['stock_after'] ?? 0) as num).toDouble();
  }

  static Future<void> addLot({required String productId, required DateTime expiresOn, required double quantity, String? code}) async {
    await _db.rpc('product_lot_add', params: {
      'p_org': _org, 'p_product': productId, 'p_expires': isoDate(expiresOn),
      'p_quantity': double.parse(quantity.toStringAsFixed(2)), 'p_code': (code == null || code.trim().isEmpty) ? null : code.trim(),
    });
  }

  static Future<void> removeLot(String lotId) async {
    await _db.rpc('product_lot_remove', params: {'p_org': _org, 'p_lot': lotId});
  }
}

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
