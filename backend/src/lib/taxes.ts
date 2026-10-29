/**
 * Estimador de impuestos del mes para Perú (REFERENCIAL: siempre "revísalo con tu contador").
 * Reglas 2026 (UIT = S/ 5,500, D.S. 301-2025-EF):
 *  - NRUS: cuota mensual S/ 20 (categoría 1: ingresos o compras hasta S/ 5,000 al mes) o S/ 50 (categoría 2: hasta
 *    S/ 8,000). Incluye IGV y renta. Tope anual S/ 96,000. Solo boletas (no facturas).
 *  - RER: IGV 18 % + renta 1.5 % de los ingresos netos del mes. Tope anual S/ 525,000.
 *  - RMT: IGV 18 % + pago a cuenta 1 % de los ingresos netos del mes mientras lo acumulado del año no pase 300 UIT;
 *    luego 1.5 % o coeficiente. Tope 1,700 UIT.
 *  - Régimen General: IGV 18 % + pago a cuenta 1.5 % o coeficiente (el que corresponda).
 * IGV del mes = IGV de ventas − crédito fiscal de compras con comprobante (nunca negativo; el saldo a favor se arrastra).
 */
export type Regime = "nrus" | "rer" | "rmt" | "general";
export const UIT = 5500;

export type TaxInput = {
  regime: Regime | null;
  monthSalesBase: number; // ventas del mes sin IGV
  monthSalesTax: number; // IGV de ventas del mes
  monthPurchasesTax: number; // IGV de compras del mes (crédito fiscal)
  yearSalesBase: number; // ventas acumuladas del año (sin IGV), incluido este mes
};

export type TaxEstimate = {
  regime: Regime | null;
  igv: number;
  renta: number;
  total: number;
  rentaRate: number | null;
  notes: string[];
  warnings: string[];
};

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

export function estimateTaxes(i: TaxInput): TaxEstimate {
  const notes: string[] = [];
  const warnings: string[] = [];
  const base = Math.max(0, i.monthSalesBase);
  const igvRaw = r2(Math.max(0, i.monthSalesTax) - Math.max(0, i.monthPurchasesTax));
  const igv = Math.max(0, igvRaw);
  if (igvRaw < 0) notes.push(`Tienes saldo a favor de IGV por ${r2(-igvRaw)} que se usa el próximo mes.`);
  switch (i.regime) {
    case "nrus": {
      const monthTotal = r2(base + Math.max(0, i.monthSalesTax));
      const cuota = monthTotal <= 5000 ? 20 : monthTotal <= 8000 ? 50 : 50;
      if (monthTotal > 8000) warnings.push("Este mes pasaste S/ 8,000: el Nuevo RUS ya no te corresponde. Habla con tu contador para cambiar de régimen.");
      if (i.yearSalesBase > 96000) warnings.push("En el año pasaste S/ 96,000: superaste el tope del Nuevo RUS.");
      else if (i.yearSalesBase > 96000 * 0.8) warnings.push(`Vas por ${Math.round((i.yearSalesBase / 96000) * 100)} % del tope anual del Nuevo RUS (S/ 96,000).`);
      notes.push("En el Nuevo RUS la cuota mensual ya incluye IGV y renta. Solo puedes emitir boletas.");
      return { regime: "nrus", igv: 0, renta: cuota, total: cuota, rentaRate: null, notes, warnings };
    }
    case "rer": {
      const renta = r2(base * 0.015);
      if (i.yearSalesBase > 525000) warnings.push("Pasaste S/ 525,000 en el año: el RER ya no te corresponde.");
      else if (i.yearSalesBase > 525000 * 0.8) warnings.push(`Vas por ${Math.round((i.yearSalesBase / 525000) * 100)} % del tope anual del RER (S/ 525,000).`);
      return { regime: "rer", igv, renta, total: r2(igv + renta), rentaRate: 0.015, notes, warnings };
    }
    case "rmt": {
      const over = i.yearSalesBase > 300 * UIT;
      const rate = over ? 0.015 : 0.01;
      if (over) notes.push("Tus ventas del año pasaron 300 UIT: el pago a cuenta sube a 1.5 % (o coeficiente). Confírmalo con tu contador.");
      if (i.yearSalesBase > 1700 * UIT) warnings.push("Pasaste 1,700 UIT en el año: corresponde el Régimen General.");
      const renta = r2(base * rate);
      return { regime: "rmt", igv, renta, total: r2(igv + renta), rentaRate: rate, notes, warnings };
    }
    case "general": {
      const renta = r2(base * 0.015);
      notes.push("Pago a cuenta estimado con 1.5 %; si tienes coeficiente, tu contador lo ajusta.");
      return { regime: "general", igv, renta, total: r2(igv + renta), rentaRate: 0.015, notes, warnings };
    }
    default:
      notes.push("Indica tu régimen tributario en Ajustes para estimar la renta. Por ahora solo se calcula el IGV.");
      return { regime: null, igv, renta: 0, total: igv, rentaRate: null, notes, warnings };
  }
}
