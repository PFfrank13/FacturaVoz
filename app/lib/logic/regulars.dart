// Cliente frecuente / casero: se calcula SOLO con sus compras reales (comprobantes que cuentan como venta).
// Cada rubro tiene su ritmo (un casero de bodega compra cada semana; un paciente vuelve cada pocos meses):
//  - "Fiel" (casero):  compras en la ventana >= umbral alto.   - "Frecuente": >= umbral bajo.
//  - Nuevo: tiene compras pero menos que el umbral bajo.       - Sin compras: ninguna.
// Los umbrales y las palabras salen de [regularRules]. El descuento es una SUGERENCIA para que el dueño decida
// (3 % frecuente, 5 % fiel); la app no lo aplica sola.
import '../models.dart';

enum RegularTier { sinCompras, nuevo, frecuente, casero }

/// Ritmo de compra de un rubro: ventana en días y compras para ser "frecuente" y "fiel".
class RegularRules {
  const RegularRules({required this.windowDays, required this.frequent, required this.loyal, required this.loyalLabel, required this.frequentLabel});
  final int windowDays;
  final int frequent;
  final int loyal;
  final String loyalLabel;
  final String frequentLabel;
}

const defaultRegularRules = RegularRules(windowDays: 90, frequent: 3, loyal: 6, loyalLabel: 'Casero', frequentLabel: 'Frecuente');

/// Umbrales por rubro (valores iniciales razonables; el dueño puede pedir ajustarlos).
const regularRules = <String, RegularRules>{
  'bodega': RegularRules(windowDays: 30, frequent: 4, loyal: 8, loyalLabel: 'Casero', frequentLabel: 'Frecuente'),
  'restaurante': RegularRules(windowDays: 60, frequent: 3, loyal: 6, loyalLabel: 'Comensal fiel', frequentLabel: 'Comensal frecuente'),
  'servicios_tecnicos': RegularRules(windowDays: 180, frequent: 2, loyal: 3, loyalLabel: 'Cliente fiel', frequentLabel: 'Cliente recurrente'),
  'salon': RegularRules(windowDays: 90, frequent: 3, loyal: 5, loyalLabel: 'Cliente fiel', frequentLabel: 'Cliente frecuente'),
  'consultorio': RegularRules(windowDays: 180, frequent: 2, loyal: 4, loyalLabel: 'Paciente fiel', frequentLabel: 'Paciente recurrente'),
  'taller': RegularRules(windowDays: 180, frequent: 2, loyal: 3, loyalLabel: 'Cliente fiel', frequentLabel: 'Cliente recurrente'),
  'mayorista': RegularRules(windowDays: 90, frequent: 3, loyal: 5, loyalLabel: 'Cliente clave', frequentLabel: 'Cliente frecuente'),
  'educacion': RegularRules(windowDays: 90, frequent: 2, loyal: 3, loyalLabel: 'Familia fiel', frequentLabel: 'Familia recurrente'),
  'construccion': RegularRules(windowDays: 365, frequent: 2, loyal: 3, loyalLabel: 'Cliente fiel', frequentLabel: 'Cliente recurrente'),
};

class RegularInfo {
  const RegularInfo({this.rules = defaultRegularRules, required this.tier, required this.purchases90, required this.purchasesTotal, required this.spentTotal, this.lastPurchase});
  final RegularRules rules;
  final RegularTier tier;
  final int purchases90; // compras dentro de la ventana del rubro (90 días si no hay rubro)
  final int purchasesTotal;
  final double spentTotal;
  final String? lastPurchase; // yyyy-MM-dd

  String get label => switch (tier) {
        RegularTier.casero => rules.loyalLabel,
        RegularTier.frecuente => rules.frequentLabel,
        RegularTier.nuevo => 'Nuevo',
        RegularTier.sinCompras => 'Sin compras',
      };

  /// Descuento sugerido (en %). 0 = ninguno.
  double get suggestedDiscountPct => switch (tier) {
        RegularTier.casero => 5,
        RegularTier.frecuente => 3,
        _ => 0,
      };
}

/// [invoices]: comprobantes de UN cliente. [today]: 'yyyy-MM-dd'. [rubro]: define el ritmo (ventana y umbrales).
RegularInfo classifyRegular(Iterable<InvoiceRecord> invoices, {required String today, String? rubro}) {
  final rules = regularRules[rubro] ?? defaultRegularRules;
  final t = DateTime.parse(today);
  final from = t.subtract(Duration(days: rules.windowDays));
  var p90 = 0, total = 0;
  var spent = 0.0;
  String? last;
  for (final i in invoices) {
    if (!i.countsAsSale || i.isCreditNote) continue;
    total++;
    spent += i.totals.total;
    if (last == null || i.issueDate.compareTo(last) > 0) last = i.issueDate;
    final d = DateTime.tryParse(i.issueDate);
    if (d != null && !d.isBefore(from) && !d.isAfter(t)) p90++;
  }
  final tier = total == 0
      ? RegularTier.sinCompras
      : p90 >= rules.loyal
          ? RegularTier.casero
          : p90 >= rules.frequent
              ? RegularTier.frecuente
              : RegularTier.nuevo;
  return RegularInfo(rules: rules, tier: tier, purchases90: p90, purchasesTotal: total, spentTotal: round2(spent), lastPurchase: last);
}
