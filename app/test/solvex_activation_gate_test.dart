import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/access.dart';

void main() {
  test('nunca se desbloquea con estado de desarrollo o licencia no verificada', () {
    expect(planHas(const LicenseInfo(), 'facturar'), isFalse);
    expect(planHas(const LicenseInfo(enforced: false, source: 'dev', mode: 'full', dev: true), 'cobros'), isFalse);
    expect(planHas(const LicenseInfo(enforced: true, source: 'local', mode: 'full'), 'stock'), isFalse);
    expect(planHas(const LicenseInfo(enforced: true, source: 'hub', mode: 'blocked', features: {'stock': true}), 'stock'), isFalse);
  });

  test('sólo el Hub concede funciones activas incluidas en el plan', () {
    const l = LicenseInfo(
      enforced: true, source: 'hub', mode: 'full', plan: 'BASICO', dev: false,
      features: {'clientes': true, 'stock': true, 'tienda': false, 'max_users': 2},
    );
    expect(planHas(l, 'clientes', rubro: 'bodega'), isTrue);
    expect(planHas(l, 'stock', rubro: 'bodega'), isTrue);
    expect(planHas(l, 'tienda', rubro: 'bodega'), isFalse);
    expect(planHas(l, 'copiloto', rubro: 'bodega'), isFalse);
    expect(planLimit(l, 'max_users'), 2);
  });
}
