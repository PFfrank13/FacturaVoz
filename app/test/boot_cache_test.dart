import 'package:facturavoz/access.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/services/boot_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Org se guarda y se recupera igual', () {
    const o = Org(id: 'a1', name: 'Ferretería Sol', taxId: '20123456789', role: 'admin');
    final r = Org.fromJson(o.toJson());
    expect([r.id, r.name, r.taxId, r.role], ['a1', 'Ferretería Sol', '20123456789', 'admin']);
  });

  test('Profile se guarda y se recupera completo', () {
    final p = Profile(businessName: 'Sol SAC', taxId: '20123456789', currency: 'PEN', taxLabel: 'IGV', taxRate: 18, ubigeo: '110101', department: 'Ica', province: 'Ica', district: 'Ica', address: 'Av. 1');
    final r = Profile.fromJson(p.toJson());
    expect(r.isComplete, isTrue);
    expect(r.isFiscalReady, isTrue);
    expect(r.taxRate, 18);
  });

  test('Access.applyCached deja permisos y licencia listos sin red', () {
    final a = Access.instance;
    a.applyCached({'role': 'cajero', 'is_admin': false, 'display_name': 'Ana', 'welcomed': true, 'can': {'finance': false}}, {'mode': 'full', 'plan': 'PRO', 'enforced': true, 'source': 'hub'});
    expect(a.loaded, isTrue);
    expect(a.role, 'cajero');
    expect(a.can('finance'), isFalse);
    expect(a.license.plan, 'PRO');
    expect(a.rawAccess!['display_name'], 'Ana');
    a.clear();
    expect(a.rawAccess, isNull);
  });

  test('BootCache entrega lo guardado solo a la misma cuenta', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    BootCache.putCore('u1', orgs: [const Org(id: 'a1', name: 'Sol', taxId: '', role: 'owner').toJson()], active: 'a1', profile: Profile(businessName: 'Sol').toJson());
    expect(BootCache.forUser('u1')?['active'], 'a1');
    BootCache.putSettings('a1', {'business_type': 'bodega'});
    expect(BootCache.forUser('u1')?['settings_org'], 'a1');
    expect(BootCache.forUser('u2'), isNull); // otra cuenta: nada, y se borra
    expect(BootCache.forUser('u1'), isNull);
    await Future<void>.delayed(Duration.zero);
  });
}
