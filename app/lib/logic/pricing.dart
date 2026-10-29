// Listas de precios y promociones (Fase 8 · 10). Lógica pura: precio por mayor, % de descuento, monto fijo,
// "lleva N" (volumen) y cupones. Nunca deja un precio negativo.
class Promo {
  const Promo({required this.id, required this.name, required this.kind, required this.value, this.productIds = const [], this.minQty, this.startsOn, this.endsOn, this.active = true});
  final String id;
  final String name;
  final String kind; // porcentaje | monto | volumen | combo
  final double value;
  final List<String> productIds;
  final double? minQty;
  final String? startsOn; // yyyy-MM-dd
  final String? endsOn;
  final bool active;

  bool liveOn(String today) => active && (startsOn == null || startsOn!.compareTo(today) <= 0) && (endsOn == null || endsOn!.compareTo(today) >= 0);

  factory Promo.fromJson(Map<String, dynamic> j) => Promo(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        kind: (j['kind'] ?? 'porcentaje') as String,
        value: (j['value'] as num?)?.toDouble() ?? 0,
        productIds: ((j['product_ids'] ?? const []) as List).map((e) => e.toString()).toList(),
        minQty: (j['min_qty'] as num?)?.toDouble(),
        startsOn: j['starts_on'] as String?,
        endsOn: j['ends_on'] as String?,
        active: j['active'] != false,
      );
}

class PricedLine {
  const PricedLine(this.unitPrice, this.reason);
  final double unitPrice;
  final String reason; // '' si no hay descuento
}

double _r2(double n) => (n * 100).round() / 100;

/// Precio unitario (sin IGV) de un producto para una cantidad, aplicando el mejor descuento vigente.
PricedLine bestPrice({
  required String productId,
  required double listPrice,
  required double qty,
  double? wholesalePrice,
  double? wholesaleMinQty,
  List<Promo> promos = const [],
  required String today,
}) {
  var best = listPrice;
  var reason = '';
  if (wholesalePrice != null && wholesaleMinQty != null && qty >= wholesaleMinQty && wholesalePrice < best) {
    best = wholesalePrice;
    reason = 'Precio por mayor';
  }
  for (final p in promos) {
    if (!p.liveOn(today)) continue;
    if (p.productIds.isNotEmpty && !p.productIds.contains(productId)) continue;
    if (p.minQty != null && qty < p.minQty!) continue;
    double price;
    switch (p.kind) {
      case 'porcentaje':
      case 'volumen':
        price = listPrice * (1 - p.value.clamp(0, 100) / 100);
      case 'monto':
        price = listPrice - p.value;
      default:
        continue;
    }
    if (price < best) {
      best = price;
      reason = p.name;
    }
  }
  return PricedLine(_r2(best < 0 ? 0 : best), reason);
}

/// Descuento de un cupón sobre un subtotal.
double couponDiscount({required String kind, required double value, required double subtotal}) {
  final d = kind == 'porcentaje' ? subtotal * value.clamp(0, 100) / 100 : value;
  return _r2(d > subtotal ? subtotal : (d < 0 ? 0 : d));
}
