import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/services/print/printer_scope.dart';

void main() {
  test('impresora se guarda bajo la empresa exacta, no un key global', () {
    final a = printerStorageKey('00000000-0000-4000-8000-000000000001');
    final b = printerStorageKey('00000000-0000-4000-8000-000000000002');
    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(a, isNot(b));
    expect(a, startsWith('fv_printer_v3_org_'));
    expect(a, isNot('fv_printer_v2'));
  });

  test('sin empresa no existe impresora directa recuperable', () {
    expect(printerStorageKey(null), isNull);
    expect(printerStorageKey(''), isNull);
    expect(printerStorageKey('   '), isNull);
  });

  test('una misma empresa conserva la clave aunque haya espacios accidentales', () {
    expect(printerStorageKey('org-A'), printerStorageKey(' org-A '));
  });

  test('un cambio de A a B y de vuelta no reutiliza la impresora de B', () {
    final first = printerStorageKey('org-A');
    final second = printerStorageKey('org-B');
    expect(second, isNot(first));
    expect(printerStorageKey('org-A'), first);
  });
  test('red ESC/POS conserva host/puerto real y el default 9100', () {
    final defaultPort = parsePrinterEndpoint('192.168.1.50');
    expect(defaultPort.host, '192.168.1.50');
    expect(defaultPort.port, 9100);
    final custom = parsePrinterEndpoint(' printer.local:9101 ');
    expect(custom.host, 'printer.local');
    expect(custom.port, 9101);
  });

  test('red rechaza IP vacía y puertos incorrectos sin fallback silencioso', () {
    for (final address in [
      '', '   ', '192.168.0.1:0', '192.168.0.1:65536',
      '192.168.0.1:abc', '192.168.0.1:9100:extra',
      'some host:9100', '192.168.0.1/-x',
    ]) {
      expect(() => parsePrinterEndpoint(address), throwsStateError,
          reason: 'No enviar datos a un host/puerto no validado: $address');
    }
  });

}
