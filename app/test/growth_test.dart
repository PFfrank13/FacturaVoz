import 'package:facturavoz/growth.dart';
import 'package:facturavoz/models.dart';
import 'package:facturavoz/models_growth.dart';
import 'package:flutter_test/flutter_test.dart';

ClientActivity act(String name, {int purchases = 3, double total = 300, double? gap = 10, int since = 5, String last = '2026-10-20'}) => ClientActivity(
      key: name.toLowerCase(),
      name: name,
      email: '',
      purchases: purchases,
      total: total,
      firstPurchase: '2026-01-01',
      lastPurchase: last,
      avgGap: gap,
      daysSince: since,
    );

InvoiceRecord sale(String date, double price, {String status = 'sent'}) => InvoiceRecord(
      id: date + price.toString(),
      number: 'F',
      issueDate: date,
      status: status,
      currency: 'PEN',
      taxRate: 0,
      notes: '',
      clientName: 'X',
      clientTaxId: '',
      clientDocType: '',
      items: [LineItem(description: 'x', quantity: 1, unitPrice: price)],
    );

void main() {
  test('meta del mes: proyección y lo que falta por día', () {
    final g = goalProgress(goal: 5000, sales: 1000, today: '2026-10-10');
    expect(g.daysInMonth, 31);
    expect(g.daysLeft, 22);
    expect(g.projected, 3100);
    expect(g.neededPerDay, 181.82);
    expect(g.percent, closeTo(0.2, 1e-9));
    expect(g.onTrack, isFalse);
    expect(goalProgress(goal: 1000, sales: 1500, today: '2026-02-28').reached, isTrue);
  });

  test('ventas por día de las últimas 2 semanas', () {
    final s = dailySeries([sale('2026-10-27', 10), sale('2026-10-14', 5), sale('2026-10-13', 99), sale('2026-10-27', 1, status: 'draft')],
        currency: 'PEN', today: '2026-10-27');
    expect(s.length, 14);
    expect(s.last, 10);
    expect(s.first, 5);
  });

  test('segmentación de clientes', () {
    final r = segmentClients([
      act('Grande', purchases: 10, total: 9000, gap: 10, since: 3),
      act('Se va', purchases: 5, total: 2000, gap: 10, since: 40),
      act('Perdido', purchases: 4, total: 1000, gap: 20, since: 120),
      act('Nuevo', purchases: 1, total: 50, gap: null, since: 10),
      act('Fiel', purchases: 4, total: 900, gap: 15, since: 10),
      act('Rara vez', purchases: 1, total: 30, gap: null, since: 200),
    ], '2026-10-27');
    Segment of(String n) => r.firstWhere((i) => i.activity.name == n).segment;
    expect(of('Grande'), Segment.vip);
    expect(of('Se va'), Segment.atRisk);
    expect(of('Perdido'), Segment.lost);
    expect(of('Nuevo'), Segment.newcomer);
    expect(of('Fiel'), Segment.loyal);
    expect(of('Rara vez'), Segment.occasional);
    final seVa = r.firstWhere((i) => i.activity.name == 'Se va');
    expect(seVa.atRiskValue, 400);
    expect(clientMessage(seVa, 'Dulce Lupe'), contains('extrañamos'));
  });

  test('precios y márgenes', () {
    expect(priceForMargin(cost: 30, margin: 0.4), 50);
    expect(marginOf(price: 50, cost: 30), closeTo(0.4, 1e-9));
    expect(marginOf(price: 50, cost: null), isNull);
  });

  test('fechas de recurrencia y slug de la tienda', () {
    expect(firstRunDate('2026-10-05', 5), '2026-10-05');
    expect(firstRunDate('2026-10-06', 5), '2026-11-05');
    expect(firstRunDate('2026-12-20', 1), '2027-01-01');
    expect(slugify('Dulce Lupe S.A.C.'), 'dulce-lupe');
    expect(slugify('Ferretería Díaz & Hijos'), 'ferreteria-diaz-hijos');
    expect(slugify('!!'), 'mi-tienda');
  });
}
