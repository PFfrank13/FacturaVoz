import 'package:facturavoz/nav/role_matrix.dart';
import 'package:facturavoz/rubros.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const _rubros = ['bodega', 'restaurante', 'servicios_tecnicos', 'salon', 'consultorio', 'taller', 'mayorista', 'educacion', 'construccion'];
const _money = {'reports.view', 'reports.profit', 'cash.read_all', 'payments.refund', 'sales.cancel'};

void main() {
  final catalogIds = {for (final f in featureCatalog()) f.id};

  test('cada bloque de Inicio apunta a una función existente', () {
    for (final b in homeBlocks.values) {
      if (b.route != null) expect(catalogIds.contains(b.route), isTrue, reason: '${b.id} → ${b.route}');
    }
  });

  test('cada rol usa bloques conocidos y un rol base real', () {
    for (final r in _rubros) {
      for (final role in rolesFor(r)) {
        expect(const {'owner', 'admin', 'finanzas', 'cajero', 'vendedor', 'tecnico'}.contains(role.base), isTrue, reason: '${role.id} ($r)');
        for (final h in role.home) {
          expect(homeBlocks.containsKey(h), isTrue, reason: '$h en ${role.id} ($r)');
        }
        if (!role.exact) expect(role.gap, isNotEmpty, reason: 'rol aproximado sin explicar: ${role.id} ($r)');
      }
    }
  });

  test('matriz 9 rubros × 3 planes × roles: reglas de seguridad', () {
    var combos = 0;
    for (final r in _rubros) {
      for (final plan in planCodes) {
        for (final role in rolesFor(r)) {
          final e = simulateExperience(r, plan, role);
          combos++;
          expect(e.nav.length, lessThanOrEqualTo(4), reason: '$r/$plan/${role.id}');
          expect(e.approvals.every(e.allowed.contains), isTrue);
          expect({...e.allowed, ...e.restricted}.length, e.allowed.length + e.restricted.length);
          if (role.base == 'tecnico') {
            expect(e.allowed.toSet().intersection({..._money, 'payments.record', 'sales.create'}), isEmpty, reason: 'técnico con dinero: $r/${role.id}');
          }
          if (role.base == 'cajero' || role.base == 'vendedor') {
            expect(e.allowed.toSet().intersection(_money), isEmpty, reason: '$r/${role.id} ve dinero del negocio');
            expect(e.home, isNot(contains('margin')));
          }
          if (role.base != 'owner') expect(e.allowed, isNot(contains('subscription.manage')));
          if (role.base != 'owner' && role.base != 'admin') expect(e.allowed, isNot(contains('team.manage')));
        }
      }
    }
    expect(combos, greaterThan(9 * 3 * 3));
  });

  test('el propietario de cada rubro tiene Inicio y barra completos en Empresa', () {
    for (final r in _rubros) {
      final owner = rolesFor(r).first;
      final e = simulateExperience(r, 'EMPRESA', owner);
      expect(e.nav.length, rubroFor(r)!.nav.length, reason: r);
      expect(e.home, isNotEmpty);
      expect(e.allowed, contains('subscription.manage'));
    }
  });

  test('bodega Básico: el dueño ve caja, fiados, stock y margen; el cajero solo su caja', () {
    final roles = {for (final x in rolesFor('bodega')) x.id: x};
    final owner = simulateExperience('bodega', 'BASICO', roles['propietario']!);
    expect(owner.home, containsAll(['today_sales', 'cash_status', 'fiados_total', 'stock_low', 'margin', 'reports']));
    final cashier = simulateExperience('bodega', 'BASICO', roles['cajero']!);
    expect(cashier.home, ['sell_cta', 'cash_status', 'last_ops', 'stock_low']);
    expect(cashier.nav, containsAll(['sell', 'cash']));
  });

  test('sin la función del plan el bloque desaparece', () {
    final owner = rolesFor('bodega').first;
    // Bodega no trae trabajos en ningún plan menor que Empresa.
    expect(simulateExperience('bodega', 'BASICO', owner).home, isNot(contains('all_jobs')));
    expect(simulateExperience('bodega', 'EMPRESA', owner).home, contains('all_jobs'));
  });

  test('el rol del usuario se resuelve a un preset de su rubro', () {
    expect(roleForUser('salon', 'tecnico').id, 'barbero');
    expect(roleForUser('taller', 'tecnico').id, 'mecanico');
    expect(roleForUser('bodega', 'cajero').id, 'cajero');
    expect(roleForUser('bodega', 'owner').id, 'propietario');
    expect(roleForUser(null, 'cajero').base, 'cajero');
  });
}
