import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/services/pos_cart_draft.dart';

void main() {
  PosCartDraft build() => const PosCartDraft(
        orgId: 'org-A', userId: 'cashier-A',
        quantities: {'product-1': 2, 'product-2': 1.25},
        notes: {'product-1': 'Sin bolsa'},
        table: 'Mesa 2',
        couponCode: 'PRUEBA',
        couponKind: 'porcentaje',
        couponValue: 5,
      );

  test('cart restores quantities, notes, table and coupon, scoped to its owner', () {
    final a = build();
    final b = PosCartDraft.fromJson(a.toJson());
    expect(b.orgId, a.orgId);
    expect(b.userId, a.userId);
    expect(b.quantities, a.quantities);
    expect(b.notes, a.notes);
    expect(b.table, 'Mesa 2');
    expect(b.couponCode, 'PRUEBA');
    expect(b.couponValue, 5);
  });

  test('corrupt local storage blocks cart recovery instead of rewriting it', () {
    final a = build().toJson();
    expect(() => PosCartDraft.fromJson({...a, 'v': 7}), throwsFormatException);
    expect(() => PosCartDraft.fromJson({...a, 'user_id': null}), throwsFormatException);
    expect(() => PosCartDraft.fromJson({...a, 'quantities': {'product-1': -1}}), throwsFormatException);
    expect(() => PosCartDraft.fromJson({...a, 'quantities': {'product-1': 1.234}}), throwsFormatException);
    expect(() => PosCartDraft.fromJson({...a, 'notes': {'not-in-cart': 'x'}}), throwsFormatException);
    expect(() => PosCartDraft.fromJson({...a, 'coupon_value': -100}), throwsFormatException);
  });

  test('cart draft is editable; payment request is separate', () {
    final json = build().toJson();
    expect(json.containsKey('method'), false);
    expect(json.containsKey('request_id'), false);
    expect(json.containsKey('invoice_id'), false);
  });
}
