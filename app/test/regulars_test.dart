import 'package:facturavoz/growth.dart' show fillDailySeries;
import 'package:facturavoz/logic/regulars.dart';
import 'package:facturavoz/models.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceRecord inv(String date, {String status = 'paid', String? kind, bool voided = false, double price = 10}) => InvoiceRecord(
      id: date + status + price.toString(),
      number: 'X',
      issueDate: date,
      status: status,
      currency: 'PEN',
      taxRate: 18,
      notes: '',
      clientName: 'Rosa',
      clientTaxId: '',
      clientDocType: '',
      items: [LineItem(description: 'Arroz', quantity: 1, unitPrice: price)],
      docKind: kind,
      voided: voided,
    );

void main() {
  const today = '2026-10-29';
  test('sin compras', () => expect(classifyRegular(const [], today: today).tier, RegularTier.sinCompras));
  test('nuevo con 1-2 compras', () {
    expect(classifyRegular([inv('2026-10-01'), inv('2026-10-10')], today: today).tier, RegularTier.nuevo);
  });
  test('frecuente con 3 compras en 90 días y casero con 6', () {
    final three = [for (final d in ['2026-10-01', '2026-10-10', '2026-10-20']) inv(d)];
    final r = classifyRegular(three, today: today);
    expect(r.tier, RegularTier.frecuente);
    expect(r.suggestedDiscountPct, 3);
    final six = [for (var i = 1; i <= 6; i++) inv('2026-10-0$i')];
    expect(classifyRegular(six, today: today).tier, RegularTier.casero);
    expect(classifyRegular(six, today: today).suggestedDiscountPct, 5);
  });
  test('no cuenta borradores, anuladas, notas de crédito ni compras de hace más de 90 días', () {
    final list = [
      inv('2026-10-01', status: 'draft'),
      inv('2026-10-02', voided: true),
      inv('2026-10-03', kind: 'nota_credito'),
      inv('2025-01-01'),
      inv('2025-02-01'),
      inv('2025-03-01'),
    ];
    final r = classifyRegular(list, today: today);
    expect(r.purchases90, 0);
    expect(r.purchasesTotal, 3);
    expect(r.tier, RegularTier.nuevo);
  });

  test('cada rubro tiene su ritmo: 3 compras en un mes es casero de bodega pero 3 en 180 días no hacen fiel a un paciente', () {
    final tres = [for (final d in ['2026-10-05', '2026-10-15', '2026-10-25', '2026-10-27']) inv(d)];
    expect(classifyRegular(tres, today: today, rubro: 'bodega').tier, RegularTier.frecuente); // 4 en 30 días
    expect(classifyRegular(tres, today: today, rubro: 'bodega').label, 'Frecuente');
    final ocho = [for (var i = 1; i <= 8; i++) inv('2026-10-0$i')];
    final b = classifyRegular(ocho, today: today, rubro: 'bodega');
    expect(b.tier, RegularTier.casero);
    expect(b.label, 'Casero');
    final c = classifyRegular(tres, today: today, rubro: 'consultorio');
    expect(c.tier, RegularTier.casero); // 4 en 180 días = paciente fiel
    expect(c.label, 'Paciente fiel');
    expect(classifyRegular([inv('2026-10-05'), inv('2026-10-06')], today: today, rubro: 'consultorio').label, 'Paciente recurrente');
    for (final r in regularRules.values) {
      expect(r.loyal > r.frequent, isTrue);
    }
  });

  test('serie diaria del servidor: rellena con 0 los días sin ventas y ubica hoy al final', () {
    final out = fillDailySeries([
      {'bucket': '2026-10-29', 'total': 120.5},
      {'bucket': '2026-10-27', 'total': 30},
      {'bucket': '2026-09-01', 'total': 999}, // fuera de la ventana: se ignora
    ], today: '2026-10-29', days: 14);
    expect(out.length, 14);
    expect(out.last, 120.5);
    expect(out[11], 30);
    expect(out.reduce((a, b) => a + b), 150.5);
  });
}
