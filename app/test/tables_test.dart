import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/tables.dart';
import 'package:facturavoz/models_v2.dart';

KitchenOrder o(String id, String table, String status, int minAgo, {double qty = 1, DateTime? now}) => KitchenOrder(
      id: id,
      number: id,
      table: table,
      status: status,
      createdAt: (now ?? DateTime(2026, 10, 30, 20)).subtract(Duration(minutes: minAgo)),
      items: [KitchenItem('Plato', qty)],
    );

void main() {
  final now = DateTime(2026, 10, 30, 20);

  test('agrupa por mesa y toma el paso más atrasado y la espera más larga', () {
    final r = summarizeTables([o('1', '3', 'listo', 5), o('2', '3', 'nuevo', 25, qty: 2), o('3', '1', 'preparando', 10)], now: now);
    expect(r.map((e) => e.label), ['3', '1']); // la mesa 3 espera más
    expect(r.first.orders, 2);
    expect(r.first.items, 3);
    expect(r.first.stage, 'nuevo');
    expect(r.first.wait, const Duration(minutes: 25));
  });

  test('ignora pedidos sin mesa y entregados', () {
    final list = [o('1', '', 'nuevo', 5), o('2', '2', 'entregado', 5), o('3', '  ', 'listo', 1)];
    expect(summarizeTables(list, now: now), isEmpty);
    expect(openWithoutTable(list), 2);
  });

  test('waitText', () {
    expect(waitText(Duration.zero), 'recién llegó');
    expect(waitText(const Duration(minutes: 12)), '12 min');
    expect(waitText(const Duration(minutes: 65)), '1 h 05 min');
  });
}
