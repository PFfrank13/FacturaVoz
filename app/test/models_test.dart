import 'package:facturavoz/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('totales con redondeo a céntimos (igual que el servidor)', () {
    final t = computeTotals([LineItem(description: 'Servicio', quantity: 2, unitPrice: 100.5)], 18);
    expect(t.subtotal, 201.00);
    expect(t.tax, 36.18);
    expect(t.total, 237.18);
  });

  test('el impuesto es la suma del impuesto de cada línea (como SUNAT)', () {
    final t = computeTotals([
      LineItem(description: 'a', quantity: 1, unitPrice: 0.55),
      LineItem(description: 'b', quantity: 1, unitPrice: 0.55),
    ], 18);
    expect(t.tax, 0.2); // 0.10 + 0.10, no round(1.10*0.18)=0.20 por casualidad
    expect(t.total, 1.3);
  });

  test('sin errores de coma flotante', () {
    final t = computeTotals([LineItem(description: 'x', quantity: 3, unitPrice: 0.1)], 0);
    expect(t.subtotal, 0.3);
    expect(t.total, 0.3);
  });

  test('varias líneas', () {
    final t = computeTotals([
      LineItem(description: 'a', quantity: 1, unitPrice: 19.99),
      LineItem(description: 'b', quantity: 2.5, unitPrice: 4.2),
    ], 18);
    expect(t.subtotal, 30.49);
    expect(t.tax, 5.49); // 3.60 + 1.89 (impuesto por línea)
    expect(t.total, 35.98);
  });

  test('parseDecimal acepta coma y rechaza basura', () {
    expect(parseDecimal('12,5'), 12.5);
    expect(parseDecimal(' 7.25 '), 7.25);
    expect(parseDecimal('abc'), isNull);
    expect(parseDecimal(''), isNull);
  });

  test('formato de moneda', () {
    expect(money(1234.5, 'PEN'), 'S/ 1,234.50');
    expect(money(1234.5, 'USD'), 'US\$ 1,234.50');
    expect(money(1234.5, 'EUR'), '1.234,50 €');
  });

  test('fecha legible', () {
    expect(displayDate('2026-10-23'), '23/10/2026');
  });

  test('perfil completo solo con todos los ajustes', () {
    expect(Profile().isComplete, isFalse);
    expect(
      Profile(businessName: 'Acme', currency: 'PEN', taxLabel: 'IGV', taxRate: 18).isComplete,
      isTrue,
    );
    expect(Profile(businessName: 'Acme', currency: 'PEN', taxLabel: 'IGV').isComplete, isFalse);
  });

  test('respuesta de /api/parse sin impuesto usa el del perfil', () {
    final profile = Profile(businessName: 'Acme', currency: 'PEN', taxLabel: 'IGV', taxRate: 18);
    final d = InvoiceDraft.fromParse({
      'client_name': 'Ferretería Díaz',
      'tax_rate': null,
      'notes': null,
      'transcript': 'dictado',
      'items': [
        {'description': 'Instalación', 'quantity': 1, 'unit_price': 450}
      ],
    }, profile);
    expect(d.taxRate, 18);
    expect(d.currency, 'PEN');
    expect(d.items.single.unitPrice, 450.0);
  });

  test('InvoiceRecord desde JSON de Supabase', () {
    final r = InvoiceRecord.fromJson({
      'id': 'x',
      'number': 'F-2026-0001',
      'issue_date': '2026-10-23',
      'status': 'draft',
      'currency': 'PEN',
      'tax_rate': '18.00',
      'notes': null,
      'clients': {'name': 'Acme', 'tax_id': null, 'doc_type': '6'},
      'fiscal_documents': {'status': 'accepted', 'series': 'F001', 'correlative': 7, 'doc_type': '01'},
      'invoice_items': [
        {'description': 'Servicio', 'quantity': 2, 'unit_price': 100.5, 'position': 1}
      ],
    });
    expect(r.taxRate, 18.0);
    expect(r.clientName, 'Acme');
    expect(r.fiscalNumber, 'F001-00000007');
    expect(r.fiscalStatus, 'accepted');
    expect(r.totals.total, 237.18);
  });

  test('número fiscal con 8 dígitos', () {
    expect(fiscalNumberOf('F001', 7), 'F001-00000007');
    expect(fiscalNumberOf('B001', 12345678), 'B001-12345678');
  });

  test('FiscalDoc desde JSON', () {
    final d = FiscalDoc.fromJson({
      'doc_type': '01',
      'series': 'F001',
      'correlative': 7,
      'env': 'beta',
      'status': 'accepted',
      'legend': 'SON UNO CON 00/100 SOLES',
      'sunat_code': '0',
      'sunat_message': null,
      'hash': 'H',
      'payload': {'tipoDoc': '01'},
      'totals': {'total': 1.0},
    });
    expect(d.number, 'F001-00000007');
    expect(d.typeName, 'FACTURA ELECTRÓNICA');
    expect(d.sunatMessage, '');
  });

  test('domicilio fiscal completo para emitir', () {
    final p = Profile(
      businessName: 'Acme', taxId: '20000000001', address: 'Av. 1', ubigeo: '150101',
      department: 'LIMA', province: 'LIMA', district: 'LIMA',
    );
    expect(p.isFiscalReady, isTrue);
    p.ubigeo = '15';
    expect(p.isFiscalReady, isFalse);
  });

  test('nota de crédito desde JSON', () {
    final n = fiscalNoteFromJson({
      'series': 'FC01',
      'correlative': 3,
      'env': 'beta',
      'status': 'accepted',
      'sunat_code': '0',
      'sunat_message': null,
      'hash': null,
      'payload': {'tipoDoc': '07', 'numDocfectado': 'F001-7'},
      'totals': {'total': 1.0},
    }, 'SON UNO CON 00/100 SOLES');
    expect(n.number, 'FC01-00000003');
    expect(n.isCreditNote, isTrue);
    expect(n.typeName, 'NOTA DE CRÉDITO ELECTRÓNICA');
    expect(n.legend, 'SON UNO CON 00/100 SOLES');
  });

  test('assessRisk: monto alto, sin documento y descripción genérica', () {
    final ok = assessRisk(
      clientName: 'Ferretería Díaz',
      clientTaxId: '20123456789',
      items: [LineItem(description: 'Instalación eléctrica', quantity: 1, unitPrice: 450)],
      taxRate: 18,
    );
    expect(ok.level, RiskLevel.low);
    final high = assessRisk(
      clientName: 'Ana',
      clientTaxId: '',
      items: [LineItem(description: 'Servicio', quantity: 1, unitPrice: 6000)],
      taxRate: 18,
    );
    expect(high.level, RiskLevel.high);
    expect(high.reasons.length, greaterThanOrEqualTo(3));
  });
}
