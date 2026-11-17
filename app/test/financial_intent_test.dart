import 'package:facturavoz/logic/financial_intent.dart';
import 'package:flutter_test/flutter_test.dart';

class _Net implements Exception {}

class _Dup implements Exception {}

class _Denied implements Exception {}

/// Servidor simulado: filas por id y un interruptor de red.
class _Server {
  final rows = <String, Map<String, dynamic>>{};
  bool online = true;
  bool loseResponse = false; // la base guarda pero la respuesta no llega
  bool deny = false;
  Future<void> send(String table, Map<String, dynamic> row) async {
    if (!online) throw _Net();
    if (deny) throw _Denied();
    if (rows.containsKey(row['id'])) throw _Dup();
    rows[row['id'] as String] = row;
    if (loseResponse) {
      loseResponse = false;
      throw _Net();
    }
  }

  Future<bool> exists(String table, String id) async {
    if (!online) throw _Net();
    return rows.containsKey(id);
  }
}

void main() {
  late _Server server;
  late MemoryIntentStorage storage;
  late FinancialIntents intents;
  var n = 0;
  Future<IntentOutcome> pay(double amount) => intents.record(
        orgId: 'org-a', userId: 'u1', table: 'payments', target: 'invoice:F1', row: {'org_id': 'org-a', 'amount': amount},
        newId: () => 'id-${++n}', send: server.send, exists: server.exists,
        isDuplicate: (e) => e is _Dup, isTransient: (e) => e is _Net);

  setUp(() {
    server = _Server();
    storage = MemoryIntentStorage();
    intents = FinancialIntents(storage);
    n = 0;
  });

  test('respuesta perdida + reintento MANUAL del usuario: un solo cobro', () async {
    server.loseResponse = true;
    await expectLater(pay(40), throwsA(isA<IntentUnknown>()));
    expect(server.rows, hasLength(1), reason: 'la base sí lo guardó');
    expect((await intents.list('u1', 'org-a')).single.state, IntentState.unknown, reason: 'queda pendiente de confirmar');
    // El usuario vuelve a tocar "Cobrar": NO se crea otro; se confirma el anterior.
    expect(await pay(40), IntentOutcome.previousConfirmed);
    expect(server.rows, hasLength(1));
    expect(await intents.list('u1', 'org-a'), isEmpty);
  });

  test('sin internet antes de llegar: al reintentar se envía con el MISMO id', () async {
    server.online = false;
    await expectLater(pay(40), throwsA(isA<IntentUnknown>()));
    expect(server.rows, isEmpty);
    server.online = true;
    expect(await pay(40), IntentOutcome.previousConfirmed, reason: 'se completa el intento anterior, no uno nuevo');
    expect(server.rows.keys, ['id-1']);
  });

  test('cierre de la app: el intento sobrevive en el almacenamiento y se resuelve al volver', () async {
    server.online = false;
    await expectLater(pay(40), throwsA(isA<IntentUnknown>()));
    final reopened = FinancialIntents(storage); // nueva instancia = app reabierta
    final pending = await reopened.list('u1', 'org-a');
    expect(pending.single.id, 'id-1');
    server.online = true;
    expect(await reopened.resolve(pending.single, send: server.send, exists: server.exists, isDuplicate: (e) => e is _Dup, isTransient: (e) => e is _Net), isTrue);
    expect(server.rows.keys, ['id-1']);
    expect(await reopened.list('u1', 'org-a'), isEmpty);
  });

  test('rechazo definitivo (permiso/licencia) no queda pendiente', () async {
    server.deny = true;
    await expectLater(pay(40), throwsA(isA<_Denied>()));
    expect(await intents.list('u1', 'org-a'), isEmpty);
  });

  test('cobro normal: confirmado sin restos', () async {
    expect(await pay(40), IntentOutcome.confirmed);
    expect(await pay(10), IntentOutcome.confirmed, reason: 'un segundo cobro intencional sí se permite cuando no hay dudas');
    expect(server.rows, hasLength(2));
  });

  test('los intentos son por usuario y empresa', () async {
    server.online = false;
    await expectLater(pay(40), throwsA(isA<IntentUnknown>()));
    expect(await intents.list('u1', 'org-b'), isEmpty);
    expect(await intents.list('u2', 'org-a'), isEmpty);
  });
}
