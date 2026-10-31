import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/logic/obra.dart';

void main() {
  test('sin contrato no hay señal', () {
    expect(obraSignal(agreed: 0, invoiced: 0, spent: 500).alert, ObraAlert.none);
  });

  test('gasto acorde a lo facturado: sin alerta', () {
    expect(obraSignal(agreed: 10000, invoiced: 5000, spent: 4000).alert, ObraAlert.none);
  });

  test('gasta más rápido de lo que factura', () {
    final s = obraSignal(agreed: 10000, invoiced: 2000, spent: 5000);
    expect(s.alert, ObraAlert.faster);
    expect(s.spentShare, 0.5);
    expect(s.invoicedShare, 0.2);
  });

  test('gastó todo el contrato', () {
    expect(obraSignal(agreed: 10000, invoiced: 8000, spent: 10000).alert, ObraAlert.over);
    expect(obraSignal(agreed: 10000, invoiced: 8000, spent: 12000).alert, ObraAlert.over);
  });
}
