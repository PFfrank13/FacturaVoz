import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/data_scope.dart';

void main() {
  group('Fase 4: ninguna escritura financiera cruza una sesión', () {
    test('autoriza solo empresa y usuario originales con versión vigente', () {
      final scope = ScopeTicket(7, 'org-A', 'cashier-A');
      expect(scope.permitsMutation(7, 'org-A', 'cashier-A'), isTrue);
      expect(scope.permitsMutation(7, 'org-B', 'cashier-A'), isFalse);
      expect(scope.permitsMutation(7, 'org-A', 'cashier-B'), isFalse);
      expect(scope.permitsMutation(8, 'org-A', 'cashier-A'), isFalse);
    });

    test('cambiar a B y volver a A invalida la operación anterior', () {
      final beforeDialog = ScopeTicket(11, 'org-A', 'cashier-A');
      expect(beforeDialog.permitsMutation(13, 'org-A', 'cashier-A'), isFalse);
    });

    test('no autoriza ninguna mutación sin cuenta o empresa autenticada', () {
      for (final scope in [
        ScopeTicket(0, null, 'cashier-A'),
        ScopeTicket(0, 'org-A', null),
        ScopeTicket(0, null, null),
      ]) {
        expect(scope.permitsMutation(0, scope.org, scope.user), isFalse);
      }
    });

    test('nulos sobrevenidos o cierre de sesión bloquean confirmación', () {
      final scope = ScopeTicket(0, 'org-A', 'cashier-A');
      expect(scope.permitsMutation(0, null, 'cashier-A'), isFalse);
      expect(scope.permitsMutation(0, 'org-A', null), isFalse);
      expect(scope.permitsMutation(1, null, null), isFalse);
    });
  });
}
