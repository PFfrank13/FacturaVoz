// RUC/DNI dentro de un dictado: "Factura para el RUC 20100070970, 3 sillas a 150…" → RUC 20100070970.
// Lógica pura (sin red ni Flutter): se prueba con `flutter test`. El dictado multiproducto sigue igual: aquí solo
// se detecta el documento para disparar la consulta DNI/RUC y rellenar el cliente.

/// Dígito verificador del RUC (módulo 11), igual que SUNAT.
bool rucValid(String ruc) {
  if (!RegExp(r'^(10|15|16|17|20)\d{9}$').hasMatch(ruc)) return false;
  const w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += w[i] * int.parse(ruc[i]);
  }
  final r = 11 - (sum % 11);
  final dv = r == 10 ? 0 : (r == 11 ? 1 : r);
  return dv == int.parse(ruc[10]);
}

/// 'dni' | 'ruc' | null según la cantidad de dígitos (y el dígito verificador en el RUC).
String? docKind(String number) {
  final n = number.replaceAll(RegExp(r'\D'), '');
  if (n.length == 8) return 'dni';
  if (n.length == 11 && rucValid(n)) return 'ruc';
  return null;
}

const _digitWords = {
  'cero': '0', 'uno': '1', 'un': '1', 'dos': '2', 'tres': '3', 'cuatro': '4', 'cinco': '5',
  'seis': '6', 'siete': '7', 'ocho': '8', 'nueve': '9',
};

/// Convierte dígitos dichos en palabras ("dos cero uno…") en números, solo cuando forman una secuencia larga.
String normalizeSpokenDigits(String text) {
  final words = text.split(RegExp(r'\s+'));
  final out = <String>[];
  var run = <String>[];
  void flush() {
    if (run.length >= 6) {
      out.add(run.join());
    } else {
      out.addAll(run.map((d) => _digitWords.entries.firstWhere((e) => e.value == d).key));
    }
    run = <String>[];
  }

  for (final w in words) {
    final k = w.toLowerCase().replaceAll(RegExp(r'[.,;:]'), '');
    final d = _digitWords[k];
    if (d != null) {
      run.add(d);
    } else {
      if (run.isNotEmpty) flush();
      out.add(w);
    }
  }
  if (run.isNotEmpty) flush();
  return out.join(' ');
}

class DocInText {
  const DocInText(this.number, this.kind, this.rest);
  final String number;
  final String kind; // dni | ruc
  /// El dictado sin la parte del documento (para no confundir al intérprete de productos).
  final String rest;
}

/// Busca un RUC o DNI en el dictado. Primero tras la palabra RUC/DNI ("RUC 20 100 070 970"), luego un RUC suelto válido.
DocInText? extractDoc(String text) {
  final t = normalizeSpokenDigits(text);
  final kw = RegExp(r'\b(r\.?\s?u\.?\s?c\.?|d\.?\s?n\.?\s?i\.?|documento)\b[\s:.,#-]*(?:n[uú]mero\s*)?((?:\d[\s.\-]{0,2}){8,11})', caseSensitive: false).firstMatch(t);
  if (kw != null) {
    final digits = kw.group(2)!.replaceAll(RegExp(r'\D'), '');
    final isRuc = kw.group(1)!.toLowerCase().startsWith('r');
    String? number;
    if (isRuc && digits.length >= 11 && rucValid(digits.substring(0, 11))) number = digits.substring(0, 11);
    if (!isRuc && digits.length >= 8) number = digits.substring(0, 8);
    if (number == null && digits.length == 11 && rucValid(digits)) number = digits;
    if (number == null && digits.length == 8) number = digits;
    if (number != null) {
      final rest = (t.substring(0, kw.start) + t.substring(kw.end)).replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      return DocInText(number, number.length == 11 ? 'ruc' : 'dni', rest);
    }
  }
  for (final m in RegExp(r'(?<!\d)(?:10|15|16|17|20)\d{9}(?!\d)').allMatches(t)) {
    final n = m.group(0)!;
    if (rucValid(n)) {
      final rest = (t.substring(0, m.start) + t.substring(m.end)).replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      return DocInText(n, 'ruc', rest);
    }
  }
  return null;
}
