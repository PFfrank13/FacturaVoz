import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/access.dart';

void main() {
  test('ningún rubro ni plan recupera stock denegado u omitido por Hub', () {
    for (final rubro in ['bodega', 'restaurante', 'servicios_tecnicos', 'salon', 'consultorio', 'taller', 'mayorista', 'educacion', 'construccion']) {
      for (final plan in ['BASICO', 'PRO', 'EMPRESA']) {
        for (final value in [false, null, 1, -1, 'true']) {
          final l = LicenseInfo(source: 'hub', mode: 'full', plan: plan, features: {'stock': value});
          expect(planHas(l, 'stock', rubro: rubro), isFalse, reason: '$rubro/$plan/$value');
        }
      }
    }
  });

  test('límites: cerrado ante caché antigua, desarrollo y valores inválidos', () {
    expect(planLimit(const LicenseInfo(source: 'hub', mode: 'full', dev: true, features: {'max_users': -1}), 'max_users'), 0);
    expect(planHas(const LicenseInfo(source: 'hub', mode: 'full', stale: true, features: {'stock': true}), 'stock'), isFalse);
    for (final value in [-2, 1.5, '5', true, null, double.infinity]) {
      expect(planLimit(LicenseInfo(source: 'hub', mode: 'full', features: {'max_users': value}), 'max_users'), 0);
    }
    expect(planLimit(const LicenseInfo(source: 'hub', mode: 'warning', features: {'max_users': -1}), 'max_users'), -1);
  });

  test('la caché no habilita módulos antes de verificar en línea', () {
    final a = Access.instance;
    a.clear();
    a.applyCached({'is_admin': true}, {'enforced': true, 'source': 'hub', 'mode': 'full', 'features': {'stock': true}});
    expect(a.has('stock'), isFalse);
    expect(a.limit('max_users'), 0);
    a.clear();
    expect(a.can('finance'), isFalse);
  });
  test('nunca se desbloquea con estado de desarrollo o licencia no verificada', () {
    expect(planHas(const LicenseInfo(), 'facturar'), isFalse);
    expect(planHas(const LicenseInfo(enforced: false, source: 'dev', mode: 'full', dev: true), 'cobros'), isFalse);
    expect(planHas(const LicenseInfo(enforced: true, source: 'local', mode: 'full'), 'stock'), isFalse);
    expect(planHas(const LicenseInfo(enforced: true, source: 'hub', mode: 'blocked', features: {'stock': true}), 'stock'), isFalse);
  });

  test('v3.4: una licencia local ya no concede NADA, aunque diga full', () {
    const license = LicenseInfo(
      enforced: true, source: 'local', mode: 'full', plan: 'BASICO',
      features: {'stock': true, 'fiados': true, 'caja': true, 'copiloto': false, 'max_users': 1},
    );
    for (final k in ['stock', 'fiados', 'caja', 'facturar']) {
      expect(planHas(license, k), isFalse, reason: k);
    }
    expect(planLimit(license, 'max_users'), 0);
    expect(planHas(const LicenseInfo(enforced: true, source: 'local', mode: 'blocked', features: {'stock': true}), 'stock'), isFalse);
    expect(planHas(const LicenseInfo(enforced: true, source: 'local', mode: 'full', stale: true, features: {'stock': true}), 'stock'), isFalse);
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
