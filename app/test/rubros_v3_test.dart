import 'dart:io';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/business_templates.dart';
import 'package:facturavoz/models_v2.dart';
import 'package:facturavoz/rubros.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:facturavoz/screens/menu.dart' show upgradeLabel;
import 'package:facturavoz/screens/rubro_tools.dart' show splitEven, suggestedOrder;
import 'package:facturavoz/models_pro.dart';
import 'package:facturavoz/services/rubro_apply.dart';
import 'package:flutter_test/flutter_test.dart';

// B5: pruebas por rubro. Cada rubro es una experiencia completa y coherente.
void main() {
  final catalog = {for (final f in featureCatalog()) f.id};

  test('"Otro / personalizado" ya no se puede elegir', () {
    expect(rubros.any((r) => r.id == 'otro'), isFalse);
    expect(rubroFor('otro'), isNull);
    expect(rubroFor(null), isNull);
    expect(rubros.length, 9);
  });

  for (final r in rubros) {
    group(r.name, () {
      test('barra: 4 destinos válidos y distintos (+ micrófono)', () {
        expect(r.nav.length, 4);
        expect(r.nav.map((n) => n.id).toSet().length, 4);
        for (final n in r.nav) {
          expect(navDestinations.contains(n.id), isTrue, reason: n.id);
          expect(n.label.length, lessThanOrEqualTo(10), reason: 'etiqueta corta: ${n.label}');
        }
      });
      test('Inicio: 3–4 accesos que existen', () {
        expect(r.home.length, inInclusiveRange(3, 4));
        for (final id in r.home) {
          expect(catalog.contains(id), isTrue, reason: id);
        }
      });
      test('Menú: todas las funciones existen y la estrella también', () {
        for (final a in r.areas) {
          for (final id in a.features) {
            expect(catalog.contains(id), isTrue, reason: '${a.title}: $id');
          }
        }
        expect(catalog.contains(r.signature), isTrue);
        expect(r.home.contains(r.signature) || r.areas.first.features.contains(r.signature), isTrue);
      });
      test('plantilla de estados, medios de cobro y datos de práctica', () {
        expect(templateFor(r.id).id, r.id);
        expect(templateFor(r.id).statuses, isNotEmpty);
        expect(r.payMethods, isNotEmpty);
        expect(r.practiceProducts.every((p) => p.price > 0), isTrue);
        expect(r.copilotStarters.length, greaterThanOrEqualTo(2));
      });
      test('normas dudosas mandan a "revisar con tu contador/asesor"', () {
        for (final n in r.notes) {
          final low = n.toLowerCase();
          expect(low.contains('contador') || low.contains('asesor') || low.contains('ley') || low.contains('sunat') || low.contains('dni'), isTrue, reason: n);
        }
      });
      test('el núcleo del rubro va en TODOS los planes', () {
        const basicOnly = LicenseInfo(dev: false, source: 'hub', enforced: true, features: {'facturar': true});
        for (final f in r.core) {
          expect(planHas(basicOnly, f, rubro: r.id), isTrue, reason: f);
        }
      });
    });
  }

  test('el núcleo de la app y el de la base son el mismo (private.rubro_core)', () {
    final sql = File('../backend/supabase/migrations/20261115_v3_rubros.sql').readAsStringSync();
    for (final r in rubros) {
      final m = RegExp("when '${r.id}' then array\\[([^\\]]*)\\]").firstMatch(sql);
      expect(m, isNotNull, reason: r.id);
      final keys = RegExp("'([a-z_]+)'").allMatches(m!.group(1)!).map((x) => x.group(1)).toSet();
      expect(keys, r.core, reason: r.id);
    }
  });

  test('lo que el plan no trae dice en qué plan está', () {
    final api = featureById('api')!;
    expect(upgradeLabel(api), 'Disponible en el plan Empresa');
    expect(upgradeLabel(featureById('agenda')!), 'Disponible en el plan Pro');
  });

  test('cambiar de rubro no pierde estados ni datos del cliente', () {
    final s = OrgSettings(
      businessType: 'salon',
      jobStatuses: [const JobStatus('nuevo', 'Por confirmar'), const JobStatus('no_vino', 'No vino')],
      clientFields: [const ClientField('preferencias', 'Preferencias')],
      labels: {'job': 'Cita', 'otro': 'x'},
    );
    final m = mergeRubro(s, 'taller');
    expect(m.businessType, 'taller');
    expect(m.jobStatuses.map((x) => x.key), containsAll(['diagnostico', 'listo', 'no_vino']));
    expect(m.clientFields.map((f) => f.key), containsAll(['placa', 'preferencias']));
    expect(m.labels.containsKey('job'), isFalse);
    expect(m.labels['otro'], 'x');
  });

  test('restaurante: la cuenta dividida siempre suma el total', () {
    for (final total in [100.0, 99.99, 47.5, 10.0]) {
      for (var n = 1; n <= 7; n++) {
        final p = splitEven(total, n);
        expect(p.length, n);
        expect((p.fold(0.0, (a, b) => a + b) * 100).round(), (total * 100).round());
      }
    }
  });

  test('bodega: reposición sugerida', () {
    const v = ProductVelocity(id: 'x', name: 'Arroz', stock: 4, reorderPoint: 5, units: 60, perDay: 2);
    expect(suggestedOrder(v, days: 14), 24); // 2×14 − 4
    const lento = ProductVelocity(id: 'y', name: 'Sal', stock: 1, reorderPoint: 3, units: 0, perDay: 0);
    expect(suggestedOrder(lento), 2); // al menos hasta el punto de pedido
  });
}
