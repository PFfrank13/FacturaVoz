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

  test('rubro fijo: cada rubro ve solo lo suyo + lo común (gastos siempre); cambiar de rubro no se ofrece', () {
    for (final r in rubros) {
      expect(rubroShows(r, 'gastos'), isTrue, reason: '${r.id} gastos');
      expect(rubroShows(r, r.signature), isTrue, reason: '${r.id} estrella');
      expect(rubroShows(r, 'tipo'), isFalse);
      expect(rubroShows(r, 'presentacion'), isFalse);
    }
    expect(rubroShows(rubroFor('bodega'), 'placas'), isFalse);
    expect(rubroShows(rubroFor('taller'), 'fiados'), isFalse);
    expect(rubroShows(null, 'placas'), isTrue); // sin rubro elegido aún: todo visible
    expect(rubroShows(null, 'tipo'), isTrue);
  });

  group('planes por rubro (Básico / Pro con módulo estrella / Empresa todo)', () {
    LicenseInfo lic(String plan) => LicenseInfo(dev: false, source: 'hub', enforced: true, plan: plan, features: const {'facturar': true});

    test('la matriz de la app y la de la base son la misma (private.plan_matrix)', () {
      final sql = File('../backend/supabase/migrations/20261118_v31_planes_por_rubro.sql').readAsStringSync();
      final base = RegExp(r"else array\[([^\]]*)\]\s*\|\|\s*case p_rubro(.*?)else array\[\]::text\[\] end\s*\|\| case when p_plan = 'PRO'", dotAll: true).firstMatch(sql)!;
      final common = RegExp("'([a-z_]+)'").allMatches(base.group(1)!).map((m) => m.group(1)!).toSet();
      final basicBlock = base.group(2)!;
      final proBlock = sql.substring(sql.indexOf("array['copiloto'] || case p_rubro"));
      for (final r in rubros) {
        final b = RegExp("when '${r.id}' then array\\[([^\\]]*)\\]").firstMatch(basicBlock)!;
        final extra = RegExp("'([a-z_]+)'").allMatches(b.group(1)!).map((m) => m.group(1)!).toSet();
        final p = RegExp("when '${r.id}' then array\\['([a-z_]+)'\\]").firstMatch(proBlock)!.group(1)!;
        expect(planMatrix(r.id, 'BASICO'), {...common, ...extra}, reason: '${r.id} básico');
        expect(planMatrix(r.id, 'PRO'), {...common, ...extra, 'copiloto', p}, reason: '${r.id} pro');
        expect(proStar[r.id], p, reason: '${r.id} estrella');
      }
    });

    test('el núcleo de cada rubro está en Básico y cada rubro tiene UNA estrella distinta de lo esencial', () {
      for (final r in rubros) {
        final basico = planMatrix(r.id, 'BASICO')!;
        expect(basico.containsAll(r.core), isTrue, reason: '${r.id} núcleo ⊆ básico');
        final pro = planMatrix(r.id, 'PRO')!;
        expect(pro.difference(basico), {'copiloto', proStar[r.id]!}, reason: '${r.id} pro = básico + copiloto + estrella');
        expect(planMatrix(r.id, 'EMPRESA')!.containsAll(pro), isTrue);
        expect(planMatrix(r.id, 'EMPRESA')!.contains('copiloto_agente'), isTrue);
        expect(pro.contains('copiloto_agente'), isFalse, reason: 'el agente es solo de Empresa');
      }
    });

    test('mismo plan, distinto rubro: desbloquea cosas distintas', () {
      expect(planHas(lic('PRO'), 'fidelizacion', rubro: 'bodega'), isTrue);
      expect(planHas(lic('PRO'), 'fidelizacion', rubro: 'salon'), isFalse);
      expect(planHas(lic('PRO'), 'comisiones', rubro: 'salon'), isTrue);
      expect(planHas(lic('BASICO'), 'copiloto', rubro: 'bodega'), isFalse);
      expect(planHas(lic('PRO'), 'copiloto', rubro: 'taller'), isTrue);
      expect(planHas(lic('PRO'), 'copiloto_agente', rubro: 'bodega'), isFalse);
      expect(planHas(lic('EMPRESA'), 'copiloto_agente', rubro: 'bodega'), isTrue);
    });

    test('complemento (add-on) del Hub: se respeta si no es parte del plan estándar', () {
      const addon = LicenseInfo(dev: false, source: 'hub', enforced: true, plan: 'BASICO', features: {'tienda': true});
      expect(planHas(addon, 'tienda', rubro: 'bodega'), isTrue);
      const noAddon = LicenseInfo(dev: false, source: 'hub', enforced: true, plan: 'PRO', features: {'tienda': true});
      expect(planHas(noAddon, 'tienda', rubro: 'salon'), isFalse); // tienda es de PRO-mayorista: no es complemento
    });

    test('los textos de "mejora tu plan" usan la matriz del rubro', () {
      expect(minPlanFor('fidelizacion', planFeatures, rubro: 'bodega'), 'PRO');
      expect(minPlanFor('fidelizacion', planFeatures, rubro: 'salon'), 'EMPRESA');
      expect(minPlanFor('copiloto_agente', planFeatures, rubro: 'taller'), 'EMPRESA');
      expect(minPlanFor('copiloto', planFeatures, rubro: 'taller'), 'PRO');
    });
  });
}
