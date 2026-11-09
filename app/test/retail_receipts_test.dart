import 'package:flutter_test/flutter_test.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/screens/retail_receipts.dart';

InvoiceRecord record({
  String? fiscalNumber,
  String? fiscalStatus,
  String? docKind,
  String status = 'sent',
  String client = 'Cliente de ensayo',
  bool voided = false,
}) => InvoiceRecord(
  id: 'receipt-1',
  number: 'V-000001',
  issueDate: '2026-11-08',
  status: status,
  currency: 'PEN',
  taxRate: 18,
  notes: '',
  clientName: client,
  clientTaxId: '12345678',
  clientDocType: '1',
  items: const [],
  fiscalNumber: fiscalNumber,
  fiscalStatus: fiscalStatus,
  docKind: docKind,
  voided: voided,
);

void main() {
  group('Plan Básico: facturación y comprobantes', () {
    test('documento interno no se presenta como boleta SUNAT', () {
      final internal = record(status: 'paid');
      expect(retailReceiptKind(internal), 'internal');
      expect(retailReceiptMatches(internal, 'unissued', ''), true);
      expect(retailReceiptMatches(internal, 'boleta', ''), false);
      expect(retailReceiptMatches(internal, 'factura', ''), false);
    });

    test('serie SUNAT identifica correctamente boleta y factura', () {
      final boleta = record(
        fiscalNumber: 'B001-00000010', fiscalStatus: 'accepted');
      final factura = record(
        fiscalNumber: 'F001-00000009', fiscalStatus: 'accepted');
      expect(retailReceiptKind(boleta), 'boleta');
      expect(retailReceiptKind(factura), 'factura');
      expect(retailReceiptMatches(boleta, 'boleta', '00000010'), true);
      expect(retailReceiptMatches(factura, 'factura', 'Cliente'), true);
      expect(retailReceiptMatches(factura, 'boleta', ''), false);
    });

    test('filtra pendientes y rechazos sin tratarlos como aceptados', () {
      for (final status in ['pending', 'rejected', 'error']) {
        final inv = record(fiscalStatus: status);
        expect(retailReceiptMatches(inv, 'review', ''), true);
        expect(retailReceiptMatches(inv, 'unissued', ''), false);
      }
      expect(retailReceiptMatches(
        record(fiscalStatus: 'accepted'), 'review', ''), false);
    });

    test('busca por cliente, identificador interno y DNI', () {
      final inv = record(client: 'María Elena');
      expect(retailReceiptMatches(inv, 'all', 'maría'), true);
      expect(retailReceiptMatches(inv, 'all', 'V-000001'), true);
      expect(retailReceiptMatches(inv, 'all', '12345678'), true);
      expect(retailReceiptMatches(inv, 'all', 'cliente desconocido'), false);
    });

    test('notas de crédito se distinguen de boletas y facturas', () {
      final note = record(docKind: 'nota_credito', fiscalNumber: 'FC01-0003');
      expect(retailReceiptKind(note), 'credit');
      expect(retailReceiptMatches(note, 'factura', ''), false);
    });
  });
}
