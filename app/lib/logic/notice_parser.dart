// Avisos de pago de Yape/Plin/banco (Fase 8 · 18). El usuario pega o comparte el texto de la notificación
// (o la app lo recibe del lector de notificaciones en Android, si se activa). Lógica pura y tolerante.
class PaymentNotice {
  const PaymentNotice({required this.app, required this.amount, required this.payer, required this.operation, required this.raw});
  final String app; // yape | plin | banco | otro
  final double amount;
  final String payer;
  final String operation;
  final String raw;
}

double? _amount(String s) {
  final m = RegExp(r'(?:S\/\.?|soles?)\s*([0-9][0-9.,]*)', caseSensitive: false).firstMatch(s);
  if (m == null) return null;
  var v = m.group(1)!.replaceAll(RegExp(r'[.,]+$'), '');
  final lastDot = v.lastIndexOf('.');
  final lastComma = v.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    v = lastComma > lastDot ? v.replaceAll('.', '').replaceAll(',', '.') : v.replaceAll(',', '');
  } else if (lastComma >= 0) {
    v = v.length - lastComma - 1 == 3 ? v.replaceAll(',', '') : v.replaceAll(',', '.');
  } else if (lastDot >= 0 && v.length - lastDot - 1 == 3 && v.indexOf('.') != lastDot) {
    v = v.replaceAll('.', '');
  }
  final n = double.tryParse(v);
  return n == null || n <= 0 || n > 10000000 ? null : n;
}

/// "¡Yape! JUAN PEREZ te envió un pago por S/ 25.50. El cód. de seguridad es: 123" → yape, 25.50, JUAN PEREZ.
PaymentNotice? parsePaymentNotice(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  final low = raw.toLowerCase();
  final amount = _amount(raw);
  if (amount == null) return null;
  final app = low.contains('yape') ? 'yape' : (low.contains('plin') ? 'plin' : (RegExp(r'transferencia|bcp|interbank|bbva|scotiabank|abono').hasMatch(low) ? 'banco' : 'otro'));
  var payer = '';
  final p1 = RegExp(r'(?:yape!?|plin!?)\s*[:\-]?\s*([A-ZÁÉÍÓÚÑ][A-Za-zÁÉÍÓÚÑáéíóúñ.\s]{2,60}?)\s+te\s+(?:envi[oó]|yape[oó]|pag[oó])', caseSensitive: false).firstMatch(raw);
  final p2 = RegExp(r'([A-ZÁÉÍÓÚÑ][A-Za-zÁÉÍÓÚÑáéíóúñ.\s]{2,60}?)\s+te\s+(?:envi[oó]|yape[oó]|pag[oó])').firstMatch(raw);
  final p3 = RegExp(r'(?:de|remitente:?)\s+([A-ZÁÉÍÓÚÑ][A-Za-zÁÉÍÓÚÑáéíóúñ.\s]{2,60}?)(?:\s+por|\s*[.,]|$)', caseSensitive: false).firstMatch(raw);
  payer = (p1?.group(1) ?? p2?.group(1) ?? p3?.group(1) ?? '').trim();
  final op = RegExp(r'(?:operaci[oó]n|n[°º]\s*de\s*operaci[oó]n|c[oó]d(?:igo)?\.?(?:\s*de\s*seguridad)?)\s*(?:es)?\s*[:#]?\s*([A-Za-z0-9-]{3,20})', caseSensitive: false).firstMatch(raw);
  return PaymentNotice(app: app, amount: amount, payer: payer, operation: op?.group(1) ?? '', raw: raw.length > 500 ? raw.substring(0, 500) : raw);
}
