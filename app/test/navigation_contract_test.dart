import 'package:facturavoz/nav/navigation_contract.dart';
import 'package:facturavoz/permissions.dart';
import 'package:facturavoz/rubros.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

const _rubros = ['bodega', 'restaurante', 'servicios_tecnicos', 'salon', 'consultorio', 'taller', 'mayorista', 'educacion', 'construccion'];

// Copia de my_access_impl().can (20261107_equipo_roles.sql) para probar la traducción sin Supabase.
Map<String, bool> _canFor(String role) {
  final member = role != 'owner' && role != 'admin';
  return {
    'finance': const {'owner', 'admin', 'finanzas'}.contains(role),
    'sell': role != 'tecnico',
    'collect': role != 'tecnico',
    'clients': true,
    'jobs': true,
    'all_jobs': role != 'tecnico',
    'products_edit': const {'owner', 'admin', 'finanzas'}.contains(role),
    'team': !member,
    'settings': !member,
    'license': !member,
    'import': const {'owner', 'admin', 'finanzas'}.contains(role),
  };
}

bool _p(String id, String role, {bool Function(String)? has}) {
  final can = _canFor(role);
  return permits(id, role: role, isAdmin: role == 'owner' || role == 'admin', can: (k) => can[k] ?? false, has: has ?? (_) => true);
}

void main() {
  test('cada destino de la barra de cada rubro tiene contrato de navegación', () {
    for (final r in _rubros) {
      final spec = rubroFor(r)!;
      expect(spec.nav.length, lessThanOrEqualTo(4), reason: 'máximo 4 destinos ($r)');
      for (final d in spec.nav) {
        expect(navContracts.containsKey(d.id), isTrue, reason: '${d.id} en $r sin contrato');
      }
    }
  });

  test('los permisos de los contratos existen', () {
    for (final c in navContracts.values) {
      if (c.permission != null) expect(permissionRules.containsKey(c.permission), isTrue, reason: c.id);
    }
    for (final p in primaryActions.values) {
      expect(permissionRules.containsKey(p.permission), isTrue, reason: p.label);
    }
  });

  test('cada rubro tiene una acción principal con destino válido', () {
    for (final r in _rubros) {
      final p = primaryActionFor(r);
      expect(p, isNotNull, reason: r);
      if (p!.kind == PrimaryKind.feature) {
        expect(featureById(p.featureId!), isNotNull, reason: '${p.featureId} no existe en el catálogo ($r)');
        expect(rubroShows(rubroFor(r), p.featureId!), isTrue, reason: '${p.featureId} no se muestra en $r');
      }
    }
    expect(primaryActionFor('bodega')!.label, 'Vender');
    expect(primaryActionFor('salon')!.label, 'Nueva cita');
    expect(primaryActionFor('taller')!.label, 'Nueva orden');
    expect(primaryActionFor('restaurante')!.label, 'Nuevo pedido');
  });

  test('una función = un nombre: no hay títulos repetidos en el catálogo', () {
    final titles = <String, String>{};
    for (final f in featureCatalog()) {
      expect(titles.containsKey(f.title), isFalse, reason: '"${f.title}" lo usan ${titles[f.title]} y ${f.id}');
      titles[f.title] = f.id;
    }
  });

  test('las funciones del menú de cada rubro existen en el catálogo', () {
    final ids = {for (final f in featureCatalog()) f.id};
    for (final r in _rubros) {
      for (final id in rubroFor(r)!.featureIds) {
        expect(ids.contains(id), isTrue, reason: '$id ($r)');
      }
    }
  });

  group('permisos granulares', () {
    test('denegar por defecto', () {
      expect(_p('no.existe', 'owner'), isFalse);
    });

    test('solo el propietario gestiona la suscripción', () {
      expect(_p('subscription.manage', 'owner'), isTrue);
      expect(_p('subscription.manage', 'admin'), isFalse);
      expect(_p('subscription.manage', 'finanzas'), isFalse);
    });

    test('el cajero vende y cierra caja pero no ve ganancia ni equipo', () {
      expect(_p('sales.create', 'cajero'), isTrue);
      expect(_p('cash.close', 'cajero'), isTrue);
      expect(_p('reports.profit', 'cajero'), isFalse);
      expect(_p('team.manage', 'cajero'), isFalse);
      expect(_p('sales.cancel', 'cajero'), isFalse);
    });

    test('el técnico no vende ni cobra; sí crea órdenes', () {
      expect(_p('sales.create', 'tecnico'), isFalse);
      expect(_p('payments.record', 'tecnico'), isFalse);
      expect(_p('jobs.create', 'tecnico'), isTrue);
      expect(_p('jobs.read_all', 'tecnico'), isFalse);
    });

    test('compras exige administrador', () {
      expect(_p('purchases.create', 'finanzas'), isFalse);
      expect(_p('purchases.create', 'admin'), isTrue);
    });

    test('sin la función contratada no hay permiso', () {
      expect(_p('cash.close', 'owner', has: (f) => f != 'caja'), isFalse);
    });
  });
}
