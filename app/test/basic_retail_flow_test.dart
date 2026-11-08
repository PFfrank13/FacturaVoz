import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/rubros.dart';
import 'package:facturavoz/screens/catalog.dart';

void main() {
  final registry = {for (final feature in featureCatalog()) feature.id: feature};

  test('Basic retail flow contains real destinations for every operational step', () {
    for (final id in const [
      'compras', 'productos', 'pos', 'fiados', 'caja', 'reportes',
      'clientes', 'medios', 'sunat', 'comprobantes', 'pin', 'avisos',
    ]) {
      expect(registry.containsKey(id), isTrue, reason: 'Missing live module: $id');
    }
    expect(registry['compras']!.feature, 'stock');
    expect(registry['compras']!.perm, 'products_edit');
    expect(registry['pos']!.feature, 'facturar');
    expect(registry['caja']!.feature, 'caja');
    expect(registry['fiados']!.feature, 'fiados');
    expect(registry['pin']!.feature, isNull);
  });

  test('Purchasing is discoverable only in the intended retail sectors', () {
    expect(rubroShows(rubroFor('bodega'), 'compras'), isTrue);
    expect(rubroShows(rubroFor('mayorista'), 'compras'), isTrue);
    expect(rubroShows(rubroFor('salon'), 'compras'), isFalse);
    expect(rubroShows(rubroFor('restaurante'), 'compras'), isFalse);
  });

  test('Basic payment confirmation and daily cash closure retain gated live modules', () {
    expect(registry['medios']!.perm, 'settings');
    expect(registry['avisos']!.feature, 'avisos_pago');
    expect(registry['caja']!.perm, 'collect');
    expect(registry['reportes']!.perm, 'finance');
    expect(registry['productos']!.feature, 'stock');
  });
}
