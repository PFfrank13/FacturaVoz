import 'package:facturavoz/services/retail_purchase.dart';
import 'package:facturavoz/services/stock_lots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vencimientos', () {
    test('clasifica por urgencia como la web', () {
      expect(expiryBucket(-1), 'vencido');
      expect(expiryBucket(0), 'semana');
      expect(expiryBucket(7), 'semana');
      expect(expiryBucket(8), 'mes');
      expect(expiryBucket(31), 'ok');
    });

    test('rebaja sugerida sin bajar del costo (mismos casos que erp-lots.test.ts)', () {
      expect(suggestedPrice(10, 5, 2), 7);
      expect(suggestedPrice(10, 5, 6), 8.5);
      expect(suggestedPrice(10, 9.5, 2), 9.7);
      expect(suggestedPrice(10, 5, 15), isNull);
      expect(suggestedPrice(10, 5, -1), isNull);
      expect(suggestedPrice(10, 10, 2), isNull);
    });

    test('lee lot_status y ordena lo más urgente primero', () {
      final a = LotStatus.fromJson({'lot_id': 'a', 'product_id': 'p', 'product_name': 'Yogurt', 'unit': 'NIU', 'lot_code': null,
        'expires_on': '2026-11-30', 'quantity': 10, 'remaining': 4, 'days_left': 9, 'unit_cost': 2, 'unit_price': 3});
      final b = LotStatus.fromJson({'lot_id': 'b', 'product_id': 'p', 'product_name': 'Leche', 'unit': 'NIU',
        'expires_on': '2026-11-20', 'quantity': 5, 'remaining': 2, 'days_left': -3});
      final c = LotStatus.fromJson({'lot_id': 'c', 'product_id': 'p', 'product_name': 'Pan', 'unit': 'NIU',
        'expires_on': '2026-11-21', 'quantity': 5, 'remaining': 0, 'days_left': -2});
      expect(activeLots([a, b, c]).map((l) => l.lotId), ['b', 'a']);
      expect(b.unitCost, isNull);
    });
  });

  group('mermas', () {
    test('valida cantidad, stock y motivo', () {
      expect(lossProblem(2, 'vencido', '', null), contains('no controla stock'));
      expect(lossProblem(0, 'vencido', '', 5), contains('mayor que cero'));
      expect(lossProblem(1.234, 'vencido', '', 5), contains('2 decimales'));
      expect(lossProblem(6, 'vencido', '', 5), contains('superar el stock'));
      expect(lossProblem(1, 'perdido', '', 5), contains('motivo'));
      expect(lossProblem(1, 'otro', '  ', 5), contains('Escribe el motivo'));
      expect(lossProblem(1.5, 'robo', '', 5), isNull);
    });
  });

  group('compra con vencimiento', () {
    test('la fecha se guarda en el teléfono pero no cambia lo que se envía a retail_receive', () {
      const line = RetailPurchaseLine(productId: 'p1', quantity: 2, unitCostCents: 350, expiresOn: '2026-12-01');
      expect(line.toJson().containsKey('expires_on'), isFalse);
      expect(line.toStoreJson()['expires_on'], '2026-12-01');
      expect(RetailPurchaseLine.fromJson(line.toStoreJson()).expiresOn, '2026-12-01');
      expect(RetailPurchaseLine.fromJson({...line.toJson(), 'expires_on': '2026-02-30'}).expiresOn, isNull);
    });

    test('una compra pendiente guardada antes (sin fechas) se sigue leyendo', () {
      final p = PendingRetailPurchase.fromJson({
        'v': 1, 'org_id': 'o', 'user_id': 'u', 'request_id': 'r', 'supplier': 'Gloria', 'reference': '', 'payment_method': 'pendiente',
        'items': [{'product_id': 'p1', 'quantity': 3, 'unit_cost_cents': 200}],
      });
      expect(p.lines.single.expiresOn, isNull);
      expect(p.totalCents, 600);
    });
  });
}
