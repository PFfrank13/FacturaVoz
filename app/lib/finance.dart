import 'dart:math' as math;

import 'models.dart';
import 'models_pro.dart';
import 'reports.dart' show countsAsSale;

/// Inteligencia financiera PURA (sin Flutter ni red): se prueba con `flutter test`.
/// Score de crédito por cliente, antigüedad de deudas, predicción de cobro, flujo de caja proyectado,
/// rentabilidad del mes, avisos del día y conciliación de pagos por foto.

// ───────────────────────── Fechas ─────────────────────────

DateTime _d(String iso) => DateTime.parse('${iso.substring(0, 10)}T00:00:00Z');
int daysBetween(String fromIso, String toIso) => _d(toIso).difference(_d(fromIso)).inDays;
String addDays(String iso, int n) => todayIso(_d(iso).add(Duration(days: n)));
const shortMonths = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/// "dd/MM" para textos cortos.
String dayMonth(String iso) => iso.length >= 10 ? '${iso.substring(8, 10)}/${iso.substring(5, 7)}' : iso;

// ───────────────────────── Antigüedad de deudas ─────────────────────────

class Aging {
  const Aging(this.current, this.d1to30, this.d31to60, this.d61to90, this.d90plus);
  final double current;
  final double d1to30;
  final double d31to60;
  final double d61to90;
  final double d90plus;

  double get overdue => round2(d1to30 + d31to60 + d61to90 + d90plus);
  double get total => round2(current + overdue);
  List<double> get values => [current, d1to30, d31to60, d61to90, d90plus];
  static const labels = ['Por vencer', '1–30 días', '31–60', '61–90', '+90'];
}

Aging agingOf(Iterable<InvoiceRecord> invoices, String today) {
  final b = List<double>.filled(5, 0);
  for (final i in invoices) {
    if (!i.receivable) continue;
    final due = i.dueDate;
    if (due == null || due.compareTo(today) >= 0) {
      b[0] += i.balance;
      continue;
    }
    final late = daysBetween(due, today);
    b[late <= 30 ? 1 : late <= 60 ? 2 : late <= 90 ? 3 : 4] += i.balance;
  }
  return Aging(round2(b[0]), round2(b[1]), round2(b[2]), round2(b[3]), round2(b[4]));
}

// ───────────────────────── Score de crédito ─────────────────────────

enum Grade { a, b, c, d, unknown }

class ClientScore {
  const ClientScore(this.score, this.grade, this.label, this.advice);
  final int score;
  final Grade grade;
  final String label;
  final String advice;

  String get letter => switch (grade) { Grade.a => 'A', Grade.b => 'B', Grade.c => 'C', Grade.d => 'D', Grade.unknown => '?' };

  /// Probabilidad estimada de cobrar (para proyectar caja).
  double get collectProbability => switch (grade) { Grade.a => 0.95, Grade.b => 0.85, Grade.c => 0.65, Grade.d => 0.4, Grade.unknown => 0.75 };
}

/// Clave para cruzar un nombre de cliente con [ClientPayStats.key].
String clientKey(String name) => name.trim().toLowerCase();

ClientScore scoreClient(ClientPayStats? s) {
  if (s == null || (s.settled < 2 && s.overdueBalance <= 0.004 && s.maxDaysLate == 0)) {
    return const ClientScore(70, Grade.unknown, 'Cliente nuevo', 'Aún no hay historial suficiente. En montos altos, pide un adelanto.');
  }
  final late = s.avgDaysLate ?? 0;
  var score = 100.0;
  score -= math.min(50, late * 2.5);
  if (s.overdueBalance > 0.004) score -= 20;
  score -= s.maxDaysLate > 30 ? 15 : (s.maxDaysLate > 15 ? 8 : 0);
  final v = score.clamp(0, 100).round();
  final lateText = late >= 1 ? 'Paga en promedio ${late.round()} días después del vencimiento. ' : '';
  if (v >= 85) return ClientScore(v, Grade.a, 'Paga puntual', '${lateText}Puedes darle crédito con confianza.');
  if (v >= 65) return ClientScore(v, Grade.b, 'A veces se demora', '${lateText}Plazo corto (7–15 días) y recordatorio el día del vencimiento.');
  if (v >= 40) return ClientScore(v, Grade.c, 'Suele pagar tarde', '${lateText}Pide 50 % de adelanto o acorta el plazo.');
  return ClientScore(v, Grade.d, 'Riesgo alto', '${lateText}Mejor al contado hasta que se ponga al día.');
}

/// Fecha en que probablemente pagará esta factura, según su historial.
String expectedPayDate(InvoiceRecord inv, ClientPayStats? s, String today) {
  final String d;
  if (inv.dueDate != null) {
    d = addDays(inv.dueDate!, (s?.avgDaysLate ?? 0).round());
  } else {
    d = addDays(inv.issueDate, (s?.avgDaysToPay ?? 7).round());
  }
  // Si la fecha esperada ya pasó, lo más probable es que pague en los próximos días tras un recordatorio.
  return d.compareTo(today) < 0 ? addDays(today, 7) : d;
}

// ───────────────────────── Flujo de caja proyectado ─────────────────────────

class ForecastWeek {
  const ForecastWeek(this.start, this.inflow, this.outflow, this.cumulative);
  final String start; // yyyy-MM-dd
  final double inflow;
  final double outflow;
  final double cumulative;
  double get net => round2(inflow - outflow);
}

class CashForecast {
  const CashForecast(this.weeks, this.warning);
  final List<ForecastWeek> weeks;
  final String? warning;
  double get totalIn => round2(weeks.fold<double>(0, (s, w) => s + w.inflow));
  double get totalOut => round2(weeks.fold<double>(0, (s, w) => s + w.outflow));
  double get net => round2(totalIn - totalOut);
}

/// Gasto diario promedio (para proyectar salidas).
double dailyExpenseRate(Iterable<Expense> expenses, int days) =>
    days <= 0 ? 0 : round2(expenses.fold<double>(0, (s, e) => s + e.total) / days);

/// Proyección semanal: entradas = cobros esperados × probabilidad; salidas = ritmo de gasto.
CashForecast forecastCash({
  required Iterable<InvoiceRecord> receivables,
  required Map<String, ClientPayStats> stats,
  required double dailyExpense,
  required String today,
  int weeks = 5,
}) {
  final inflow = List<double>.filled(weeks, 0);
  for (final inv in receivables) {
    if (!inv.receivable) continue;
    final s = stats[clientKey(inv.clientName)];
    final when = expectedPayDate(inv, s, today);
    final k = daysBetween(today, when) ~/ 7;
    if (k < 0 || k >= weeks) continue;
    inflow[k] += inv.balance * scoreClient(s).collectProbability;
  }
  final out = <ForecastWeek>[];
  var cum = 0.0;
  String? warning;
  for (var k = 0; k < weeks; k++) {
    final o = round2(dailyExpense * 7);
    final i = round2(inflow[k]);
    cum = round2(cum + i - o);
    final start = addDays(today, k * 7);
    out.add(ForecastWeek(start, i, o, cum));
    if (warning == null && cum < 0) {
      warning = 'La semana del ${dayMonth(start)} tus gastos superarían lo que esperas cobrar. Adelanta cobros o pospone compras.';
    }
  }
  return CashForecast(out, warning);
}

// ───────────────────────── Rentabilidad ─────────────────────────

class ProfitSummary {
  const ProfitSummary({
    required this.sales,
    required this.salesTax,
    required this.expenses,
    required this.expenseTax,
    required this.cashIn,
    required this.cashOut,
    required this.invoiceCount,
  });

  /// Ventas sin IGV.
  final double sales;
  final double salesTax;

  /// Gastos sin IGV.
  final double expenses;
  final double expenseTax;
  final double cashIn;
  final double cashOut;
  final int invoiceCount;

  double get profit => round2(sales - expenses);
  double get margin => sales <= 0 ? 0 : profit / sales;
  double get netCash => round2(cashIn - cashOut);

  /// IGV estimado del mes: IGV de ventas menos crédito fiscal de compras (nunca negativo).
  double get igvEstimate => math.max(0, round2(salesTax - expenseTax));
}

bool _sale(InvoiceRecord i, String currency) => i.currency == currency && i.status != 'draft' && countsAsSale(i);

ProfitSummary profitOf({
  required Iterable<InvoiceRecord> invoices,
  required Iterable<Expense> expenses,
  required Iterable<DatedPayment> payments,
  required String currency,
}) {
  var sales = 0.0, salesTax = 0.0, exp = 0.0, expTax = 0.0, cashIn = 0.0, cashOut = 0.0;
  var n = 0;
  for (final i in invoices) {
    if (!_sale(i, currency)) continue;
    final t = i.totals;
    sales += t.subtotal;
    salesTax += t.tax;
    n++;
  }
  for (final e in expenses) {
    if (e.currency != currency) continue;
    exp += e.base;
    expTax += e.tax;
    cashOut += e.total;
  }
  for (final p in payments) {
    if (p.currency == currency) cashIn += p.amount;
  }
  return ProfitSummary(
    sales: round2(sales),
    salesTax: round2(salesTax),
    expenses: round2(exp),
    expenseTax: round2(expTax),
    cashIn: round2(cashIn),
    cashOut: round2(cashOut),
    invoiceCount: n,
  );
}

class MonthPoint {
  const MonthPoint(this.key, this.label, this.sales, this.expenses);
  final String key; // yyyy-MM
  final String label;
  final double sales; // sin IGV
  final double expenses; // sin IGV
}

/// Últimos [months] meses (el último es el de [today]).
List<MonthPoint> monthlySeries({
  required Iterable<InvoiceRecord> invoices,
  required Iterable<Expense> expenses,
  required String currency,
  required String today,
  int months = 6,
}) {
  final y = int.parse(today.substring(0, 4));
  final m = int.parse(today.substring(5, 7));
  final keys = <String>[];
  for (var k = months - 1; k >= 0; k--) {
    final d = DateTime.utc(y, m - k, 1);
    keys.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
  }
  final s = {for (final k in keys) k: 0.0};
  final e = {for (final k in keys) k: 0.0};
  for (final i in invoices) {
    if (!_sale(i, currency) || i.issueDate.length < 7) continue;
    final k = i.issueDate.substring(0, 7);
    if (s.containsKey(k)) s[k] = s[k]! + i.totals.subtotal;
  }
  for (final x in expenses) {
    if (x.currency != currency || x.spentOn.length < 7) continue;
    final k = x.spentOn.substring(0, 7);
    if (e.containsKey(k)) e[k] = e[k]! + x.base;
  }
  return [for (final k in keys) MonthPoint(k, shortMonths[int.parse(k.substring(5, 7)) - 1], round2(s[k]!), round2(e[k]!))];
}

/// Gastos por categoría, de mayor a menor.
List<MapEntry<String, double>> expensesByCategory(Iterable<Expense> expenses, String currency) {
  final m = <String, double>{};
  for (final e in expenses) {
    if (e.currency != currency) continue;
    m[e.category] = round2((m[e.category] ?? 0) + e.total);
  }
  return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

// ───────────────────────── Avisos del día ─────────────────────────

class Insight {
  const Insight({required this.kind, required this.title, required this.body, required this.tone});
  final String kind; // claims | overdue | due_soon | pace | stock
  final String title;
  final String body;
  final String tone; // ok | warn | bad | info
}

List<Insight> buildInsights({
  required List<InvoiceRecord> invoices,
  required String today,
  required String currency,
  List<ProductVelocity> stock = const [],
  int pendingClaims = 0,
  int storeOrders = 0,
  int recurringDrafts = 0,
}) {
  final out = <Insight>[];
  if (storeOrders > 0) {
    out.add(Insight(
      kind: 'store_orders',
      title: storeOrders == 1 ? '1 pedido web nuevo' : '$storeOrders pedidos web nuevos',
      body: 'Llegaron desde tu tienda en línea. Confírmalos y conviértelos en factura con un toque.',
      tone: 'ok',
    ));
  }
  if (pendingClaims > 0) {
    out.add(Insight(
      kind: 'claims',
      title: pendingClaims == 1 ? '1 pago reportado por confirmar' : '$pendingClaims pagos reportados por confirmar',
      body: 'Tus clientes avisaron que ya pagaron. Verifica y confirma con un toque.',
      tone: 'info',
    ));
  }
  if (recurringDrafts > 0) {
    out.add(Insight(
      kind: 'recurring',
      title: recurringDrafts == 1 ? '1 factura mensual lista' : '$recurringDrafts facturas mensuales listas',
      body: 'Se crearon solas según tu programación. Revísalas y emítelas.',
      tone: 'info',
    ));
  }
  final mine = invoices.where((i) => i.currency == currency).toList();
  final overdue = mine.where((i) => i.isOverdue(today)).toList()..sort((a, b) => b.balance.compareTo(a.balance));
  if (overdue.isNotEmpty) {
    final sum = round2(overdue.fold(0.0, (s, i) => s + i.balance));
    out.add(Insight(
      kind: 'overdue',
      title: '${money(sum, currency)} vencidos',
      body: '${overdue.length == 1 ? '1 factura vencida' : '${overdue.length} facturas vencidas'}. Empieza por ${overdue.first.clientName} (${money(overdue.first.balance, currency)}).',
      tone: 'bad',
    ));
  }
  final weekEnd = addDays(today, 7);
  final soon = mine.where((i) => i.receivable && i.dueDate != null && i.dueDate!.compareTo(today) >= 0 && i.dueDate!.compareTo(weekEnd) <= 0).toList();
  if (soon.isNotEmpty) {
    final sum = round2(soon.fold(0.0, (s, i) => s + i.balance));
    out.add(Insight(
      kind: 'due_soon',
      title: '${money(sum, currency)} vencen esta semana',
      body: 'Un recordatorio amable hoy evita atrasos mañana.',
      tone: 'warn',
    ));
  }
  // Ritmo del mes vs. el mes pasado a la misma fecha
  final day = int.parse(today.substring(8, 10));
  final thisMonth = today.substring(0, 7);
  final y = int.parse(today.substring(0, 4));
  final m = int.parse(today.substring(5, 7));
  final prev = DateTime.utc(y, m - 1, 1);
  final prevKey = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
  double cur = 0, last = 0;
  for (final i in mine) {
    if (!_sale(i, currency) || i.issueDate.length < 10) continue;
    final k = i.issueDate.substring(0, 7);
    final dd = int.parse(i.issueDate.substring(8, 10));
    if (k == thisMonth) cur += i.totals.total;
    if (k == prevKey && dd <= day) last += i.totals.total;
  }
  if (last > 0 && cur > 0) {
    final pct = ((cur - last) / last * 100).round();
    out.add(Insight(
      kind: 'pace',
      title: pct >= 0 ? 'Vas $pct % arriba del mes pasado' : 'Vas ${pct.abs()} % abajo del mes pasado',
      body: 'Comparado a la misma fecha: ${money(round2(cur), currency)} vs ${money(round2(last), currency)}.',
      tone: pct >= 0 ? 'ok' : 'warn',
    ));
  }
  final risky = stock.where((p) => p.atRisk).toList()..sort((a, b) => (a.daysLeft ?? 999).compareTo(b.daysLeft ?? 999));
  if (risky.isNotEmpty) {
    final p = risky.first;
    final dl = p.daysLeft;
    out.add(Insight(
      kind: 'stock',
      title: dl == null ? 'Stock bajo: ${p.name}' : (dl < 1 ? '${p.name}: sin stock' : '${p.name} se acaba en ~${dl.round()} días'),
      body: risky.length > 1 ? 'Y ${risky.length - 1} producto(s) más por reponer.' : 'Quedan ${qtyText(p.stock ?? 0)} unidades. Pide a tu proveedor a tiempo.',
      tone: dl != null && dl < 3 ? 'bad' : 'warn',
    ));
  }
  return out.take(6).toList();
}

// ───────────────────────── Conciliación de pagos por foto ─────────────────────────

const _stop = {'sac', 'srl', 'eirl', 'sa', 'saa', 'de', 'la', 'el', 'los', 'las', 'del', 'y', 'e', 'cia', 'sociedad', 'anonima', 'cerrada', 'empresa'};

String stripAccents(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final k = from.indexOf(ch);
    b.write(k >= 0 ? to[k] : ch);
  }
  return b.toString();
}

List<String> _tokens(String s) =>
    stripAccents(s).replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').split(RegExp(r'\s+')).where((t) => t.isNotEmpty && !_stop.contains(t)).toList();

/// 0..1: qué tanto se parecen dos nombres. Tolera abreviaturas de Yape ("Juan P. Pere*").
double nameSimilarity(String a, String b) {
  final ta = _tokens(a);
  final tb = _tokens(b);
  if (ta.isEmpty || tb.isEmpty) return 0;
  var hits = 0;
  final used = <int>{};
  for (final x in ta) {
    for (var j = 0; j < tb.length; j++) {
      if (used.contains(j)) continue;
      final y = tb[j];
      final ok = x == y || (x.length >= 3 && y.startsWith(x)) || (y.length >= 3 && x.startsWith(y)) || (x.length == 1 && y.startsWith(x));
      if (ok) {
        hits++;
        used.add(j);
        break;
      }
    }
  }
  return hits / math.min(ta.length, tb.length);
}

class MatchCandidate {
  const MatchCandidate(this.invoice, this.score, this.reasons);
  final InvoiceRecord invoice;
  final int score; // 0..100
  final List<String> reasons;
}

/// Ordena las facturas por cobrar según qué tan probable es que [p] sea su pago.
List<MatchCandidate> matchPayment(PaymentScan p, Iterable<InvoiceRecord> receivables, String today) {
  final out = <MatchCandidate>[];
  for (final inv in receivables) {
    if (!inv.receivable || inv.currency != p.currency) continue;
    var s = 0;
    final why = <String>[];
    if ((p.amount - inv.balance).abs() <= 0.01) {
      s += 55;
      why.add('Monto exacto del saldo');
    } else if ((p.amount - inv.totals.total).abs() <= 0.01) {
      s += 45;
      why.add('Monto igual al total');
    } else if (p.amount > 0 && p.amount < inv.balance) {
      s += 12;
      why.add('Posible pago parcial');
    } else {
      continue; // pagó más que el saldo: no es esta factura
    }
    final sim = nameSimilarity(p.payerName, inv.clientName);
    s += (sim * 35).round();
    if (sim >= 0.5) why.add('El nombre coincide');
    if (inv.dueDate != null && daysBetween(today, inv.dueDate!) <= 7) s += 5;
    out.add(MatchCandidate(inv, math.min(100, s), why));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.where((c) => c.score >= 15).take(5).toList();
}
