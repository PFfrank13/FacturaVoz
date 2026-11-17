// Vincula líneas dictadas/escritas con el catálogo SOLO cuando la descripción es exactamente el nombre de un
// producto activo (sin distinguir mayúsculas ni espacios). En la base el nombre es único por empresa
// (uq_products_org_name), así que no hay ambigüedad. La vinculación es visible en la línea antes de emitir y se
// pierde si el usuario cambia la descripción (new_invoice.dart). Desde v3.4 la base solo mueve stock con
// product_id explícito: nunca adivina por descripción.
import '../models.dart';

String _key(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

List<LineItem> linkToCatalog(List<LineItem> items, List<Product> catalog) {
  final byName = <String, Product>{};
  final dup = <String>{};
  for (final p in catalog.where((p) => p.active)) {
    final k = _key(p.name);
    if (k.isEmpty) continue;
    if (byName.containsKey(k)) dup.add(k);
    byName[k] = p;
  }
  return [
    for (final i in items)
      if (i.productId != null)
        i
      else if (byName[_key(i.description)] case final p? when !dup.contains(_key(i.description)))
        LineItem(description: i.description, quantity: i.quantity, unitPrice: i.unitPrice == 0 ? p.unitPrice : i.unitPrice, productId: p.id)
      else
        i,
  ];
}
