import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/ui/widgets.dart';

void main() {
  test('All nine rubros have an independent photographic category asset name', () {
    final categories = [
      'bodega', 'restaurante', 'servicios_tecnicos', 'taller', 'consultorio',
      'salon', 'educacion', 'construccion', 'mayorista',
    ];
    final photos = categories.map(sectorPhotoFor).toSet();
    expect(photos.length, 9);
  });

  test('Product identifier travels with a POS line, independent of description', () {
    final line = LineItem(
      description: 'Arroz (promoción)', quantity: 2,
      unitPrice: 5.0, productId: '00000000-0000-4000-8000-000000000012',
    );
    final json = line.toJson();
    expect(json['product_id'], line.productId);
    expect(LineItem.fromJson(json).productId, line.productId);
    expect(LineItem.fromJson(json).description, 'Arroz (promoción)');
  });

  test('Pure service lines without SKU keep backward-compatible JSON', () {
    final json = LineItem(description: 'Consulta', quantity: 1, unitPrice: 30).toJson();
    expect(json.containsKey('product_id'), false);
  });
}
