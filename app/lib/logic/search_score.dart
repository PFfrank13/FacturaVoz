// Buscador universal: puntaje de coincidencia tolerante a tildes, mayúsculas y orden de palabras. Puro y probado.
String fold(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// 0 = no coincide. Más alto = mejor. Todas las palabras de la consulta deben aparecer (en cualquier orden).
double matchScore(String query, String title, {List<String> extra = const []}) {
  final q = fold(query).trim();
  if (q.isEmpty) return 0;
  final t = fold(title);
  final hay = '$t ${extra.map(fold).join(' ')}';
  final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (!words.every(hay.contains)) {
    // Coincidencia por dígitos (DNI/RUC/número de comprobante con o sin guiones)
    final dq = q.replaceAll(RegExp(r'\D'), '');
    if (dq.length >= 3 && hay.replaceAll(RegExp(r'\D'), '').contains(dq)) return 0.4;
    return 0;
  }
  var score = 0.3;
  if (t == q) {
    score += 1;
  } else if (t.startsWith(q)) {
    score += 0.7;
  } else if (t.contains(q)) {
    score += 0.5;
  } else if (words.every(t.contains)) {
    score += 0.35;
  }
  return score;
}
