/**
 * Pure helpers for lots, expiry dates and shrinkage (mermas), no I/O.
 * Research basis: docs/INVESTIGACION_RETAIL.md, rows 3 and 4 (half of known shrinkage is expiry and damage).
 */

export type LotStatus = {
  lot_id: string; product_id: string; product_name: string; unit: string; lot_code: string | null; expires_on: string;
  quantity: number; remaining: number; days_left: number; unit_cost: number | null; unit_price: number | null;
};

export type LossRow = {
  id: string; product_id: string; quantity: number; reason: LossReason; note: string | null; unit_cost: number | null;
  created_at: string; product_name: string; lot_code: string | null; expires_on: string | null; user_name: string | null;
};

export const lossReasons = {
  vencido: "Vencido",
  danado: "Dañado o roto",
  robo: "Robo o faltante",
  consumo: "Consumo interno",
  canje: "Devuelto al proveedor",
  otro: "Otro motivo",
} as const;
export type LossReason = keyof typeof lossReasons;
export const isLossReason = (v: string): v is LossReason => Object.hasOwn(lossReasons, v);

/** How urgent a lot is: already expired, this week, this month, or fine. */
export function expiryBucket(daysLeft: number): "vencido" | "semana" | "mes" | "ok" {
  if (daysLeft < 0) return "vencido";
  if (daysLeft <= 7) return "semana";
  if (daysLeft <= 30) return "mes";
  return "ok";
}

/** Lots that still have stock on the shelf, most urgent first. */
export function activeLots(lots: LotStatus[]): LotStatus[] {
  return lots.filter(l => l.remaining > 0).sort((a, b) => a.days_left - b.days_left || a.product_name.localeCompare(b.product_name, "es"));
}

/** Counts and money at risk (remaining units × cost; price when there is no cost) per bucket. */
export function summarizeLots(lots: LotStatus[]) {
  const out = { vencido: { count: 0, units: 0, value: 0 }, semana: { count: 0, units: 0, value: 0 }, mes: { count: 0, units: 0, value: 0 } };
  for (const l of activeLots(lots)) {
    const b = expiryBucket(l.days_left);
    if (b === "ok") continue;
    out[b].count++;
    out[b].units = round2(out[b].units + l.remaining);
    out[b].value = round2(out[b].value + l.remaining * Number(l.unit_cost ?? l.unit_price ?? 0));
  }
  return out;
}

/**
 * Suggested sale price for a lot close to expiry: 30 % off in the last 3 days, 15 % off within the week,
 * never below cost + 2 % (selling at a small margin beats throwing it away). Null when no change is needed.
 */
export function suggestedPrice(price: number | null, cost: number | null, daysLeft: number): number | null {
  if (price == null || !(price > 0) || daysLeft < 0 || daysLeft > 7) return null;
  const off = daysLeft <= 3 ? 0.3 : 0.15;
  const floor = cost != null && cost > 0 ? cost * 1.02 : 0;
  const value = Math.max(price * (1 - off), floor);
  return value < price - 0.004 ? Math.round(value * 10) / 10 : null;
}

/** The first problem with a shrinkage entry, in the owner's words, or null. */
export function lossProblem(quantity: number | null, reason: string, note: string, stock: number | null): string | null {
  if (stock == null) return "Este producto no controla stock: actívalo primero.";
  if (quantity == null || !(quantity > 0) || Math.abs(quantity * 100 - Math.round(quantity * 100)) > 1e-6) return "Escribe una cantidad mayor que cero, con hasta 2 decimales.";
  if (quantity > stock) return `La merma no puede superar el stock actual (${stock}).`;
  if (!isLossReason(reason)) return "Elige el motivo de la merma.";
  if (reason === "otro" && !note.trim()) return "Escribe el motivo de la merma.";
  if (note.trim().length > 200) return "La nota admite hasta 200 caracteres.";
  return null;
}

/** Shrinkage in money per reason, plus its share of sales when sales are known. */
export function summarizeLosses(rows: LossRow[], salesTotal: number | null) {
  const byReason = new Map<LossReason, { reason: LossReason; label: string; value: number; count: number }>();
  let total = 0;
  for (const r of rows) {
    const value = r.quantity * Number(r.unit_cost ?? 0);
    total += value;
    const row = byReason.get(r.reason) ?? { reason: r.reason, label: lossReasons[r.reason], value: 0, count: 0 };
    row.value += value; row.count++;
    byReason.set(r.reason, row);
  }
  const reasons = [...byReason.values()].map(r => ({ ...r, value: round2(r.value) })).sort((a, b) => b.value - a.value);
  const share = salesTotal && salesTotal > 0 ? Math.round((total / salesTotal) * 1000) / 10 : null;
  return { total: round2(total), reasons, share, uncosted: rows.filter(r => r.unit_cost == null).length };
}

const round2 = (n: number) => Math.round(n * 100) / 100;
