import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('rechazo de stock transaccional permite corregir el carrito', () {
    final denied = PostgrestException(
      message: 'Stock insuficiente para Agua. Registra una compra o corrige existencias antes de vender.',
      code: '22023',
    );
    expect(isConfirmedStockRejection(denied), isTrue);
    expect(friendly(denied), contains('Revisa existencias'));
  });

  test('un error de conexión o validación distinta NO permite desechar el reintento', () {
    expect(isConfirmedStockRejection(Exception('SocketTimeout')), isFalse);
    expect(isConfirmedStockRejection(
      PostgrestException(message: 'Cantidad no válida', code: '22023'),
    ), isFalse);
    expect(isConfirmedStockRejection(
      PostgrestException(message: 'Stock insuficiente para Agua', code: '42501'),
    ), isFalse);
  });
}
