/** Kardex of one product: purchases and sales merged into one timeline (pure, testable). */

export type KardexEntry = { at: string; kind: "compra" | "venta"; delta: number; before: number; after: number; ref: string };

type Purchase = { created_at: string; quantity_delta: number | string; stock_before: number | string; stock_after: number | string; receipt: { supplier_name: string; document_ref: string | null } | { supplier_name: string; document_ref: string | null }[] | null };
type Sale = { created_at: string; quantity_delta: number | string; stock_before: number | string; stock_after: number | string; invoice: { number: string } | { number: string }[] | null };

const one = <T,>(v: T | T[] | null): T | null => (Array.isArray(v) ? v[0] ?? null : v);

export function mergeKardex(purchases: Purchase[], sales: Sale[], limit = 30): KardexEntry[] {
  const rows: KardexEntry[] = [
    ...purchases.map(p => {
      const r = one(p.receipt);
      return { at: p.created_at, kind: "compra" as const, delta: Number(p.quantity_delta), before: Number(p.stock_before), after: Number(p.stock_after), ref: [r?.supplier_name, r?.document_ref].filter(Boolean).join(" · ") || "Compra" };
    }),
    ...sales.map(s => ({ at: s.created_at, kind: "venta" as const, delta: Number(s.quantity_delta), before: Number(s.stock_before), after: Number(s.stock_after), ref: one(s.invoice)?.number ?? "Venta" })),
  ];
  return rows.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0)).slice(0, limit);
}

/** Units in and out over the listed entries. */
export function kardexTotals(rows: KardexEntry[]) {
  let entered = 0, left = 0;
  for (const r of rows) { if (r.delta > 0) entered += r.delta; else left -= r.delta; }
  return { entered: Math.round(entered * 100) / 100, left: Math.round(left * 100) / 100 };
}
