// Etiquetas de balanza (EAN-13 de peso variable, prefijo GS1 «2»): docs/INVESTIGACION_RETAIL.md, fila 8.
// Formato usado por las balanzas etiquetadoras del mercado peruano: 2X PPPPP VVVVV C
//   2X = prefijo (20–29), PPPPP = código PLU del producto en la balanza, VVVVV = peso en gramos, C = dígito de control.
// En el producto se guarda como código de barras el PLU (5 dígitos) o «2X» + PLU (7 dígitos).

class ScaleLabel {
  const ScaleLabel({required this.plu, required this.prefixPlu, required this.kilos});
  final String plu; // 5 dígitos
  final String prefixPlu; // 7 dígitos (2X + PLU)
  final double kilos;
}

/// Dígito de control EAN-13 de los 12 primeros dígitos.
int ean13Check(String twelve) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = twelve.codeUnitAt(i) - 48;
    sum += i.isEven ? d : d * 3;
  }
  return (10 - sum % 10) % 10;
}

/// Lee una etiqueta de balanza. null si no es un EAN-13 de peso variable válido o el peso es 0.
ScaleLabel? parseScaleLabel(String raw) {
  final code = raw.trim();
  if (!RegExp(r'^2\d{12}$').hasMatch(code)) return null;
  if (ean13Check(code.substring(0, 12)) != code.codeUnitAt(12) - 48) return null;
  final grams = int.parse(code.substring(7, 12));
  if (grams <= 0) return null;
  return ScaleLabel(plu: code.substring(2, 7), prefixPlu: code.substring(0, 7), kilos: grams / 1000);
}

/// ¿Este código de barras guardado en el producto corresponde a la etiqueta? (PLU, 2X+PLU o PLU sin ceros a la izquierda).
bool matchesScaleProduct(String productBarcode, ScaleLabel label) {
  final b = productBarcode.trim();
  if (b.isEmpty) return false;
  return b == label.plu || b == label.prefixPlu || (RegExp(r'^\d{1,5}$').hasMatch(b) && int.parse(b) == int.parse(label.plu));
}
