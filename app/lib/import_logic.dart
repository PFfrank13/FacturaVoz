// Lectura de archivos de comprobantes históricos (CSV/TXT del portal de SUNAT o de otro sistema).
// Lógica pura y probada: detecta separador, columnas (cliente, servicio, importe, fecha, número) y limpia los valores.
import 'dart:convert';
import 'dart:typed_data';

const maxImportRows = 200000;

class ImportRow {
  const ImportRow({required this.client, required this.amount, this.taxId = '', this.description = '', this.number = '', this.date = '', this.currency = 'PEN'});
  final String client;
  final String taxId;
  final String description;
  final String number;
  final String date; // yyyy-MM-dd o vacío
  final String currency;
  final double amount;

  Map<String, Object> toJson() => {
        'client': client,
        'tax_id': taxId,
        'description': description,
        'number': number,
        'date': date,
        'currency': currency,
        'amount': amount.toStringAsFixed(2),
      };
}

class ParsedImport {
  const ParsedImport({required this.rows, required this.rejected, required this.columns, this.error});
  final List<ImportRow> rows;
  final int rejected;

  /// Qué encabezado del archivo se usó para cada dato (para mostrárselo al usuario).
  final Map<String, String> columns;
  final String? error;
}

/// UTF-8 y, si el archivo viene en Windows-1252/Latin-1 (común en SUNAT), Latin-1.
String decodeImportBytes(Uint8List bytes) {
  final u = utf8.decode(bytes, allowMalformed: true);
  final bad = '�'.allMatches(u).length;
  final text = bad > 3 ? latin1.decode(bytes) : u;
  return text.startsWith('﻿') ? text.substring(1) : text;
}

String _norm(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
  const to = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String detectDelimiter(String firstLine) {
  var best = ',';
  var bestCount = 0;
  for (final d in [',', ';', '|', '\t']) {
    final n = d.allMatches(firstLine).length;
    if (n > bestCount) {
      best = d;
      bestCount = n;
    }
  }
  return best;
}

/// CSV con comillas ("a;b" y "" escapada). Tolera saltos de línea dentro de comillas.
List<List<String>> parseCsv(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == delimiter) {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// "S/ 1,234.56", "1.234,56", "1234,5" → 1234.56. null si no es un número.
double? parseAmount(String raw) {
  var s = raw.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (s.isEmpty || s == '-' || s.startsWith('-')) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    final decimalIsComma = lastComma > lastDot;
    s = decimalIsComma ? s.replaceAll('.', '').replaceAll(',', '.') : s.replaceAll(',', '');
  } else if (lastComma >= 0) {
    final after = s.length - lastComma - 1;
    s = (after == 3 && s.indexOf(',') == lastComma && lastComma > 0 && s.length > 4) ? s.replaceAll(',', '') : s.replaceAll(',', '.');
  } else if (lastDot >= 0 && s.indexOf('.') != lastDot) {
    s = s.replaceAll('.', ''); // 1.234.567
  }
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v.isInfinite || v <= 0 || v > 99999999) return null;
  return v;
}

/// dd/MM/yyyy, dd-MM-yyyy o yyyy-MM-dd → yyyy-MM-dd ('' si no se entiende).
String parseDateIso(String raw) {
  final s = raw.trim();
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  final dmy = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})').firstMatch(s);
  int? y, m, d;
  if (iso != null) {
    y = int.parse(iso[1]!);
    m = int.parse(iso[2]!);
    d = int.parse(iso[3]!);
  } else if (dmy != null) {
    d = int.parse(dmy[1]!);
    m = int.parse(dmy[2]!);
    y = int.parse(dmy[3]!);
  }
  if (y == null || m == null || d == null || y < 1990 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return '';
  final dt = DateTime(y, m, d);
  if (dt.month != m) return '';
  return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

int? _find(List<String> headers, List<String> exact, List<String> contains, {Set<int> taken = const {}}) {
  for (final e in exact) {
    final i = headers.indexOf(e);
    if (i >= 0 && !taken.contains(i)) return i;
  }
  for (final c in contains) {
    for (var i = 0; i < headers.length; i++) {
      if (!taken.contains(i) && headers[i].contains(c)) return i;
    }
  }
  return null;
}

ParsedImport parseImportText(String text) {
  final firstLine = text.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) return const ParsedImport(rows: [], rejected: 0, columns: {}, error: 'El archivo está vacío.');
  final table = parseCsv(text, detectDelimiter(firstLine));
  if (table.length < 2) return const ParsedImport(rows: [], rejected: 0, columns: {}, error: 'No encontramos filas con datos.');
  final raw = table.first.map((h) => h.trim()).toList();
  final h = raw.map(_norm).toList();

  final taken = <int>{};
  int? pick(List<String> exact, List<String> contains) {
    final i = _find(h, exact, contains, taken: taken);
    if (i != null) taken.add(i);
    return i;
  }

  final amountI = pick(['importetotal', 'totalcp', 'montototal', 'total', 'importe', 'monto'], ['importetotal', 'total', 'importe', 'monto']);
  final clientI = pick(['cliente', 'razonsocial', 'denominacion', 'nombre', 'nombrecliente'], ['razonsocial', 'cliente', 'denominacion', 'nombre']);
  final taxI = pick(['ruc', 'dni', 'nrodocidentidad', 'numerodocumentoidentidad', 'nrodocumentoidentidad', 'docidentidad'], ['docidentidad', 'ruc', 'dni']);
  final descI = pick(['servicio', 'descripcion', 'concepto', 'detalle', 'glosa', 'producto'], ['servicio', 'descripcion', 'concepto', 'glosa']);
  final dateI = pick(['fechaemision', 'fechadeemision', 'femision', 'fecha'], ['fechaemision', 'fecha']);
  final curI = pick(['moneda', 'mon'], ['moneda']);
  final serieI = pick(['serie', 'seriecp', 'seriedecomprobante'], []);
  final numI = pick(['numerodecomprobante', 'nrocomprobante', 'nrocp', 'numerocp', 'numero', 'correlativo', 'nrodocumento', 'comprobante'], ['numerocp', 'nrocp', 'comprobante']);

  if (amountI == null) {
    return const ParsedImport(rows: [], rejected: 0, columns: {}, error: 'No encontramos la columna del importe (por ejemplo "Importe total" o "Total").');
  }
  if (clientI == null && descI == null) {
    return const ParsedImport(rows: [], rejected: 0, columns: {}, error: 'No encontramos la columna del cliente ni la del servicio.');
  }

  String cell(List<String> r, int? i) => (i == null || i >= r.length) ? '' : r[i].trim();
  final out = <ImportRow>[];
  var rejected = 0;
  for (var k = 1; k < table.length; k++) {
    if (out.length >= maxImportRows) {
      rejected += table.length - k;
      break;
    }
    final r = table[k];
    final amount = parseAmount(cell(r, amountI));
    if (amount == null) {
      rejected++;
      continue;
    }
    var number = cell(r, numI);
    final serie = cell(r, serieI);
    if (serie.isNotEmpty && number.isNotEmpty && !number.contains('-')) number = '$serie-$number';
    final cur = cell(r, curI).toUpperCase();
    out.add(ImportRow(
      client: cell(r, clientI),
      taxId: cell(r, taxI),
      description: cell(r, descI),
      number: number,
      date: parseDateIso(cell(r, dateI)),
      currency: (cur == 'USD' || cur == 'DOLARES' || cur == 'US\$') ? 'USD' : 'PEN',
      amount: amount,
    ));
  }
  String name(int? i) => i == null ? '' : raw[i];
  return ParsedImport(
    rows: out,
    rejected: rejected,
    columns: {
      'Cliente': name(clientI),
      'Servicio': name(descI),
      'Importe': name(amountI),
      'Fecha': name(dateI),
      'Número': numI == null ? '' : (serieI == null ? name(numI) : '${name(serieI)} + ${name(numI)}'),
    },
  );
}
