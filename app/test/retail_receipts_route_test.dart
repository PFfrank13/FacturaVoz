import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/screens/catalog.dart';
import 'package:facturavoz/screens/retail_receipts.dart';

void main() {
  testWidgets('El acceso Comprobantes abre el módulo fiscal dedicado', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Prueba'))));
    final ctx = tester.element(find.text('Prueba'));
    final receiptEntry = featureById('comprobantes');
    expect(receiptEntry, isNotNull);
    expect(receiptEntry!.builder(ctx), isA<RetailReceiptsScreen>());
    expect(receiptEntry.feature, 'facturar');
    expect(receiptEntry.subtitle, contains('SUNAT'));
  });
}
