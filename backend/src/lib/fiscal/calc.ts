// Cálculo fiscal por LÍNEA (como valida SUNAT): el IGV total es la suma del IGV de cada línea.
export type Afectacion = "gravado" | "exonerado" | "inafecto";

export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
export const round6 = (n: number) => Math.round((n + Number.EPSILON) * 1e6) / 1e6;

/** icbper: bolsa plástica (ICBPER, Ley 30884). Su impuesto va DENTRO del precio cobrado. */
export type Line = { description: string; quantity: number; unit_price: number; icbper?: boolean };

export type CalcLine = {
  description: string;
  quantity: number;
  valorUnitario: number; // sin impuesto
  base: number; // valor de venta de la línea
  igv: number;
  precioUnitario: number; // con impuesto
};

export type Calc = {
  lines: CalcLine[];
  base: number;
  igv: number;
  total: number;
};

export function calc(lines: Line[], afectacion: Afectacion, rate: number): Calc {
  const out: CalcLine[] = lines.map((l) => {
    const quantity = round2(l.quantity);
    const valorUnitario = round2(l.unit_price);
    const base = round2(quantity * valorUnitario);
    const igv = afectacion === "gravado" ? round2((base * rate) / 100) : 0;
    return {
      description: l.description.trim(),
      quantity,
      valorUnitario,
      base,
      igv,
      precioUnitario: quantity > 0 ? round6((base + igv) / quantity) : 0,
    };
  });
  const base = round2(out.reduce((s, l) => s + l.base, 0));
  const igv = round2(out.reduce((s, l) => s + l.igv, 0));
  return { lines: out, base, igv, total: round2(base + igv) };
}

/** ICBPER por bolsa en soles (S/ 0.50 desde 2023, D.S. 244-2019-EF). */
export const ICBPER_RATE = 0.5;

export type IcbperLine = CalcLine & { icbper: number; factorIcbper: number };

/**
 * Separa el ICBPER del precio de las bolsas sin cambiar el total cobrado: de lo que paga el cliente por la línea
 * (valor + IGV) se reserva S/ 0.50 por bolsa y el resto es el valor de la bolsa con su IGV. Devuelve null en
 * una línea cuyo precio no alcanza para el impuesto (la venta no puede declararse así).
 */
export function splitIcbper(c: Calc, lines: Line[], afectacion: Afectacion, rate: number): { lines: IcbperLine[]; base: number; igv: number; icbper: number; total: number } | null {
  const out: IcbperLine[] = [];
  for (const [k, l] of c.lines.entries()) {
    if (!lines[k]?.icbper) { out.push({ ...l, icbper: 0, factorIcbper: 0 }); continue; }
    const icb = round2(l.quantity * ICBPER_RATE);
    const rest = round2(l.base + l.igv - icb);
    if (rest <= 0 || !Number.isInteger(l.quantity)) return null;
    const base = afectacion === "gravado" ? round2(rest / (1 + rate / 100)) : rest;
    const igv = round2(rest - base);
    out.push({ ...l, base, igv, valorUnitario: round6(base / l.quantity), precioUnitario: round6(rest / l.quantity), icbper: icb, factorIcbper: ICBPER_RATE });
  }
  const base = round2(out.reduce((s, l) => s + l.base, 0));
  const igv = round2(out.reduce((s, l) => s + l.igv, 0));
  const icbper = round2(out.reduce((s, l) => s + l.icbper, 0));
  return { lines: out, base, igv, icbper, total: round2(base + igv + icbper) };
}
