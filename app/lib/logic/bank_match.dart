// Conciliación bancaria básica (Fase 8 · 15): cruza líneas del extracto (CSV/Excel del banco) con facturas por
// cobrar. Lógica pura: puntaje por monto exacto, fecha cercana y nombre del cliente en la descripción.
import 'dart:convert';

class BankLine {
  BankLine({required this.date, required this.description, required this.amount, this.reference = ''});
  final String date; // yyyy-MM-dd
  final String description;
  final double amount; // + ingreso, − egreso
  final String reference;

  /// Huella estable para no importar dos veces la misma línea.
  String get fingerprint => base64Url.encode(utf8.encode('$date|${amount.toStringAsFixed(2)}|${reference.trim()}|${description.trim().toLowerCase()}')).replaceAll('=', '');
}

class Receivable {
  const Receivable({required this.invoiceId, required this.number, required this.client, required this.balance, required this.issueDate});
  final String invoiceId;
  final String number;
  final String client;
  final double balance;
  final String issueDate;
}

class MatchSuggestion {
  const MatchSuggestion(this.line, this.invoice, this.score, this.why);
  final BankLine line;
  final Receivable invoice;
  final double score; // 0..1
  final String why;
}

String _norm(String s) {
  const from = 'áéíóúñü';
  const to = 'aeiounu';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
}

int _days(String a, String b) {
  final da = DateTime.tryParse(a);
  final db = DateTime.tryParse(b);
  if (da == null || db == null) return 999;
  return da.difference(db).inDays.abs();
}

/// Mejor factura para cada ingreso del extracto (solo sugerencias con puntaje ≥ 0.5; el usuario confirma).
List<MatchSuggestion> suggestMatches(List<BankLine> lines, List<Receivable> open) {
  final out = <MatchSuggestion>[];
  final used = <String>{};
  for (final l in lines.where((l) => l.amount > 0)) {
    MatchSuggestion? best;
    for (final r in open) {
      if (used.contains(r.invoiceId)) continue;
      var score = 0.0;
      final why = <String>[];
      final diff = (r.balance - l.amount).abs();
      if (diff < 0.01) {
        score += 0.6;
        why.add('monto exacto');
      } else if (diff <= 1) {
        score += 0.35;
        why.add('monto casi igual');
      } else {
        continue;
      }
      final desc = _norm('${l.description} ${l.reference}');
      final words = _norm(r.client).split(' ').where((w) => w.length >= 4).toList();
      if (words.isNotEmpty && words.where((w) => desc.contains(w)).length >= (words.length >= 2 ? 2 : 1)) {
        score += 0.3;
        why.add('nombre del cliente');
      }
      final numDigits = r.number.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
      if (numDigits.length >= 3 && desc.contains(numDigits)) {
        score += 0.2;
        why.add('número de factura');
      }
      if (_days(l.date, r.issueDate) <= 45) score += 0.1;
      if (best == null || score > best.score) best = MatchSuggestion(l, r, score > 1 ? 1 : score, why.join(' + '));
    }
    if (best != null && best.score >= 0.5) {
      out.add(best);
      used.add(best.invoice.invoiceId);
    }
  }
  return out;
}

/// Lee un extracto ya convertido en tabla (CSV o Excel): detecta fecha, descripción, monto (o abono/cargo) y referencia.
List<BankLine> parseBankTable(List<List<String>> table) {
  if (table.length < 2) return const [];
  String n(String s) => _norm(s).replaceAll(' ', '');
  var hi = 0;
  for (var k = 0; k < table.length && k < 15; k++) {
    final h = table[k].map(n).toList();
    if (h.any((x) => x.contains('fecha')) && h.any((x) => x.contains('monto') || x.contains('importe') || x.contains('abono') || x.contains('cargo'))) {
      hi = k;
      break;
    }
  }
  final h = table[hi].map(n).toList();
  int? col(List<String> keys) {
    for (final k in keys) {
      final i = h.indexWhere((x) => x.contains(k));
      if (i >= 0) return i;
    }
    return null;
  }

  final di = col(['fechaoperacion', 'fecha']);
  final de = col(['descripcion', 'detalle', 'concepto', 'glosa', 'movimiento']);
  final mo = col(['monto', 'importe']);
  final ab = col(['abono', 'ingreso', 'credito']);
  final ca = col(['cargo', 'egreso', 'debito']);
  final re = col(['operacion', 'referencia', 'nrooperacion', 'numero']);
  double? amt(String s) {
    var t = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (t.isEmpty) return null;
    final neg = t.startsWith('-');
    t = t.replaceAll('-', '');
    if (t.contains(',') && t.contains('.')) {
      t = t.lastIndexOf(',') > t.lastIndexOf('.') ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
    } else if (t.contains(',')) {
      t = RegExp(r',\d{1,2}$').hasMatch(t) ? t.replaceAll(',', '.') : t.replaceAll(',', '');
    }
    final v = double.tryParse(t);
    return v == null ? null : (neg ? -v : v);
  }

  String date(String s) {
    final t = s.trim();
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (iso != null) return '${iso[1]}-${iso[2]}-${iso[3]}';
    final dmy = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})').firstMatch(t);
    if (dmy != null) {
      var y = dmy[3]!;
      if (y.length == 2) y = '20$y';
      return '$y-${dmy[2]!.padLeft(2, '0')}-${dmy[1]!.padLeft(2, '0')}';
    }
    return '';
  }

  String cell(List<String> r, int? i) => i == null || i >= r.length ? '' : r[i].trim();
  final out = <BankLine>[];
  for (final r in table.skip(hi + 1)) {
    final d = date(cell(r, di));
    if (d.isEmpty) continue;
    double? v;
    if (mo != null) v = amt(cell(r, mo));
    if (v == null || v == 0) {
      final a = ab == null ? null : amt(cell(r, ab));
      final c = ca == null ? null : amt(cell(r, ca));
      if (a != null && a != 0) {
        v = a.abs();
      } else if (c != null && c != 0) {
        v = -c.abs();
      }
    }
    if (v == null || v == 0) continue;
    out.add(BankLine(date: d, description: cell(r, de), amount: v, reference: cell(r, re)));
  }
  return out;
}
