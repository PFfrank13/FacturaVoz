// Pedido de restaurante creado desde caja. Las notas de cocina son independientes
// de la descripción comercial usada en cotizaciones/facturas.
import 'dart:math';

class KitchenDraftItem {
  const KitchenDraftItem({required this.description, required this.quantity, required this.unitPrice, this.note = ''});
  final String description;
  final double quantity;
  final double unitPrice;
  final String note;

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'note': note.trim(),
      };
}

/// UUID v4 válido para idempotencia: reutilizar el mismo valor en cada reintento.
String newKitchenRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
}
