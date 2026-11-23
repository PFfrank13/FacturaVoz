// Códigos de barras por producto (v3.9): el principal (products.barcode) y los adicionales (product_barcodes).
// Un código vende siempre el mismo producto; la base impide que un código sea de dos productos.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';
import 'repo.dart';

class CodeOwner {
  const CodeOwner(this.productId, this.name);
  final String productId;
  final String name;
}

/// ¿Es un código de barras válido para guardar? (4–40 letras, números, guion o punto).
bool isValidCode(String code) => RegExp(r'^[0-9A-Za-z\-\.]{4,40}$').hasMatch(code.trim());

/// Mensaje claro cuando la base rechaza un código repetido.
String codeTakenMessage(String code, String? owner) =>
    owner == null ? 'El código $code ya es de otro producto.' : 'El código $code ya es de «$owner». Un código solo puede ser de un producto.';

class ProductCodes {
  ProductCodes._();
  static SupabaseClient get _db => Supabase.instance.client;
  static String get _org {
    final org = Repo.activeOrgId;
    if (org == null) throw AppException('Selecciona una empresa.');
    return org;
  }

  /// Dueño del código, o null si está libre. [except] = el producto que se está editando.
  static Future<CodeOwner?> owner(String code, {String? except}) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    try {
      final rows = await _db.rpc('product_code_owner', params: {'p_org': _org, 'p_code': c});
      final list = rows as List;
      if (list.isEmpty) return null;
      final r = Map<String, dynamic>.from(list.first as Map);
      if (r['product_id'] == except) return null;
      return CodeOwner(r['product_id'] as String, (r['name'] ?? '') as String);
    } on PostgrestException {
      // Migración v3.9 pendiente: se consulta solo el código principal.
      final r = await _db.from('products').select('id, name').eq('org_id', _org).eq('barcode', c).maybeSingle();
      if (r == null || r['id'] == except) return null;
      return CodeOwner(r['id'] as String, (r['name'] ?? '') as String);
    }
  }

  /// Todos los códigos adicionales de la empresa: código → producto (para vender escaneando, también sin señal).
  static Future<Map<String, String>> extraCodes() async {
    try {
      final rows = await _db.from('product_barcodes').select('code, product_id').eq('org_id', _org).limit(20000);
      return {for (final r in rows as List) (r as Map)['code'] as String: r['product_id'] as String};
    } catch (_) {
      return const {};
    }
  }

  static Future<List<({String id, String code})>> codesOf(String productId) async {
    final rows = await _db.from('product_barcodes').select('id, code').eq('product_id', productId).order('created_at');
    return [for (final r in rows as List) (id: (r as Map)['id'] as String, code: r['code'] as String)];
  }

  /// Agrega un código al producto. Lanza AppException con mensaje claro si ya es de otro.
  static Future<void> add(String productId, String code) async {
    final c = code.trim();
    if (!isValidCode(c)) throw AppException('Código no válido: usa de 4 a 40 letras o números.');
    final taken = await owner(c);
    if (taken != null) {
      if (taken.productId == productId) throw AppException('Ese código ya está en este producto.');
      throw AppException(codeTakenMessage(c, taken.name));
    }
    try {
      await _db.from('product_barcodes').insert({'org_id': _org, 'product_id': productId, 'code': c});
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw AppException(codeTakenMessage(c, null));
      rethrow;
    }
  }

  static Future<void> remove(String id) => _db.from('product_barcodes').delete().eq('id', id);
}
