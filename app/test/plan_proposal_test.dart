import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/access.dart';
import '../tool/plans/proposal.dart';
import '../tool/plans/main.dart';

ProposedFeature feature(String id) => proposedFeatures.singleWhere((f) => f.id == id);

Set<String> localGraph(String entry) {
  final visited = <String>{};
  void visit(String file) {
    final path = File(file).absolute.uri.normalizePath().toFilePath();
    if (!visited.add(path)) return;
    final text = File(path).readAsStringSync();
    for (final m in RegExp(r'''(?:import|export|part)\s+['"]([^'"]+)['"]''').allMatches(text)) {
      final uri = m[1]!;
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:facturavoz/')) {
        visit('lib/${uri.substring('package:facturavoz/'.length)}');
      } else if (!uri.startsWith('package:')) {
        visit(File(path).parent.uri.resolve(uri).toFilePath());
      }
    }
  }
  visit(entry);
  return visited;
}

void main() {
  test('single matrix, existing destination evidence and unique IDs', () {
    expect(proposedFeatures.map((f) => f.id).toSet().length, proposedFeatures.length);
    for (final f in proposedFeatures) {
      if (f.file == '-') { expect(f.pending, isTrue); continue; }
      final code = File('lib/screens/${f.file}').readAsStringSync();
      expect(code.contains('class ${f.destination} '), isTrue, reason: f.id);
    }
  });
  test('progressive plan goals and separate voice/copilot', () {
    expect(trialDecision(feature('voz'), TrialPlan.basico, TrialRole.cajero), TrialDecision.allowed);
    expect(trialDecision(feature('copiloto'), TrialPlan.basico, TrialRole.propietario), TrialDecision.upgrade);
    expect(trialDecision(feature('copiloto'), TrialPlan.pro, TrialRole.propietario), TrialDecision.allowed);
    expect(trialHome(TrialPlan.basico, TrialRole.propietario).any((f) => f.id == 'multisucursal'), isFalse);
    expect(trialHome(TrialPlan.pro, TrialRole.propietario).any((f) => f.id == 'api'), isFalse);
    expect(trialHome(TrialPlan.empresa, TrialRole.propietario).any((f) => f.id == 'multisucursal'), isTrue);
    expect(trialDecision(feature('multisucursal'), TrialPlan.empresa, TrialRole.propietario), TrialDecision.pending);
  });
  test('every higher-tier feature uses the upgrade path for an authorized owner', () {
    for (final p in TrialPlan.values) {
      for (final f in proposedFeatures.where((f) => f.minimum.index > p.index)) {
        expect(trialDecision(f, p, TrialRole.propietario), TrialDecision.upgrade, reason: '${p.name}/${f.id}');
      }
    }
  });
  for (final p in TrialPlan.values) {
    testWidgets('${p.name}: selector, role change and comparison use the same matrix', (tester) async {
      await tester.pumpWidget(const PlansLab());
      await tester.tap(find.byType(DropdownButtonFormField<TrialPlan>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(proposals[p]!.label).last);
      await tester.pumpAndSettle();
      expect(find.text('${proposals[p]!.experience} · ${proposals[p]!.users} usuarios · ${proposals[p]!.branches} sucursales'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<TrialRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cajero').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menú'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('compras')), 300);
      await tester.tap(find.byKey(const ValueKey('compras')));
      await tester.pumpAndSettle();
      expect(find.text('Permiso de trabajador requerido'), findsOneWidget);
      expect(find.text('Ver planes'), findsNothing);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  for (final p in TrialPlan.values) {
    for (final r in TrialRole.values) {
      test('${p.name}/${r.name}: role wins over upsell; no locked home entries', () {
        for (final f in trialHome(p, r)) {
          expect(f.minimum.index <= p.index, isTrue);
          expect(trialRoleAllows(r, f.permission), isTrue);
        }
        if (r == TrialRole.cajero) {
          expect(trialDecision(feature('api'), p, r), TrialDecision.roleDenied);
          expect(trialDecision(feature('compras'), p, r), TrialDecision.roleDenied);
        }
      });
    }
  }
  test('limits are proposals, exact threshold and no negative usage accepted by UI', () {
    expect(proposals.values.map((p) => p.users), [1, 5, 20]);
    expect(proposals.values.map((p) => p.branches), [1, 1, 5]);
    expect(trialDecision(feature('equipo'), TrialPlan.pro, TrialRole.administrador, users: 4), TrialDecision.allowed);
    expect(trialDecision(feature('equipo'), TrialPlan.pro, TrialRole.administrador, users: 5), TrialDecision.limitReached);
    expect(trialDecision(feature('multisucursal'), TrialPlan.empresa, TrialRole.propietario, branches: 5), TrialDecision.limitReached);
  });
  test('lab imports no operational services and production cannot reach lab', () {
    final production = localGraph('lib/main.dart');
    expect(production.any((p) => p.contains('${Platform.pathSeparator}tool${Platform.pathSeparator}plans')), isFalse);
    final lab = localGraph('tool/plans/main.dart');
    for (final p in lab) {
      final code = File(p).readAsStringSync();
      expect(RegExp(r'''import\s+['"](?:dart:io|package:(?:http|supabase_flutter|url_launcher)/)''').hasMatch(code), isFalse, reason: p);
      expect(p.endsWith('access.dart'), isFalse);
      expect(p.contains('${Platform.pathSeparator}services${Platform.pathSeparator}'), isFalse);
    }
    final entry = File('tool/plans/main.dart').readAsStringSync();
    expect(entry.contains("if (!kDebugMode) throw UnsupportedError"), isTrue);
  });
  testWidgets('premium lock opens comparison, without changing real Access', (tester) async {
    final before = Access.instance.license;
    await tester.pumpWidget(const PlansLab());
    await tester.tap(find.text('Menú'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('copiloto')), 400);
    await tester.tap(find.byKey(const ValueKey('copiloto')));
    await tester.pumpAndSettle();
    expect(find.text('Actualiza tu plan'), findsOneWidget);
    await tester.tap(find.text('Ver planes'));
    await tester.pumpAndSettle();
    expect(find.text('Comparación propuesta'), findsOneWidget);
    expect(find.text('Empresa'), findsOneWidget);
    expect(identical(Access.instance.license, before), isTrue);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Comparación propuesta'), findsNothing);
  });
}
