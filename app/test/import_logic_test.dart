import 'package:facturavoz/import_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('importes en varios formatos', () {
    expect(parseAmount('S/ 1,234.56'), 1234.56);
    expect(parseAmount('1.234,56'), 1234.56);
    expect(parseAmount('1234,5'), 1234.5);
    expect(parseAmount('1,500'), 1500);
    expect(parseAmount('10.50'), 10.5);
    expect(parseAmount('1.234.567'), 1234567);
    expect(parseAmount('abc'), isNull);
    expect(parseAmount('0'), isNull);
    expect(parseAmount('-5'), isNull);
  });

  test('fechas', () {
    expect(parseDateIso('26/10/2026'), '2026-10-26');
    expect(parseDateIso('2026-10-26 10:00:00'), '2026-10-26');
    expect(parseDateIso('31/02/2026'), '');
    expect(parseDateIso('basura'), '');
  });

  test('CSV con comillas y separador punto y coma', () {
    final t = parseCsv('a;b;c\n"x;1";"he said ""hi""";3\n', ';');
    expect(t[1], ['x;1', 'he said "hi"', '3']);
  });

  test('detecta columnas de un archivo tipo SUNAT y descarta filas sin importe', () {
    const csv = 'Fecha de Emisión;Serie;Número;Nro Doc Identidad;Apellidos y Nombres / Razón Social;Descripción;Moneda;Importe Total\n'
        '15/01/2026;F001;123;20480072872;ACME SAC;Instalación de software;PEN;"1,180.00"\n'
        '16/01/2026;F001;124;20480072872;ACME SAC;Soporte;USD;100.00\n'
        '17/01/2026;F001;125;;SIN IMPORTE;Nada;PEN;\n';
    final p = parseImportText(csv);
    expect(p.error, isNull);
    expect(p.rows.length, 2);
    expect(p.rejected, 1);
    expect(p.rows.first.client, 'ACME SAC');
    expect(p.rows.first.number, 'F001-123');
    expect(p.rows.first.amount, 1180);
    expect(p.rows.first.date, '2026-01-15');
    expect(p.rows.first.taxId, '20480072872');
    expect(p.rows[1].currency, 'USD');
  });

  test('errores claros', () {
    expect(parseImportText('').error, isNotNull);
    expect(parseImportText('cliente,servicio\nA,B').error, contains('importe'));
    expect(parseImportText('foo,importe\n1,2').error, contains('cliente'));
  });
}
