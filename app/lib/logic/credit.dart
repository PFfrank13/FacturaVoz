// Límite de crédito del cliente (mayorista): avisa al vender al crédito si se pasaría del límite.
// Es solo una advertencia: el dueño decide si vende igual.

enum CreditLevel { none, ok, near, over }

class CreditCheck {
  const CreditCheck(this.level, this.limit, this.used, this.after);
  final CreditLevel level;
  final double limit;
  final double used; // lo que ya debe
  final double after; // lo que debería con esta venta
  double get excess => after > limit ? double.parse((after - limit).toStringAsFixed(2)) : 0;
  double get left => limit > after ? double.parse((limit - after).toStringAsFixed(2)) : 0;
}

/// [limit] <= 0 o nulo = sin límite fijado (no se advierte). "Cerca" = usaría 80 % o más del límite.
CreditCheck creditCheck({required double? limit, required double used, required double newTotal}) {
  final l = limit ?? 0;
  final after = double.parse((used + newTotal).toStringAsFixed(2));
  if (l <= 0) return CreditCheck(CreditLevel.none, 0, used, after);
  if (after > l + 0.004) return CreditCheck(CreditLevel.over, l, used, after);
  if (after >= l * 0.8) return CreditCheck(CreditLevel.near, l, used, after);
  return CreditCheck(CreditLevel.ok, l, used, after);
}
