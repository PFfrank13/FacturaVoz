/** Pure helpers for the web Cobros module (no I/O, fully testable). Same `payments` rows the mobile app records. */
import { methodLabel } from "@/lib/erp/cash";
import { receiptNumber, type FiscalInfo } from "@/lib/erp/receipts";

export type PaymentRow = {
  id: string; amount: number; paid_on: string; method: string; note: string | null; created_at: string;
  invoice: {
    id: string; number: string; currency: string | null; amt_total: number | null;
    client: { name: string | null; tax_id: string | null } | null;
    fiscal: Pick<FiscalInfo, "series" | "correlative"> | null;
  } | null;
};

const month = /^\d{4}-(0[1-9]|1[0-2])$/;

/** `?mes=YYYY-MM` from the URL; anything invalid or in the future falls back to the current month. */
export function parseMonth(raw: unknown, today: string): string {
  const current = today.slice(0, 7);
  return typeof raw === "string" && month.test(raw) && raw <= current && raw >= "2000-01" ? raw : current;
}

export function shiftMonth(m: string, delta: number): string {
  const [y, mo] = m.split("-").map(Number);
  const d = new Date(Date.UTC(y, mo - 1 + delta, 1));
  return d.toISOString().slice(0, 7);
}

/** First and last calendar day of a month (both included). */
export function monthBounds(m: string): { from: string; to: string; days: number } {
  const [y, mo] = m.split("-").map(Number);
  const days = new Date(Date.UTC(y, mo, 0)).getUTCDate();
  return { from: `${m}-01`, to: `${m}-${String(days).padStart(2, "0")}`, days };
}

export function paymentReceipt(p: PaymentRow): string {
  return p.invoice ? receiptNumber({ number: p.invoice.number, fiscal: p.invoice.fiscal as FiscalInfo | null }) : "Comprobante";
}

/** Totals in the company currency; payments of receipts in another currency are counted apart, never mixed. */
export function summarizePayments(rows: PaymentRow[], currency: string, m: string, today: string) {
  const own = rows.filter(r => (r.invoice?.currency || currency) === currency);
  const cents = (v: number) => Math.round(v * 100);
  const totalCents = own.reduce((a, r) => a + cents(r.amount), 0);
  const byMethod = new Map<string, number>();
  for (const r of own) byMethod.set(r.method, (byMethod.get(r.method) ?? 0) + cents(r.amount));
  const methods = [...byMethod].map(([method, c]) => ({ method, label: methodLabel[method] ?? method, total: c / 100, share: totalCents ? Math.round((c / totalCents) * 100) : 0 }))
    .sort((a, b) => b.total - a.total);
  const { days } = monthBounds(m);
  const lastDay = m === today.slice(0, 7) ? Number(today.slice(8, 10)) : days;
  const perDay = Array.from({ length: days }, (_, i) => ({ day: i + 1, total: 0, count: 0, future: i + 1 > lastDay }));
  for (const r of own) {
    const d = Number(r.paid_on.slice(8, 10));
    if (r.paid_on.startsWith(m) && perDay[d - 1]) { perDay[d - 1].total += r.amount; perDay[d - 1].count += 1; }
  }
  const max = Math.max(0, ...perDay.map(d => d.total));
  const best = max > 0 ? perDay.find(d => d.total === max)!.day : null;
  const digital = own.filter(r => r.method !== "efectivo").reduce((a, r) => a + cents(r.amount), 0);
  return {
    total: totalCents / 100,
    count: own.length,
    average: own.length ? Math.round(totalCents / own.length) / 100 : 0,
    digitalShare: totalCents ? Math.round((digital / totalCents) * 100) : 0,
    methods,
    days: perDay.map(d => ({ ...d, total: Math.round(d.total * 100) / 100, height: max ? Math.round((d.total / max) * 100) / 100 : 0 })),
    best,
    other: rows.length - own.length,
  };
}

export type PaymentFilter = { q?: string; method?: string };

export function matchesPayment(p: PaymentRow, f: PaymentFilter): boolean {
  if (f.method && f.method !== "todos" && p.method !== f.method) return false;
  const q = f.q?.trim().toLocaleLowerCase("es");
  if (!q) return true;
  return [paymentReceipt(p), p.invoice?.number ?? "", p.invoice?.client?.name ?? "", p.invoice?.client?.tax_id ?? "", p.note ?? ""]
    .some(v => v.toLocaleLowerCase("es").includes(q));
}

/** Payments grouped by day, newest day first, each with its subtotal. */
export function groupByDay(rows: PaymentRow[]) {
  const map = new Map<string, PaymentRow[]>();
  for (const r of [...rows].sort((a, b) => b.paid_on.localeCompare(a.paid_on) || b.created_at.localeCompare(a.created_at))) {
    const list = map.get(r.paid_on) ?? [];
    list.push(r);
    map.set(r.paid_on, list);
  }
  return [...map].map(([day, items]) => ({ day, items, total: Math.round(items.reduce((a, r) => a + r.amount * 100, 0)) / 100 }));
}
