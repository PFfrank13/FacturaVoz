import 'dart:math' as math;

import 'finance.dart' show addDays, daysBetween;
import 'models.dart';
import 'models_growth.dart';
import 'reports.dart' show countsAsSale;

/// Lógica PURA de crecimiento (sin Flutter ni red): meta del mes, tendencia diaria,
/// segmentación de clientes (Clientes 360), precios y fechas de recurrencia.

// ───────────────────────── Meta del mes ─────────────────────────

class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.sales,
    required this.projected,
    required this.neededPerDay,
    required this.daysLeft,
    required this.dayOfMonth,
    required this.daysInMonth,
  });

  final double goal;
  final double sales;

  /// Venta estimada al cierre del mes, al ritmo actual.
  final double projected;

  /// Lo que falta vender por día (incluyendo hoy) para llegar a la meta.
  final double neededPerDay;
  final int daysLeft;
  final int dayOfMonth;
  final int daysInMonth;

  double get percent => goal <= 0 ? 0 : (sales / goal).clamp(0.0, 1.0).toDouble();
  double get projectedPercent => goal <= 0 ? 0 : projected / goal;
  bool get reached => goal > 0 && sales >= goal;
  bool get onTrack => projected >= goal;
}

GoalProgress goalProgress({required double goal, required double sales, required String today}) {
  final y = int.parse(today.substring(0, 4));
  final m = int.parse(today.substring(5, 7));
  final d = int.parse(today.substring(8, 10));
  final dim = DateTime.utc(y, m + 1, 0).day;
  final left = dim - d + 1;
  return GoalProgress(
    goal: goal,
    sales: round2(sales),
    projected: round2(sales / d * dim),
    neededPerDay: round2(math.max(0, goal - sales) / math.max(1, left)),
    daysLeft: left,
    dayOfMonth: d,
    daysInMonth: dim,
  );
}

/// Total vendido por día en los últimos [days] días (el último es hoy). Solo ventas válidas.
List<double> dailySeries(Iterable<InvoiceRecord> invoices, {required String currency, required String today, int days = 14}) {
  final out = List<double>.filled(days, 0);
  final start = addDays(today, -(days - 1));
  for (final i in invoices) {
    if (i.currency != currency || i.status == 'draft' || !countsAsSale(i) || i.issueDate.length < 10) continue;
    final k = daysBetween(start, i.issueDate);
    if (k < 0 || k >= days) continue;
    out[k] += i.totals.total;
  }
  return [for (final v in out) round2(v)];
}

// ───────────────────────── Clientes 360 ─────────────────────────

enum Segment { vip, loyal, atRisk, lost, newcomer, occasional }

String segmentLabel(Segment s) => switch (s) {
      Segment.vip => 'VIP',
      Segment.loyal => 'Fiel',
      Segment.atRisk => 'Se está yendo',
      Segment.lost => 'Perdido',
      Segment.newcomer => 'Nuevo',
      Segment.occasional => 'Ocasional',
    };

class ClientInsight {
  const ClientInsight(this.activity, this.segment, this.reason, this.expectedNextPurchase);
  final ClientActivity activity;
  final Segment segment;
  final String reason;

  /// Fecha en que debería volver a comprar según su costumbre (null si no hay patrón).
  final String? expectedNextPurchase;

  /// Venta que se pierde si no vuelve (un ticket promedio) para los que se están yendo o perdidos.
  double get atRiskValue => segment == Segment.atRisk || segment == Segment.lost ? activity.avgTicket : 0;
}

/// Clasifica a cada cliente según cuánto compra y si mantiene su ritmo habitual.
List<ClientInsight> segmentClients(List<ClientActivity> list, String today) {
  if (list.isEmpty) return const [];
  final sorted = [...list]..sort((a, b) => b.total.compareTo(a.total));
  // Top 20 % por facturación (mínimo 1) y activos = VIP.
  final vipCut = math.max(1, (sorted.length * 0.2).ceil());
  final vipKeys = sorted.take(vipCut).map((c) => c.key).toSet();
  final out = <ClientInsight>[];
  for (final c in sorted) {
    final gap = c.avgGap;
    final usual = gap == null ? null : math.max(gap, 7.0);
    final next = gap == null || c.lastPurchase.length < 10 ? null : addDays(c.lastPurchase, usual!.round());
    final Segment seg;
    final String why;
    if (c.purchases >= 2 && usual != null && c.daysSince > math.max(90, usual * 3)) {
      seg = Segment.lost;
      why = 'Compraba cada ${usual.round()} días y no vuelve hace ${c.daysSince}.';
    } else if (c.purchases >= 2 && usual != null && c.daysSince > math.max(30, usual * 1.8)) {
      seg = Segment.atRisk;
      why = 'Suele comprar cada ${usual.round()} días; ya van ${c.daysSince}.';
    } else if (vipKeys.contains(c.key) && c.purchases >= 2) {
      seg = Segment.vip;
      why = 'De tus mejores clientes: ${c.purchases} compras.';
    } else if (c.purchases >= 3) {
      seg = Segment.loyal;
      why = 'Compra con regularidad${usual == null ? '' : ' (cada ${usual.round()} días)'}.';
    } else if (c.purchases == 1 && c.daysSince <= 45) {
      seg = Segment.newcomer;
      why = 'Primera compra hace ${c.daysSince} días: invítalo a volver.';
    } else {
      seg = Segment.occasional;
      why = c.purchases == 1 ? 'Compró una vez hace ${c.daysSince} días.' : 'Compra de vez en cuando.';
    }
    out.add(ClientInsight(c, seg, why, next));
  }
  return out;
}

/// Mensaje de WhatsApp listo para enviar según el segmento (cálido, nunca insistente).
String clientMessage(ClientInsight i, String business) {
  final name = i.activity.name.trim().split(' ').first;
  final biz = business.trim().isEmpty ? 'nosotros' : business.trim();
  return switch (i.segment) {
    Segment.atRisk || Segment.lost => 'Hola $name, ¡te extrañamos en $biz! Tenemos novedades y un precio especial para ti esta semana. ¿Te preparo tu pedido de siempre?',
    Segment.vip => 'Hola $name, gracias por tu confianza en $biz. Como cliente preferente, te reservamos prioridad y una atención especial. ¿Necesitas algo esta semana?',
    Segment.newcomer => 'Hola $name, gracias por tu primera compra en $biz. ¿Todo bien con tu pedido? Cuando necesites algo más, aquí estamos.',
    _ => 'Hola $name, te saluda $biz. ¿Te puedo ayudar con algo esta semana?',
  };
}

// ───────────────────────── Precios ─────────────────────────

/// Margen sobre el precio de venta (0..1). null si no hay costo o precio.
double? marginOf({required double price, required double? cost}) => cost == null || price <= 0 ? null : (price - cost) / price;

/// Precio de venta (sin IGV) para lograr [margin] (0..0.95) con el costo dado.
double priceForMargin({required double cost, required double margin}) => round2(cost / (1 - margin.clamp(0.0, 0.95)));

// ───────────────────────── Recurrencia ─────────────────────────

/// Primera fecha >= hoy que cae en el [day] del mes (1..28).
String firstRunDate(String today, int day) {
  final y = int.parse(today.substring(0, 4));
  final m = int.parse(today.substring(5, 7));
  final d = int.parse(today.substring(8, 10));
  final thisMonth = DateTime.utc(y, m, day);
  return todayIso(d <= day ? thisMonth : DateTime.utc(y, m + 1, day));
}

/// Slug para la tienda a partir del nombre del negocio ("Dulce Lupe S.A.C." → "dulce-lupe").
String slugify(String name) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in name.toLowerCase().split('')) {
    final k = from.indexOf(ch);
    b.write(k >= 0 ? to[k] : ch);
  }
  var s = b.toString().replaceAll(RegExp(r'\b(s\.?a\.?c\.?|s\.?r\.?l\.?|e\.?i\.?r\.?l\.?|s\.?a\.?)$'), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 40) s = s.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  return s.length < 3 ? 'mi-tienda' : s;
}
