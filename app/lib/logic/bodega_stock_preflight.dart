/// Pre-cashier warning for tracked Bodega/Tienda inventory.
///
/// This is an early UX check only. It is never a substitute for the atomic
/// PostgreSQL stock guard: another till may sell the same unit seconds later.
String? firstInsufficientBodegaSku(
  Map<String, double> quantitiesById,
  Map<String, double?> stockById,
) {
  for (final requested in quantitiesById.entries) {
    if (requested.value <= 0 || !requested.value.isFinite) {
      return requested.key;
    }
    if (!stockById.containsKey(requested.key)) {
      return requested.key; // Missing/inactive product must be checked again.
    }
    final available = stockById[requested.key];
    // NULL stock is explicitly NOT tracked: services may be sold normally.
    if (available != null &&
        (!available.isFinite || available + 0.0000001 < requested.value)) {
      return requested.key;
    }
  }
  return null;
}
