// Revisión de lo que leyó el escáner de comprobantes ANTES de guardarlo como gasto (Fase 0, punto 6).
// No cambia el escáner: solo avisa en la hoja de confirmación del gasto.
class ScanWarning {
  const ScanWarning(this.text, {this.serious = false});
  final String text;
  final bool serious;
}

/// [myRuc]: RUC de la empresa activa. [today]: 'yyyy-MM-dd'.
List<ScanWarning> scanWarnings({
  required String issueDate,
  required String supplierTaxId,
  required String clientTaxId,
  required String docType,
  required double confidence,
  required bool looksHandwritten,
  required String myRuc,
  required String today,
}) {
  final out = <ScanWarning>[];
  final d = DateTime.tryParse(issueDate);
  final t = DateTime.tryParse(today);
  if (d != null && t != null) {
    final days = t.difference(d).inDays;
    if (days < -1) out.add(const ScanWarning('La fecha del comprobante está en el futuro: revísala.', serious: true));
    if (days > 365) {
      out.add(const ScanWarning('Este comprobante tiene más de un año. El IGV de compras antiguas puede ya no servir como crédito fiscal: consúltalo con tu contador.', serious: true));
    } else if (days > 60) {
      out.add(ScanWarning('El comprobante es de hace $days días. ¿Seguro que es de este periodo?'));
    }
  }
  final mine = myRuc.trim();
  if (mine.isNotEmpty && supplierTaxId.trim() == mine) {
    out.add(const ScanWarning('El RUC del emisor es el TUYO: parece una venta tuya, no una compra. Usa "Es una venta mía".', serious: true));
  }
  final buyer = clientTaxId.trim();
  if (docType == 'factura' && mine.isNotEmpty && buyer.isNotEmpty && buyer != mine) {
    out.add(ScanWarning('La factura está a nombre de otro RUC ($buyer), no del tuyo. No podrás usar su IGV como crédito fiscal.', serious: true));
  } else if (docType == 'factura' && mine.isNotEmpty && buyer.isEmpty) {
    out.add(const ScanWarning('No se leyó el RUC del comprador. Verifica que la factura esté a tu nombre.'));
  }
  if (looksHandwritten) out.add(const ScanWarning('Parece escrito a mano: revisa cada número con calma.'));
  if (confidence < 0.6) out.add(const ScanWarning('La lectura no es muy segura. Compara los montos con el papel.'));
  return out;
}

/// Señales de un comprobante hecho a mano (talonario): sin RUC del emisor ni serie electrónica.
bool looksHandwritten({required String supplierTaxId, required String docNumber, required String docType}) {
  final electronic = RegExp(r'^[FBEPT][A-Z0-9]{3}\s*-\s*\d+$', caseSensitive: false).hasMatch(docNumber.trim());
  if (electronic) return false;
  if (supplierTaxId.trim().isEmpty) return true;
  return docType == 'otro' || docType == 'recibo' || RegExp(r'^\d{3}\s*-\s*\d+$').hasMatch(docNumber.trim());
}

/// La confianza que se MUESTRA baja en textos manuscritos (la IA suele sobreestimarla).
double shownConfidence(double raw, {required bool handwritten}) {
  final c = raw.isNaN ? 0.5 : raw.clamp(0.0, 1.0);
  return handwritten ? (c > 0.6 ? 0.6 : c) : c;
}
