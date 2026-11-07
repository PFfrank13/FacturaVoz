import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_state.dart';
import 'repo.dart';

class ReceivingRepo {
  static Future<Map<String, dynamic>> load() async {
    final org = Repo.activeOrgId;
    if (org == null) throw StateError('Selecciona una empresa.');
    final db = Supabase.instance.client;
    final results = await Future.wait([
      db
          .from('products')
          .select('id,name,stock,unit_cost,unit_price')
          .eq('org_id', org)
          .eq('active', true)
          .order('name')
          .limit(500),
      db
          .from('retail_receipts')
          .select('id,supplier_name,reference,total,currency,created_at')
          .eq('org_id', org)
          .order('created_at', ascending: false)
          .limit(50),
    ]);
    return {'products': results[0], 'receipts': results[1]};
  }

  static Future<String> receive(Map<String, dynamic> input) async {
    final org = Repo.activeOrgId;
    if (org == null) throw StateError('Selecciona una empresa.');
    final result = await Supabase.instance.client.rpc(
      'retail_receive',
      params: {'p_org': org, ...input},
    );
    if (result is! String || result.isEmpty) {
      throw StateError('No se confirmó la recepción.');
    }
    AppState.instance.bump();
    return result;
  }
}
