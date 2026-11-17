import 'package:facturavoz/logic/idempotent.dart';
import 'package:flutter_test/flutter_test.dart';

class _Net implements Exception {}

class _Dup implements Exception {}

class _Denied implements Exception {}

void main() {
  final saved = <String>[];
  Future<void> run(Future<void> Function() op) => runIdempotent(op, isDuplicate: (e) => e is _Dup, isTransient: (e) => e is _Net, wait: Duration.zero);

  setUp(saved.clear);

  test('si la red falla DESPUÉS de guardar, el reintento choca con el id y se registra una sola vez', () async {
    var calls = 0;
    await run(() async {
      calls++;
      if (calls == 1) {
        saved.add('cobro-1'); // la base sí lo guardó
        throw _Net(); // pero la respuesta no llegó
      }
      if (saved.contains('cobro-1')) throw _Dup();
      saved.add('cobro-1');
    });
    expect(saved, ['cobro-1']);
    expect(calls, 2);
  });

  test('si la red falla ANTES de guardar, el reintento lo guarda', () async {
    var calls = 0;
    await run(() async {
      calls++;
      if (calls == 1) throw _Net();
      saved.add('abono');
    });
    expect(saved, ['abono']);
  });

  test('un permiso denegado no se reintenta', () async {
    var calls = 0;
    await expectLater(run(() async {
      calls++;
      throw _Denied();
    }), throwsA(isA<_Denied>()));
    expect(calls, 1);
  });

  test('un duplicado en el PRIMER intento no se oculta', () async {
    await expectLater(run(() async => throw _Dup()), throwsA(isA<_Dup>()));
  });

  test('sin red persistente, se rinde y avisa', () async {
    var calls = 0;
    await expectLater(run(() async {
      calls++;
      throw _Net();
    }), throwsA(isA<_Net>()));
    expect(calls, 2);
  });
}
