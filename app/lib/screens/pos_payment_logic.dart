/// Quantities are stored in integer cents during POS tender calculation.
int? parsePosCents(String input) {
  final raw = input.trim().replaceAll(',', '.');
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(raw);
  if (match == null) return null;
  final soles = int.tryParse(match.group(1)!);
  if (soles == null) return null;
  final fractions = (match.group(2) ?? '').padRight(2, '0');
  return soles * 100 + (fractions.isEmpty ? 0 : int.parse(fractions));
}

int posChangeDue({required int chargeCents, required int tenderedCents}) {
  if (chargeCents < 0 || tenderedCents < chargeCents) {
    throw ArgumentError('El efectivo recibido es menor que el total');
  }
  return tenderedCents - chargeCents;
}

int posMoneyToCents(num amount) {
  if (!amount.isFinite || amount < 0) {
    throw ArgumentError('Monto de cobro inválido');
  }
  // Matches the established two-decimal monetary rounding of the current POS.
  return parsePosCents(amount.toStringAsFixed(2))!;
}
