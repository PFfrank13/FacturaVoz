// Bodega: productos con stock que no se vendieron en el período (plata parada en el estante).
// No inventa costos: solo cuenta lo que hay y que no salió. Un producto recién agregado también puede aparecer.
import '../models_pro.dart';

/// Con stock > 0 y cero unidades vendidas en el período; los de más stock primero.
List<ProductVelocity> stagnantProducts(List<ProductVelocity> all, {int limit = 15}) {
  final r = all.where((v) => (v.stock ?? 0) > 0 && v.units <= 0).toList()..sort((a, b) => (b.stock ?? 0).compareTo(a.stock ?? 0));
  return r.length > limit ? r.sublist(0, limit) : r;
}
