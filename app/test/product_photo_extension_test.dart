import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/products.dart';

void main() {
  test('photo restore preserves real PNG and WebP types', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
    final webp = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
    final jpg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0]);
    expect(productPhotoExtension(png), 'png');
    expect(productPhotoExtension(webp), 'webp');
    expect(productPhotoExtension(jpg), 'jpg');
  });
}
