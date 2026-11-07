/// Decimal boundary parser. Money stays in cents; never round binary floats here.
int? parseCents(String value) {
  final match = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(value.trim());
  if (match == null) return null;
  final units = int.tryParse(match[1]!);
  if (units == null || units > 90000000000) return null;
  return units * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
}

/// Presentation/legacy RPC adapter, not a floating-point money calculation.
int centsFromLegacy(double value) {
  if (!value.isFinite || value < 0) throw ArgumentError('Importe no válido');
  final parsed = parseCents(value.toStringAsFixed(2));
  if (parsed == null) throw ArgumentError('Importe fuera de rango');
  return parsed;
}
