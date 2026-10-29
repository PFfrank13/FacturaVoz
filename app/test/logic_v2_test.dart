// Pruebas de la lógica pura de la v2.0 (sin red ni base de datos): flutter test test/logic_v2_test.dart
import 'dart:typed_data';

import 'package:facturavoz/access.dart';
import 'package:facturavoz/business_templates.dart';
import 'package:facturavoz/logic/bank_match.dart';
import 'package:facturavoz/logic/doc_voice.dart';
import 'package:facturavoz/logic/escpos.dart';
import 'package:facturavoz/logic/notice_parser.dart';
import 'package:facturavoz/logic/pay_score.dart';
import 'package:facturavoz/logic/pricing.dart';
import 'package:facturavoz/logic/scan_checks.dart';
import 'package:facturavoz/logic/search_score.dart';
import 'package:facturavoz/logic/taxes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DNI/RUC en el dictado', () {
    test('dígito verificador del RUC', () {
      expect(rucValid('20100070970'), isTrue);
      expect(rucValid('10467793549'), isTrue);
      expect(rucValid('20100070971'), isFalse);
      expect(rucValid('30100070970'), isFalse);
    });
    test('tipo de documento', () {
      expect(docKind('12345678'), 'dni');
      expect(docKind('20131312955'), 'ruc');
      expect(docKind('20131312950'), isNull);
      expect(docKind('123'), isNull);
    });
    test('RUC dicho con espacios o en palabras', () {
      expect(extractDoc('Factura para el RUC 20 100 070 970, 3 sillas a 150')?.number, '20100070970');
      expect(extractDoc('boleta DNI 4 5 6 7 8 9 1 2 dos kilos de arroz')?.number, '45678912');
      expect(extractDoc('ruc dos cero uno cero cero cero siete cero nueve siete cero')?.kind, 'ruc');
      expect(extractDoc('tres sillas a ciento cincuenta'), isNull);
    });
    test('el resto del dictado queda sin el documento', () {
      final d = extractDoc('Factura RUC 20100070970 tres sillas a 150')!;
      expect(d.rest.contains('20100070970'), isFalse);
      expect(d.rest.contains('sillas'), isTrue);
    });
  });

  group('Impuestos (referencial)', () {
    test('RER: IGV ventas − compras y 1.5 % de renta', () {
      final e = estimateTaxes(regime: 'rer', monthSalesBase: 1000, monthSalesTax: 180, monthPurchasesTax: 50, yearSalesBase: 1000);
      expect(e.igv, 130);
      expect(e.renta, 15);
      expect(e.total, 145);
    });
    test('Nuevo RUS: cuota fija', () {
      final e = estimateTaxes(regime: 'nrus', monthSalesBase: 4000, monthSalesTax: 0, monthPurchasesTax: 0, yearSalesBase: 4000);
      expect(e.renta, 20);
      expect(e.igv, 0);
    });
    test('saldo a favor de IGV no se vuelve negativo', () {
      final e = estimateTaxes(regime: 'rmt', monthSalesBase: 100, monthSalesTax: 18, monthPurchasesTax: 50, yearSalesBase: 100);
      expect(e.igv, 0);
      expect(e.notes.any((n) => n.contains('saldo a favor')), isTrue);
    });
  });

  group('Precios y promociones', () {
    test('precio por mayor desde N unidades', () {
      final p = bestPrice(productId: 'a', listPrice: 10, qty: 12, wholesalePrice: 8, wholesaleMinQty: 12, today: '2026-10-28');
      expect(p.unitPrice, 8);
      expect(p.reason, 'Precio por mayor');
    });
    test('elige la mejor promoción vigente', () {
      const promo = Promo(id: 'x', name: '30 % gaseosas', kind: 'porcentaje', value: 30);
      final p = bestPrice(productId: 'a', listPrice: 10, qty: 1, promos: const [promo], today: '2026-10-28');
      expect(p.unitPrice, 7);
    });
    test('promoción vencida no aplica', () {
      const promo = Promo(id: 'x', name: 'Vieja', kind: 'porcentaje', value: 50, endsOn: '2026-01-01');
      expect(bestPrice(productId: 'a', listPrice: 10, qty: 1, promos: const [promo], today: '2026-10-28').unitPrice, 10);
    });
    test('el cupón nunca deja el total negativo', () {
      expect(couponDiscount(kind: 'monto', value: 50, subtotal: 30), 30);
      expect(couponDiscount(kind: 'porcentaje', value: 10, subtotal: 200), 20);
    });
  });

  group('Avisos de Yape/Plin', () {
    test('lee monto, app y pagador', () {
      final n = parsePaymentNotice('¡Yape! JUAN PEREZ te envió un pago por S/ 25.50. El cód. de seguridad es: 123')!;
      expect(n.app, 'yape');
      expect(n.amount, 25.5);
      expect(n.payer.toUpperCase().contains('JUAN'), isTrue);
    });
    test('sin monto no hay aviso', () {
      expect(parsePaymentNotice('Hola, ¿cómo estás?'), isNull);
    });
  });

  group('Conciliación bancaria', () {
    test('lee el extracto y sugiere la factura por monto y nombre', () {
      final lines = parseBankTable([
        ['Fecha', 'Descripción', 'Monto', 'Operación'],
        ['15/10/2026', 'TRANSF DE ROSA QUISPE', '1,250.00', '998877'],
        ['16/10/2026', 'COMISION MANTENIMIENTO', '-10.00', '1'],
      ]);
      expect(lines.length, 2);
      expect(lines.first.date, '2026-10-15');
      expect(lines.first.amount, 1250);
      final s = suggestMatches(lines, const [
        Receivable(invoiceId: 'i1', number: 'F001-00000023', client: 'Rosa Quispe SAC', balance: 1250, issueDate: '2026-10-01'),
        Receivable(invoiceId: 'i2', number: 'F001-00000024', client: 'Otro Cliente', balance: 99, issueDate: '2026-10-01'),
      ]);
      expect(s.length, 1);
      expect(s.first.invoice.invoiceId, 'i1');
      expect(s.first.score, greaterThanOrEqualTo(0.8));
    });
    test('la huella evita importar dos veces la misma línea', () {
      final a = BankLine(date: '2026-10-15', description: 'X', amount: 10, reference: '1');
      final b = BankLine(date: '2026-10-15', description: 'x ', amount: 10.0, reference: '1');
      expect(a.fingerprint, b.fingerprint);
    });
  });

  group('Escáner: avisos antes de guardar el gasto', () {
    test('fecha antigua y factura a nombre de otro RUC', () {
      final w = scanWarnings(
        issueDate: '2025-01-01',
        supplierTaxId: '20100070970',
        clientTaxId: '20131312955',
        docType: 'factura',
        confidence: 0.9,
        looksHandwritten: false,
        myRuc: '20601030013',
        today: '2026-10-28',
      );
      expect(w.where((x) => x.serious).length, 2);
    });
    test('manuscritos bajan la confianza mostrada', () {
      expect(shownConfidence(0.95, handwritten: true), 0.6);
      expect(shownConfidence(0.95, handwritten: false), 0.95);
      expect(looksHandwritten(supplierTaxId: '', docNumber: '001-123', docType: 'boleta'), isTrue);
      expect(looksHandwritten(supplierTaxId: '20100070970', docNumber: 'F001-123', docType: 'factura'), isFalse);
    });
  });

  group('Ticket ESC/POS', () {
    test('columnas y saltos de línea', () {
      expect(twoCols('Total', 'S/ 10.00', 20).length, 20);
      expect(wrapLines('hola mundo grande', 10), ['hola mundo', 'grande']);
    });
    test('tildes y ñ en la página 1252', () {
      expect(encode1252('ñ'), Uint8List.fromList([0xF1]));
      expect(encode1252('€'), Uint8List.fromList([0x80]));
    });
    test('QR nativo con corrección Q y corte de papel', () {
      final e = EscPos(Paper.mm80)
        ..init()
        ..qr('20100070970|01|F001|00000023|18.00|118.00|2026-10-28|6|20131312955|')
        ..cut();
      final b = e.bytes();
      // GS ( k … 0x31 0x45 0x33 = nivel de corrección Q
      expect(String.fromCharCodes(b).contains(String.fromCharCodes([0x1D, 0x28, 0x6B, 3, 0, 0x31, 0x45, 0x33])), isTrue);
      expect(b.sublist(b.length - 4), [0x1D, 0x56, 66, 3]);
    });
    test('matriz → imagen de ancho múltiplo de 8', () {
      final r = matrixToRaster([
        [true, false],
        [false, true],
      ], scale: 3, quiet: 1);
      expect(r.width % 8, 0);
      expect(r.data.isNotEmpty, isTrue);
    });
    test('logo a monocromo: negro sale negro, blanco sale blanco', () {
      final rgba = Uint8List.fromList([0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255]);
      final r = rasterize(rgba, 8, 1, 8);
      expect(r.width, 8);
      expect(r.data.first, 0xAA);
    });
  });

  group('Buscador universal', () {
    test('sin tildes, sin mayúsculas, en cualquier orden', () {
      expect(matchScore('rosa', 'Rosa Pérez'), greaterThan(0));
      expect(matchScore('perez rosa', 'Rosa Pérez'), greaterThan(0));
      expect(matchScore('xyz', 'Rosa Pérez'), 0);
      expect(matchScore('20100070970', 'Supermercado', extra: ['RUC 20100070970']), greaterThan(0));
    });
    test('el título exacto gana', () {
      expect(matchScore('fiados', 'Fiados'), greaterThan(matchScore('fiados', 'Libreta de fiados')));
    });
  });

  group('Puntaje de pago y coordenadas', () {
    test('sin historial no inventa un puntaje', () {
      expect(payScore(creditInvoices: 0, settled: 0).value, isNull);
    });
    test('puntual = 100; muy atrasado y con deuda vencida = bajo', () {
      expect(payScore(creditInvoices: 5, settled: 5, avgDaysLate: 0).value, 100);
      final bad = payScore(creditInvoices: 5, settled: 3, avgDaysLate: 20, overdueBalance: 100);
      expect(bad.value, 35);
      expect(bad.tone, 'bad');
    });
    test('enlaces de Google Maps y texto con coordenadas', () {
      expect(parseCoordinates('https://www.google.com/maps/place/X/@-12.0464,-77.0428,17z')?.lat, -12.0464);
      expect(parseCoordinates('https://maps.google.com/?q=-12.1,-77.2')?.lng, -77.2);
      expect(parseCoordinates('-12.04, -77.03')?.lat, -12.04);
      expect(parseCoordinates('hola'), isNull);
    });
  });

  group('Licencia y plantillas', () {
    test('el plan oculta lo no contratado; lo básico siempre está', () {
      const l = LicenseInfo(enforced: true, dev: false, source: 'hub', features: {'tienda': false, 'trabajos': true, 'max_users': 3});
      expect(planHas(l, 'tienda'), isFalse);
      expect(planHas(l, 'trabajos'), isTrue);
      expect(planHas(l, 'facturar'), isTrue);
      expect(planLimit(l, 'max_users'), 3);
    });
    test('modo desarrollo (Hub sin configurar): todo habilitado', () {
      const l = LicenseInfo();
      expect(planHas(l, 'tienda'), isTrue);
      expect(planLimit(l, 'max_users'), -1);
    });
    test('servicio técnico WiFi: flujo completo y pasos terminados', () {
      final t = templateFor('servicios_tecnicos');
      expect(t.statuses.map((s) => s.key), containsAll(['nuevo', 'visita', 'cotizado', 'pendiente', 'en_camino', 'instalado', 'cobrado']));
      for (final b in businessTemplates) {
        expect(b.statuses.any((s) => s.done), isTrue, reason: b.id);
      }
      expect(templateFor('no-existe').id, 'otro');
      expect(businessTemplates.length, greaterThanOrEqualTo(9));
    });
  });
}
