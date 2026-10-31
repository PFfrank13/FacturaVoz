// Mesas del restaurante: resume los pedidos abiertos de la carta QR por mesa.
// Solo lee los pedidos que ya llegan a Comandas; no inventa nada ni toca la base de datos.
import '../models_v2.dart';

const _order = {'nuevo': 0, 'preparando': 1, 'listo': 2};

class TableSummary {
  const TableSummary({required this.label, required this.orders, required this.items, required this.stage, required this.wait});

  final String label;
  final int orders; // pedidos abiertos de la mesa
  final int items; // platos pedidos (suma de cantidades, redondeada)
  final String stage; // el paso más atrasado: nuevo | preparando | listo
  final Duration wait; // desde el pedido abierto más antiguo
}

/// Agrupa por mesa los pedidos abiertos (nuevo, preparando, listo). Los pedidos sin mesa
/// (para llevar o delivery) no entran. Las que llevan más tiempo esperando van primero.
List<TableSummary> summarizeTables(List<KitchenOrder> orders, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final by = <String, List<KitchenOrder>>{};
  for (final o in orders) {
    final label = o.table.trim();
    if (label.isEmpty || !_order.containsKey(o.status)) continue;
    by.putIfAbsent(label, () => []).add(o);
  }
  final out = <TableSummary>[];
  by.forEach((label, list) {
    var stage = 'listo';
    DateTime? oldest;
    var items = 0.0;
    for (final o in list) {
      if ((_order[o.status] ?? 2) < (_order[stage] ?? 2)) stage = o.status;
      final c = o.createdAt;
      if (c != null && (oldest == null || c.isBefore(oldest))) oldest = c;
      for (final i in o.items) {
        items += i.quantity;
      }
    }
    final w = oldest == null ? Duration.zero : t.difference(oldest);
    out.add(TableSummary(label: label, orders: list.length, items: items.round(), stage: stage, wait: w.isNegative ? Duration.zero : w));
  });
  out.sort((a, b) => b.wait.compareTo(a.wait));
  return out;
}

/// Cuántos pedidos abiertos no son de mesa (para llevar o delivery).
int openWithoutTable(List<KitchenOrder> orders) => orders.where((o) => o.table.trim().isEmpty && _order.containsKey(o.status)).length;

/// "12 min", "1 h 05 min".
String waitText(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'recién llegó';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}
