import 'package:facturavoz/ux/commerce_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Básico local presenta solo destinos básicos, nunca premium', () {
    for (final id in const ['pos', 'productos', 'inventario', 'fiados',
      'caja', 'compras', 'clientes', 'sunat', 'plan']) {
      expect(commerceEntryVisible(
        id: id, hubPlan: 'EMPRESA', roleOk: true,
        planOk: false, localPreview: true), isTrue, reason: id);
    }
    for (final id in const ['tienda', 'copiloto', 'agente', 'api',
      'carta', 'agenda', 'banco', 'puntos', 'reponer']) {
      expect(commerceEntryVisible(
        id: id, hubPlan: 'EMPRESA', roleOk: true,
        planOk: true, localPreview: true), isFalse, reason: id);
    }
  });
  test('El permiso del trabajador sigue siendo obligatorio', () {
    expect(commerceEntryVisible(id: 'fiados', hubPlan: 'BASICO',
      roleOk: false, planOk: true, localPreview: true), isFalse);
  });
  test('Sin vista local, manda la licencia real', () {
    expect(commerceEntryVisible(id: 'fiados', hubPlan: 'BASICO',
      roleOk: true, planOk: false, localPreview: false), isFalse);
    expect(commerceEntryVisible(id: 'fiados', hubPlan: 'BASICO',
      roleOk: true, planOk: true, localPreview: false), isTrue);
  });
  test('El contenido de la experiencia no define derechos', () {
    expect(commerceMenuVisible('tienda', 'BASICO'), isFalse);
    expect(commerceMenuVisible('fiados', 'BASICO'), isTrue);
    expect(commerceViewPlan('EMPRESA'),
      basicLocalPreview ? 'BASICO' : 'EMPRESA');
  });
}
