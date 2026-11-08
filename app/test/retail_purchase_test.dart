import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/services/retail_purchase.dart';

void main() {
  PendingRetailPurchase sample() => PendingRetailPurchase(
        orgId: 'org-A',
        userId: 'user-A',
        requestId: '00000000-0000-4000-8000-000000000066',
        supplier: 'Distribuidora Centro',
        reference: 'F001-345',
        paymentMethod: 'efectivo',
        lines: const [
          RetailPurchaseLine(
            productId: '00000000-0000-4000-8000-000000000011',
            quantity: 3,
            unitCostCents: 275,
          ),
        ],
      );

  test('purchase idempotency and supplier details roundtrip exactly', () {
    final a = sample();
    final b = PendingRetailPurchase.fromJson(a.toJson());
    expect(b.requestId, a.requestId);
    expect(b.userId, 'user-A');
    expect(b.orgId, 'org-A');
    expect(b.supplier, 'Distribuidora Centro');
    expect(b.reference, 'F001-345');
    expect(b.paymentMethod, 'efectivo');
    expect(b.lines.single.productId, a.lines.single.productId);
    expect(b.totalCents, 825);
  });

  test('stock increase price uses cents, not the catalog sales price', () {
    const item = RetailPurchaseLine(productId: 'sku-A', quantity: 1.25, unitCostCents: 199);
    expect(item.lineTotalCents, 249);
    expect(item.toJson()['quantity'], 1.25);
    expect(item.toJson()['unit_cost_cents'], 199);
  });

  test('reused request cannot carry duplicate SKU or invalid quantity', () {
    final a = sample().toJson();
    (a['items'] as List).add((a['items'] as List).first);
    expect(() => PendingRetailPurchase.fromJson(a), throwsFormatException);

    final b = sample().toJson();
    (b['items'] as List).first['quantity'] = -1;
    expect(() => PendingRetailPurchase.fromJson(b), throwsFormatException);
  });

  test('bad source identity and unsupported payment method fail closed', () {
    final a = sample().toJson();
    expect(() => PendingRetailPurchase.fromJson({...a, 'org_id': ''}), throwsFormatException);
    expect(() => PendingRetailPurchase.fromJson({...a, 'payment_method': 'otro'}), throwsFormatException);
    expect(() => PendingRetailPurchase.fromJson({...a, 'items': <Object>[]}), throwsFormatException);
  });
}
