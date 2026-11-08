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

  test('supplier settlement roundtrip preserves immutable payment identity', () {
    const original = PendingRetailSettlement(
      orgId: 'org-1',
      userId: 'owner-1',
      requestId: '00000000-0000-4000-8000-000000000001',
      receiptId: '00000000-0000-4000-8000-000000000002',
      method: 'yape',
      evidence: 'Operación revisada por el cajero',
    );
    final decoded = PendingRetailSettlement.fromJson(original.toJson());
    expect(decoded.orgId, original.orgId);
    expect(decoded.userId, original.userId);
    expect(decoded.requestId, original.requestId);
    expect(decoded.receiptId, original.receiptId);
    expect(decoded.method, 'yape');
    expect(decoded.evidence, original.evidence);
  });

  test('supplier settlement rejects unsupported or corrupt payment snapshots', () {
    const p = PendingRetailSettlement(
      orgId: 'org-1', userId: 'owner-1', requestId: 'req',
      receiptId: 'receipt', method: 'efectivo', evidence: '',
    );
    final j = p.toJson();
    expect(() => PendingRetailSettlement.fromJson({...j, 'method': 'pendiente'}), throwsFormatException);
    expect(() => PendingRetailSettlement.fromJson({...j, 'receipt_id': ''}), throwsFormatException);
    expect(() => PendingRetailSettlement.fromJson({...j, 'v': 2}), throwsFormatException);
    expect(() => PendingRetailSettlement.fromJson({...j, 'evidence': 'a' * 201}), throwsFormatException);
  });

  test('bad source identity and unsupported payment method fail closed', () {
    final a = sample().toJson();
    expect(() => PendingRetailPurchase.fromJson({...a, 'org_id': ''}), throwsFormatException);
    expect(() => PendingRetailPurchase.fromJson({...a, 'payment_method': 'otro'}), throwsFormatException);
    expect(() => PendingRetailPurchase.fromJson({...a, 'items': <Object>[]}), throwsFormatException);
  });
}
