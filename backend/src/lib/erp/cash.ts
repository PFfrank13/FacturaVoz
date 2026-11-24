/** Pure helpers for the web Caja module (no I/O, fully testable). Mirrors the mobile «Caja y cierre del día». */
import type { DaySummary } from "@/lib/dayclose";

export const methodLabel: Record<string, string> = {
  efectivo: "Efectivo", yape: "Yape", plin: "Plin", transferencia: "Transferencia", tarjeta: "Tarjeta", mercadopago: "Mercado Pago", otro: "Otro",
};

export type CashMove = { id: string; kind: "apertura" | "ingreso" | "egreso"; amount: number; method: string; note: string | null; created_at: string; user_id?: string | null };
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

export type CashierRow = { user_id: string; name: string; cashSales: number; digital: number; opening: number; cashIn: number; cashOut: number; expected: number; count: number };

/**
 * Who handled what today (docs/INVESTIGACION_RETAIL.md, row 5: internal theft and collusion): sales collected by each
 * person, split cash / digital, plus the cash movements they recorded. Expected cash = opening + cash sales + cash in −
 * cash out, per person, so the owner can count each drawer when there is more than one cashier.
 */
export function cashierBreakdown(payments: { user_id: string; method: string; amount: number | string }[], moves: CashMove[], names: Map<string, string | null>): CashierRow[] {
  const rows = new Map<string, CashierRow>();
  const row = (id: string) => {
    let r = rows.get(id);
    if (!r) { r = { user_id: id, name: names.get(id) || "Sin nombre", cashSales: 0, digital: 0, opening: 0, cashIn: 0, cashOut: 0, expected: 0, count: 0 }; rows.set(id, r); }
    return r;
  };
  for (const p of payments) {
    const r = row(p.user_id);
    if (p.method === "efectivo") r.cashSales += n(p.amount); else r.digital += n(p.amount);
    r.count++;
  }
  for (const m of moves) {
    if (!m.user_id || m.method !== "efectivo") continue;
    const r = row(m.user_id);
    if (m.kind === "apertura") r.opening += n(m.amount);
    else if (m.kind === "ingreso") r.cashIn += n(m.amount);
    else r.cashOut += n(m.amount);
  }
  const r2 = (v: number) => Math.round(v * 100) / 100;
  return [...rows.values()].map(r => ({ ...r, cashSales: r2(r.cashSales), digital: r2(r.digital), opening: r2(r.opening), cashIn: r2(r.cashIn), cashOut: r2(r.cashOut),
    expected: r2(r.opening + r.cashSales + r.cashIn - r.cashOut) })).sort((a, b) => b.cashSales + b.digital - (a.cashSales + a.digital) || a.name.localeCompare(b.name, "es"));
}

/** Quick entries for money that is not a sale (docs/INVESTIGACION_RETAIL.md, row 24): banking agent and top-ups. */
export const serviceMoves = [
  { id: "agente_deposito", label: "Depósito de agente", kind: "ingreso", note: "Agente: depósito de cliente" },
  { id: "agente_retiro", label: "Retiro de agente", kind: "egreso", note: "Agente: retiro de cliente" },
  { id: "recarga", label: "Recarga o pago de servicio", kind: "ingreso", note: "Recarga / servicio" },
] as const;

/** Agent and top-up money of the day, apart from sales: what came in, what went out, and the net in the drawer. */
export function serviceSummary(moves: CashMove[]) {
  let inflow = 0, outflow = 0, count = 0;
  for (const m of moves) {
    if (!m.note || !/^(Agente:|Recarga)/.test(m.note)) continue;
    count++;
    if (m.kind === "egreso") outflow += Number(m.amount); else if (m.kind === "ingreso") inflow += Number(m.amount);
  }
  const r = (v: number) => Math.round(v * 100) / 100;
  return { count, inflow: r(inflow), outflow: r(outflow), net: r(inflow - outflow) };
}

/** Peruvian notes and coins for the count (BCRP denominations in circulation). */
export const denominations = [200, 100, 50, 20, 10, 5, 2, 1, 0.5, 0.2, 0.1] as const;

/** Total of a count by denomination (in cents to avoid float errors). */
export function countTotal(qty: Record<string, number>): number {
  return denominations.reduce((s, d) => s + Math.round(d * 100) * Math.max(0, Math.floor(qty[String(d)] ?? 0)), 0) / 100;
}

/** Short text of the count for the closing note: "200×1 · 50×3 · 1×7". */
export function countText(qty: Record<string, number>): string {
  return denominations.filter(d => (qty[String(d)] ?? 0) > 0).map(d => `${d >= 1 ? d : d.toFixed(2)}×${Math.floor(qty[String(d)])}`).join(" · ");
}
