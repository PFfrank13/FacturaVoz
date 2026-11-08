import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/services/pending_checkout.dart';

void main() {
  LineItem product() => LineItem(
        description: 'Arroz (promoción)',
        productId: '00000000-0000-4000-8000-000000000012',
        quantity: 2,
        unitPrice: 5.75,
      );

  PendingCheckout sample() => PendingCheckout(
        orgId: 'org-A',
        userId: 'user-A',
        requestId: '00000000-0000-4000-8000-000000000077',
        method: 'yape',
        taxRate: 18,
        currency: 'PEN',
        notes: 'Mesa 3',
        items: [product()],
      );

  test('recovered payment preserves the exact request and original SKU/price', () {
    final restored = PendingCheckout.fromJson(sample().toJson());
    expect(restored.requestId, sample().requestId);
    expect(restored.method, 'yape');
    expect(restored.orgId, 'org-A');
    expect(restored.userId, 'user-A');
    expect(restored.toDraft().items.single.productId, product().productId);
    expect(restored.toDraft().items.single.description, 'Arroz (promoción)');
    expect(restored.toDraft().items.single.quantity, 2);
    expect(restored.toDraft().items.single.unitPrice, 5.75);
    expect(restored.toDraft().notes, 'Mesa 3');
  });

  test('snapshot is independent of subsequent cart edits', () {
    final pending = sample();
    final serialized = pending.toJson();
    pending.items.single.unitPrice = 99;
    final restored = PendingCheckout.fromJson(serialized);
    expect(restored.items.single.unitPrice, 5.75);
  });

  test('a missing SKU fails closed rather than replaying an ambiguous sale', () {
    final json = sample().toJson();
    (json['items'] as List).first.remove('product_id');
    expect(() => PendingCheckout.fromJson(json), throwsFormatException);
  });

  test('empty and unsupported pending snapshots are rejected', () {
    final json = sample().toJson();
    expect(() => PendingCheckout.fromJson({...json, 'v': 2}), throwsFormatException);
    expect(() => PendingCheckout.fromJson({...json, 'items': <Object>[]}), throwsFormatException);
  });

  test('negative item quantities are rejected', () {
    final json = sample().toJson();
    (json['items'] as List).first['quantity'] = -1;
    expect(() => PendingCheckout.fromJson(json), throwsFormatException);
  });
}
