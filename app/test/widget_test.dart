// Reemplaza la prueba de ejemplo de `flutter create` (usaba "MyApp", que no existe en FacturaVoz).
// Prueba de humo: la app principal se puede construir como widget (sin conectarse a Supabase).
import 'package:facturavoz/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FacturaVozApp existe y es un widget constante', () {
    const app = FacturaVozApp();
    expect(app, isNotNull);
  });
}
