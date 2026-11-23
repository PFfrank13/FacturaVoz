/** Pure helpers for the web Caja module (no I/O, fully testable). Mirrors the mobile «Caja y cierre del día». */
import type { DaySummary } from "@/lib/dayclose";

export const methodLabel: Record<string, string> = {
  efectivo: "Efectivo", yape: "Yape", plin: "Plin", transferencia: "Transferencia", tarjeta: "Tarjeta", mercadopago: "Mercado Pago", otro: "Otro",
};

export type CashMove = { id: string; kind: "apertura" | "ingreso" | "egreso"; amount: number; method: string; note: string | null; created_at: string };
export type DayClosing = { counted_cash: number; expected_cash: number; difference: number | null; note: string | null; created_at: string };

const n = (v: unknown) => Number(v ?? 0) || 0;
const cents = (v: number) => Math.round(v * 100);

/** How the expected cash is built, line by line, as the database computes it (day_summary). */
export function cashBreakdown(s: DaySummary) {
  const fiadoCash = Math.max(0, n(s.expected_cash) - n(s.cash_opening) - n(s.cash_sales) - n(s.cash_in) + n(s.cash_out));
  return [
    { label: "Apertura", value: n(s.cash_opening), sign: 1 },
    { label: "Ventas cobradas en efectivo", value: n(s.cash_sales), sign: 1 },
    { label: "Abonos de fiado en efectivo", value: Math.round(fiadoCash * 100) / 100, sign: 1 },
    { label: "Otros ingresos en efectivo", value: n(s.cash_in), sign: 1 },
    { label: "Retiros y pagos en efectivo", value: n(s.cash_out), sign: -1 },
  ].filter(l => l.value !== 0 || l.label === "Apertura");
}

/** Payment methods of the day, largest first, with their share of the total collected. */
export function methodShares(s: DaySummary) {
  const rows = Object.entries(s.payments_by_method ?? {}).map(([method, total]) => ({ method, label: methodLabel[method] ?? method, total: n(total) })).filter(r => r.total > 0);
  const sum = rows.reduce((a, r) => a + r.total, 0);
  return rows.sort((a, b) => b.total - a.total).map(r => ({ ...r, share: sum ? Math.round((r.total / sum) * 100) : 0 }));
}

export type Difference = { kind: "cuadra" | "sobra" | "falta"; amount: number };

/** Counted vs expected, to the cent (one cent of tolerance, as the server). */
export function cashDifference(expected: number, counted: number): Difference {
  const d = cents(counted) - cents(expected);
  if (Math.abs(d) <= 1) return { kind: "cuadra", amount: 0 };
  return { kind: d > 0 ? "sobra" : "falta", amount: Math.abs(d) / 100 };
}

/** Parses a typed amount ("1 250,50", "S/ 80") into soles, or null. */
export function parseAmount(raw: string): number | null {
  const t = raw.replace(/s\/|\s/gi, "").replace(/,(\d{1,2})$/, ".$1").replace(/,/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return null;
  const v = Number(t);
  return Number.isFinite(v) && v < 1e8 ? Math.round(v * 100) / 100 : null;
}
