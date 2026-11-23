import 'dart:convert';
import 'dart:io';

import 'package:facturavoz/rubros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los precios de la app coinciden con docs/facturavoz-planes.json', () {
    final j = jsonDecode(File('../docs/facturavoz-planes.json').readAsStringSync()) as Map<String, dynamic>;
    for (final p in j['plans'] as List) {
      final m = p as Map<String, dynamic>;
      expect(planPrices[m['code']], double.parse(m['price'] as String), reason: 'precio de ${m['code']}');
    }
  });

  test('límites y días de prueba de la app coinciden con docs/facturavoz-planes.json', () {
    final j = jsonDecode(File('../docs/facturavoz-planes.json').readAsStringSync()) as Map<String, dynamic>;
    for (final p in j['plans'] as List) {
      final m = p as Map<String, dynamic>;
      final f = m['features'] as Map<String, dynamic>;
      expect(planLimits[m['code']]!.users, f['max_users'], reason: 'usuarios ${m['code']}');
      expect(planLimits[m['code']]!.branches, f['max_branches'], reason: 'sucursales ${m['code']}');
      expect(planTrialDays[m['code']], m['trial_days'], reason: 'prueba ${m['code']}');
    }
  });

  test('valores comerciales confirmados en Solvex Hub (22/11/2026)', () {
    expect(planLimits['BASICO'], (users: 2, branches: 1));
    expect(planLimits['PRO'], (users: 5, branches: 1));
    expect(planLimits['EMPRESA'], (users: 20, branches: 5));
    expect(planTrialDays.values.every((d) => d >= 7), isTrue);
  });

  test('texto de precio', () {
    expect(planPriceText('BASICO'), 'S/ 39 al mes');
    expect(planPriceText('PRO'), 'S/ 79 al mes');
    expect(planPriceText('EMPRESA'), 'S/ 179 al mes');
    expect(planPriceText('XYZ'), '');
  });

  test('herramientas nuevas por plan: cada plan suma sobre el anterior y nada se repite', () {
    for (final r in ['bodega', 'restaurante', 'servicios_tecnicos', 'salon', 'consultorio', 'taller', 'mayorista', 'educacion', 'construccion']) {
      final b = planNewTools(r, 'BASICO').toSet();
      final p = planNewTools(r, 'PRO').toSet();
      final e = planNewTools(r, 'EMPRESA').toSet();
      expect(b.intersection(p), isEmpty, reason: r);
      expect(p.intersection(e), isEmpty, reason: r);
      expect({...b, ...p, ...e}, allFeatureKeys, reason: 'al final Empresa lo tiene todo ($r)');
      expect(p, contains('copiloto'), reason: r);
      expect(p, contains(proStar[r]), reason: r);
      expect(e, contains('copiloto_agente'), reason: r);
    }
  });

  test('rubro desconocido: sin herramientas por rubro', () {
    expect(planNewTools(null, 'PRO'), isEmpty);
    expect(planNewTools('otro', 'PRO'), isEmpty);
  });
}
