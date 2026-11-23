/** Bulk price changes and shelf labels (docs/INVESTIGACION_RETAIL.md, row 21: costs move every ~15 days). Pure. */

export type PriceMode = "subir_pct" | "bajar_pct" | "subir_monto" | "bajar_monto";
export const priceModes: Record<PriceMode, string> = {
  subir_pct: "Subir %", bajar_pct: "Bajar %", subir_monto: "Subir S/", bajar_monto: "Bajar S/",
};

/**
 * New price WITH IGV for a product whose stored price is WITHOUT IGV. The owner thinks in shelf prices,
 * so the change and the rounding (to 0.10 by default) apply to the price the customer pays; the result is
 * converted back to the stored base. Never goes below 0.10.
 */
export function newShelfPrice(shelf: number, mode: PriceMode, value: number, roundTo = 0.1): number {
  const v = Math.abs(value);
  let next = mode === "subir_pct" ? shelf * (1 + v / 100) : mode === "bajar_pct" ? shelf * (1 - v / 100) : mode === "subir_monto" ? shelf + v : shelf - v;
  if (roundTo > 0) next = Math.round(next / roundTo) * roundTo;
  return Math.max(0.1, Math.round(next * 100) / 100);
}

export const withTax = (base: number, rate: number) => Math.round(base * (1 + rate / 100) * 100) / 100;
/**
 * Stored base (without IGV, 2 decimals as the database keeps it) for a shelf price: of the two nearest cents it
 * picks the one whose price with IGV gives back the shelf price, so the label and the receipt say the same.
 */
export function withoutTax(shelf: number, rate: number): number {
  const exact = shelf / (1 + rate / 100);
  const down = Math.floor(exact * 100) / 100, up = Math.ceil(exact * 100) / 100;
  for (const c of [Math.round(exact * 100) / 100, down, up]) if (withTax(c, rate) === Math.round(shelf * 100) / 100) return c;
  return Math.round(exact * 100) / 100;
}

export function pricingProblem(mode: string, value: number | null): string | null {
  if (!Object.hasOwn(priceModes, mode)) return "Elige si subes o bajas, en % o en soles.";
  if (value == null || !(value > 0)) return "Escribe cuánto cambia el precio.";
  if (mode.endsWith("pct") && value > 90) return "El cambio no puede pasar de 90 %.";
  return null;
}
