// Cálculo fiscal por LÍNEA (como valida SUNAT): el IGV total es la suma del IGV de cada línea.
export type Afectacion = "gravado" | "exonerado" | "inafecto";

export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
export const round6 = (n: number) => Math.round((n + Number.EPSILON) * 1e6) / 1e6;

export type Line = { description: string; quantity: number; unit_price: number };

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
