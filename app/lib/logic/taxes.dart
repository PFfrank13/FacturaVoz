// Estimador de impuestos del mes (REFERENCIAL: "revísalo con tu contador"). Mismas reglas que el servidor
// (backend/src/lib/taxes.ts). UIT 2026 = S/ 5,500 (D.S. 301-2025-EF).
//  NRUS: cuota S/ 20 (cat. 1, hasta S/ 5,000/mes) o S/ 50 (cat. 2, hasta S/ 8,000/mes); tope S/ 96,000 al año.
//        Los topes valen para ingresos Y para compras (SUNAT Emprender; docs/INVESTIGACION_RETAIL.md, fila 14).
//  RER: IGV + 1.5 % de los ingresos netos; tope S/ 525,000.
//  RMT: IGV + 1 % hasta 300 UIT acumuladas en el año, luego 1.5 % o coeficiente; tope 1,700 UIT.
//  General: IGV + 1.5 % o coeficiente.
import 'dart:math' as math;

const uit2026 = 5500.0;

const regimes = <String, String>{
  'nrus': 'Nuevo RUS',
  'rer': 'Régimen Especial (RER)',
  'rmt': 'Régimen MYPE Tributario (RMT)',
  'general': 'Régimen General',
};

double _r2(double n) => (n * 100).round() / 100;

class TaxEstimate {
  const TaxEstimate({required this.regime, required this.igv, required this.renta, required this.rentaRate, required this.notes, required this.warnings});
  final String? regime;
  final double igv;
  final double renta;
  final double? rentaRate;
  final List<String> notes;
  final List<String> warnings;
  double get total => _r2(igv + renta);
}

TaxEstimate estimateTaxes({
  required String? regime,
  required double monthSalesBase,
  required double monthSalesTax,
  required double monthPurchasesTax,
  required double yearSalesBase,
  double? monthPurchasesTotal,
  double? yearPurchasesTotal,
}) {
  final notes = <String>[];
  final warnings = <String>[];
  final base = math.max(0.0, monthSalesBase);
  final igvRaw = _r2(math.max(0.0, monthSalesTax) - math.max(0.0, monthPurchasesTax));
  final igv = math.max(0.0, igvRaw);
  if (igvRaw < 0) notes.add('Tienes saldo a favor de IGV por ${_r2(-igvRaw).toStringAsFixed(2)} que se usa el próximo mes.');
  switch (regime) {
    case 'nrus':
      final monthTotal = _r2(base + math.max(0.0, monthSalesTax));
      final monthBuys = _r2(math.max(0.0, monthPurchasesTotal ?? 0));
      final yearBuys = _r2(math.max(0.0, yearPurchasesTotal ?? 0));
      // La categoría la decide lo mayor entre lo que vendes y lo que compras en el mes.
      final cuota = math.max(monthTotal, monthBuys) <= 5000 ? 20.0 : 50.0;
      if (monthTotal > 8000) warnings.add('Este mes pasaste S/ 8,000: el Nuevo RUS ya no te corresponde. Habla con tu contador para cambiar de régimen.');
      if (monthBuys > 8000) warnings.add('Este mes tus compras pasaron S/ 8,000: el tope del Nuevo RUS también cuenta las compras. Habla con tu contador.');
      if (yearSalesBase > 96000) {
        warnings.add('En el año pasaste S/ 96,000: superaste el tope del Nuevo RUS.');
      } else if (yearSalesBase > 96000 * 0.8) {
        warnings.add('Vas por ${(yearSalesBase / 96000 * 100).round()} % del tope anual del Nuevo RUS (S/ 96,000).');
      }
      if (yearBuys > 96000) {
        warnings.add('En el año tus compras pasaron S/ 96,000: superaste el tope del Nuevo RUS.');
      } else if (yearBuys > 96000 * 0.8) {
        warnings.add('Tus compras del año van por ${(yearBuys / 96000 * 100).round()} % del tope del Nuevo RUS (S/ 96,000).');
      }
      if (monthTotal > 8000 || monthBuys > 8000 || yearSalesBase > 96000 || yearBuys > 96000) {
        notes.add('Si sales del Nuevo RUS, desde el mes siguiente debes emitir comprobantes electrónicos (RS 000075-2026).');
      }
      notes.add('En el Nuevo RUS la cuota mensual ya incluye IGV y renta. Solo puedes emitir boletas.');
      return TaxEstimate(regime: 'nrus', igv: 0, renta: cuota, rentaRate: null, notes: notes, warnings: warnings);
    case 'rer':
      if (yearSalesBase > 525000) {
        warnings.add('Pasaste S/ 525,000 en el año: el RER ya no te corresponde.');
      } else if (yearSalesBase > 525000 * 0.8) {
        warnings.add('Vas por ${(yearSalesBase / 525000 * 100).round()} % del tope anual del RER (S/ 525,000).');
      }
      return TaxEstimate(regime: 'rer', igv: igv, renta: _r2(base * 0.015), rentaRate: 0.015, notes: notes, warnings: warnings);
    case 'rmt':
      final over = yearSalesBase > 300 * uit2026;
      final rate = over ? 0.015 : 0.01;
      if (over) notes.add('Tus ventas del año pasaron 300 UIT: el pago a cuenta sube a 1.5 % (o coeficiente). Confírmalo con tu contador.');
      if (yearSalesBase > 1700 * uit2026) warnings.add('Pasaste 1,700 UIT en el año: corresponde el Régimen General.');
      return TaxEstimate(regime: 'rmt', igv: igv, renta: _r2(base * rate), rentaRate: rate, notes: notes, warnings: warnings);
    case 'general':
      notes.add('Pago a cuenta estimado con 1.5 %; si tienes coeficiente, tu contador lo ajusta.');
      return TaxEstimate(regime: 'general', igv: igv, renta: _r2(base * 0.015), rentaRate: 0.015, notes: notes, warnings: warnings);
    default:
      notes.add('Indica tu régimen tributario para estimar la renta. Por ahora solo se calcula el IGV.');
      return TaxEstimate(regime: null, igv: igv, renta: 0, rentaRate: null, notes: notes, warnings: warnings);
  }
}

/// "Cuánto me queda de verdad": ventas sin IGV − costo de lo vendido − gastos sin IGV − renta estimada.
class RealProfit {
  const RealProfit({required this.sales, required this.costOfSales, required this.expenses, required this.taxes});
  final double sales;
  final double costOfSales;
  final double expenses;
  final double taxes;
  double get gross => _r2(sales - costOfSales);
  double get net => _r2(sales - costOfSales - expenses - taxes);
  double get margin => sales <= 0 ? 0 : net / sales;
}
