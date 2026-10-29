// Puntaje de pago del cliente (Fase 8 · módulo 9). Puro: se calcula con el historial de cobros (client_payment_stats).
// 100 = siempre paga a tiempo. No es un puntaje de centrales de riesgo: solo mide cómo te paga A TI.
class PayScore {
  const PayScore(this.value, this.label, this.tone);
  final int? value; // null = sin historial suficiente
  final String label;
  final String tone; // ok | warn | bad | neutral
}

PayScore payScore({required int creditInvoices, required int settled, double? avgDaysLate, int maxDaysLate = 0, double overdueBalance = 0}) {
  if (creditInvoices < 2 && settled < 2) return const PayScore(null, 'Sin historial suficiente', 'neutral');
  var s = 100.0;
  final late = avgDaysLate ?? 0;
  s -= (late * 2.5).clamp(0, 55);
  if (maxDaysLate > 30) s -= 10;
  if (maxDaysLate > 60) s -= 10;
  if (overdueBalance > 0) s -= 15;
  final v = s.clamp(0, 100).round();
  if (v >= 80) return PayScore(v, 'Paga puntual', 'ok');
  if (v >= 55) return PayScore(v, 'A veces se atrasa', 'warn');
  return PayScore(v, 'Cobra por adelantado', 'bad');
}

/// Lee coordenadas de un enlace de Google Maps / OpenStreetMap o de un texto "-12.04, -77.03". null si no hay.
({double lat, double lng})? parseCoordinates(String text) {
  final t = text.trim();
  final patterns = [
    RegExp(r'@(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&](?:q|query|ll|destination)=(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'mlat=(-?\d{1,2}\.\d+)&mlon=(-?\d{1,3}\.\d+)'),
    RegExp(r'^(-?\d{1,2}\.\d+)\s*[,;\s]\s*(-?\d{1,3}\.\d+)$'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(t);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) continue;
    return (lat: lat, lng: lng);
  }
  return null;
}
