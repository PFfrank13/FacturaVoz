// Lector mínimo de Excel (.xlsx) sin servidores ni servicios externos: el archivo se abre en el propio teléfono.
// Un .xlsx es un ZIP con XML adentro: se lee la PRIMERA hoja (o la que tenga más filas), los textos compartidos
// y los estilos (para reconocer qué números son fechas). El resultado es una tabla de textos, igual que un CSV.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// ¿Los bytes son un ZIP (xlsx/docx…)? Empieza con "PK\x03\x04".
bool looksLikeZip(Uint8List b) => b.length > 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04;

/// ¿Es un Excel antiguo (.xls, formato binario OLE2)? No se puede leer: hay que guardarlo como .xlsx o .csv.
bool looksLikeOldXls(Uint8List b) => b.length > 8 && b[0] == 0xD0 && b[1] == 0xCF && b[2] == 0x11 && b[3] == 0xE0;

/// Fecha de Excel (número de días desde 1899-12-30) → 'yyyy-MM-dd'. '' si no es una fecha razonable.
String excelSerialToIso(num serial) {
  if (serial < 20000 || serial > 80000) return ''; // 1954..2119
  final d = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// "AB12" → índice de columna 27 (base 0). -1 si no es una referencia válida.
int columnIndex(String ref) {
  var n = 0;
  var seen = false;
  for (final c in ref.codeUnits) {
    if (c >= 65 && c <= 90) {
      n = n * 26 + (c - 64);
      seen = true;
    } else if (c >= 97 && c <= 122) {
      n = n * 26 + (c - 96);
      seen = true;
    } else {
      break;
    }
  }
  return seen ? n - 1 : -1;
}

String _unescape(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);'), (m) {
    final e = m[1]!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
    return code == null ? m[0]! : String.fromCharCode(code);
  });
}

/// Une todo el texto de los nodos `<t>` dentro de un fragmento XML (texto enriquecido incluido).
String _texts(String xml) {
  final b = StringBuffer();
  for (final m in RegExp(r'<(?:\w+:)?t(?:\s[^>]*)?>([\s\S]*?)</(?:\w+:)?t>').allMatches(xml)) {
    b.write(_unescape(m[1]!));
  }
  return b.toString();
}

String? _attr(String tag, String name) {
  final m = RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(tag);
  return m == null ? null : _unescape(m[1]!);
}

/// Textos compartidos (sharedStrings.xml).
List<String> parseSharedStrings(String xml) =>
    [for (final m in RegExp(r'<(?:\w+:)?si(?:\s[^>]*)?>([\s\S]*?)</(?:\w+:)?si>').allMatches(xml)) _texts(m[1]!)];

/// Índices de estilo (atributo s de cada celda) cuyo formato numérico es de fecha.
Set<int> parseDateStyles(String xml) {
  const builtInDate = {14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 30, 36, 45, 46, 47, 50, 57};
  final custom = <int>{};
  for (final m in RegExp(r'<(?:\w+:)?numFmt\s([^>]*)/?>').allMatches(xml)) {
    final id = int.tryParse(_attr(m[1]!, 'numFmtId') ?? '');
    final code = (_attr(m[1]!, 'formatCode') ?? '').toLowerCase().replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]'), '');
    if (id != null && RegExp(r'[dy]').hasMatch(code) && !code.contains('0.0')) custom.add(id);
  }
  final out = <int>{};
  final xfs = RegExp(r'<(?:\w+:)?cellXfs[^>]*>([\s\S]*?)</(?:\w+:)?cellXfs>').firstMatch(xml);
  if (xfs == null) return out;
  var i = 0;
  for (final m in RegExp(r'<(?:\w+:)?xf\s([^>]*?)/?>').allMatches(xfs[1]!)) {
    final id = int.tryParse(_attr(m[1]!, 'numFmtId') ?? '0') ?? 0;
    if (builtInDate.contains(id) || custom.contains(id)) out.add(i);
    i++;
  }
  return out;
}

String _numText(String v) {
  final n = num.tryParse(v);
  if (n == null) return v;
  if (n == n.roundToDouble() && n.abs() < 1e15) return n.toInt().toString();
  // Evita "0.30000000000000004": Excel guarda binario; 10 decimales bastan para montos.
  var s = n.toStringAsFixed(10);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// Filas de una hoja (sheetN.xml) como tabla de textos. Las celdas vacías intermedias quedan como ''.
List<List<String>> parseSheet(String xml, List<String> shared, Set<int> dateStyles, {int maxRows = 250000}) {
  final rows = <List<String>>[];
  final rowRe = RegExp(r'<(?:\w+:)?row(?:\s[^>]*)?>([\s\S]*?)</(?:\w+:)?row>');
  final cellRe = RegExp(r'<(?:\w+:)?c(\s[^>]*?)?(?:/>|>([\s\S]*?)</(?:\w+:)?c>)');
  final vRe = RegExp(r'<(?:\w+:)?v(?:\s[^>]*)?>([\s\S]*?)</(?:\w+:)?v>');
  for (final rm in rowRe.allMatches(xml)) {
    if (rows.length >= maxRows) break;
    final row = <String>[];
    var next = 0;
    for (final cm in cellRe.allMatches(rm[1]!)) {
      final attrs = cm[1] ?? '';
      final body = cm[2] ?? '';
      final ref = _attr(attrs, 'r');
      var col = ref == null ? next : columnIndex(ref);
      if (col < 0) col = next;
      if (col > 400) continue; // columnas absurdas: se ignoran
      while (row.length < col) {
        row.add('');
      }
      final type = _attr(attrs, 't') ?? 'n';
      final style = int.tryParse(_attr(attrs, 's') ?? '');
      final v = vRe.firstMatch(body)?[1];
      String text;
      switch (type) {
        case 's':
          final i = int.tryParse(v ?? '');
          text = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
        case 'inlineStr':
          text = _texts(body);
        case 'str':
        case 'e':
          text = _unescape(v ?? '');
        case 'b':
          text = v == '1' ? 'VERDADERO' : 'FALSO';
        default:
          final raw = _unescape(v ?? '');
          final n = num.tryParse(raw);
          if (n != null && style != null && dateStyles.contains(style)) {
            final iso = excelSerialToIso(n);
            text = iso.isEmpty ? _numText(raw) : iso;
          } else {
            text = raw.isEmpty ? '' : _numText(raw);
          }
      }
      if (row.length == col) {
        row.add(text);
      } else {
        row[col] = text;
      }
      next = col + 1;
    }
    if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

Archive? _unzip(Uint8List bytes) {
  try {
    return ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
}

String _read(Archive a, String name) {
  final f = a.findFile(name);
  if (f == null) return '';
  return utf8.decode(f.content as List<int>, allowMalformed: true);
}

/// Hojas del libro en el orden en que aparecen, con su archivo dentro del ZIP.
List<String> _sheetPaths(Archive a) {
  final wb = _read(a, 'xl/workbook.xml');
  final rels = _read(a, 'xl/_rels/workbook.xml.rels');
  final targets = <String, String>{};
  for (final m in RegExp(r'<(?:\w+:)?Relationship\s([^>]*?)/?>').allMatches(rels)) {
    final id = _attr(m[1]!, 'Id');
    var t = _attr(m[1]!, 'Target');
    if (id == null || t == null) continue;
    if (t.startsWith('/')) {
      t = t.substring(1);
    } else if (!t.startsWith('xl/')) {
      t = 'xl/$t';
    }
    targets[id] = t;
  }
  final out = <String>[];
  for (final m in RegExp(r'<(?:\w+:)?sheet\s([^>]*?)/?>').allMatches(wb)) {
    final id = _attr(m[1]!, 'r:id') ?? RegExp(r'\w+:id="([^"]*)"').firstMatch(m[1]!)?[1];
    final t = id == null ? null : targets[id];
    if (t != null && a.findFile(t) != null) out.add(t);
  }
  if (out.isEmpty) {
    final found = a.files.where((f) => f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)).map((f) => f.name).toList()..sort();
    out.addAll(found);
  }
  return out;
}

/// Lee un .xlsx y devuelve la hoja con más filas (normalmente la de datos). null si no es un Excel válido.
List<List<String>>? readXlsxTable(Uint8List bytes) {
  if (!looksLikeZip(bytes)) return null;
  final a = _unzip(bytes);
  if (a == null) return null;
  final paths = _sheetPaths(a);
  if (paths.isEmpty) return null;
  final shared = parseSharedStrings(_read(a, 'xl/sharedStrings.xml'));
  final dates = parseDateStyles(_read(a, 'xl/styles.xml'));
  List<List<String>>? best;
  for (final p in paths.take(6)) {
    final t = parseSheet(_read(a, p), shared, dates);
    if (best == null || t.length > best.length) best = t;
  }
  return best;
}
