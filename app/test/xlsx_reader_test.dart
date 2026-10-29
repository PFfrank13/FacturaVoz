import 'dart:typed_data';

import 'package:facturavoz/import_logic.dart';
import 'package:facturavoz/xlsx_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('referencias de columna y fechas de Excel', () {
    expect(columnIndex('A1'), 0);
    expect(columnIndex('H7'), 7);
    expect(columnIndex('AB12'), 27);
    expect(columnIndex('12'), -1);
    expect(excelSerialToIso(46037), '2026-01-15');
    expect(excelSerialToIso(5), '');
  });

  test('textos compartidos con texto enriquecido y entidades', () {
    const xml = '<sst><si><t>Fecha</t></si><si><r><rPr><b/></rPr><t>Cli</t></r><r><t xml:space="preserve">ente</t></r></si>'
        '<si><t>Pérez &amp; Cía</t></si></sst>';
    expect(parseSharedStrings(xml), ['Fecha', 'Cliente', 'Pérez & Cía']);
  });

  test('estilos de fecha (incorporados y personalizados)', () {
    const xml = '<styleSheet><numFmts count="1"><numFmt numFmtId="165" formatCode="dd/mm/yyyy;@"/></numFmts>'
        '<cellXfs count="4"><xf numFmtId="0"/><xf numFmtId="165" applyNumberFormat="1"/><xf numFmtId="4"/><xf numFmtId="14"/></cellXfs></styleSheet>';
    expect(parseDateStyles(xml), {1, 3});
  });

  test('hoja con celdas vacías, textos compartidos, en línea, fechas y decimales', () {
    const sheet = '<worksheet><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
        '<row r="2"><c r="A2" s="1"><v>46037</v></c><c r="B2" t="inlineStr"><is><t>ACME &amp; Hijos</t></is></c><c r="C2"><v>1234.5</v></c></row>'
        '<row r="3"><c r="A3" s="1"/><c r="C3"><v>0.30000000000000004</v></c></row>'
        '</sheetData></worksheet>';
    final t = parseSheet(sheet, ['Fecha', 'Total'], {1});
    expect(t[0], ['Fecha', '', 'Total']);
    expect(t[1], ['2026-01-15', 'ACME & Hijos', '1234.5']);
    expect(t[2], ['', '', '0.3']);
  });

  test('encabezados que no están en la primera fila (títulos arriba) y fecha como número de Excel', () {
    final p = parseImportTable([
      ['Reporte de ventas 2026'],
      [],
      ['Fecha de Emisión', 'Serie', 'Número', 'Nro Doc Identidad', 'Razón Social', 'Descripción', 'Moneda', 'Importe Total'],
      ['46037', 'F001', '123', '20480072872', 'ACME SAC', 'Instalación', 'PEN', '1180'],
      ['2026-01-16', 'F001', '124', '20480072872', 'ACME SAC', 'Soporte', 'USD', '100.5'],
    ]);
    expect(p.error, isNull);
    expect(p.rows.length, 2);
    expect(p.rows.first.date, '2026-01-15');
    expect(p.rows.first.number, 'F001-123');
    expect(p.rows.last.currency, 'USD');
  });

  test('reconoce un ZIP y un .xls antiguo por su firma', () {
    expect(looksLikeOldXls(Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0])), isTrue);
    expect(looksLikeZip(Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0])), isTrue);
    expect(readXlsxTable(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
