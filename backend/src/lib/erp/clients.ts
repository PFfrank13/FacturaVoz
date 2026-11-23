/** Pure helpers for the web Clientes module (no I/O, fully testable). */

export type ClientRow = {
  id: string; name: string; tax_id: string | null; doc_type: string | null; email: string | null; phone: string | null;
  address: string | null; district: string | null; notes: string | null; credit_limit: number | string | null; created_at: string;
};
export type ClientBalance = {
  client_id: string; balance: number | string; charges: number | string; payments: number | string;
  last_move: string | null; oldest_due: string | null; credit_limit: number | string | null;
};
export type ClientActivity = {
  client_key: string; purchases: number; total: number | string; first_purchase: string | null; last_purchase: string | null;
  avg_gap: number | string | null; days_since: number | null;
};

export type ClientView = ClientRow & {
  balance: number; limit: number | null; overLimit: boolean; overdue: boolean; oldestDue: string | null;
  purchases: number; spent: number; lastPurchase: string | null; daysSince: number | null; avgGap: number | null;
};

const num = (v: unknown) => (v === null || v === undefined || v === "" ? 0 : Number(v) || 0);

/** SUNAT catalogue 06 code from the number itself: 8 digits DNI («1»), 11 digits RUC («6»). */
export function docTypeOf(taxId: string | null | undefined): "1" | "6" | null {
  const d = (taxId ?? "").replace(/\D/g, "");
  if (d.length === 8 && d === (taxId ?? "").trim()) return "1";
  if (d.length === 11 && d === (taxId ?? "").trim()) return "6";
  return null;
}

export const docLabel = (c: Pick<ClientRow, "tax_id" | "doc_type">) =>
  !c.tax_id ? "" : c.doc_type === "6" || c.tax_id.length === 11 ? "RUC" : c.doc_type === "1" || c.tax_id.length === 8 ? "DNI" : "Doc.";

/** Peruvian mobile ready for wa.me (51 + 9 digits) or "" — same rule as the mobile app. */
export function waPhone(phone: string | null | undefined): string {
  const d = (phone ?? "").replace(/\D/g, "");
  if (/^9\d{8}$/.test(d)) return `51${d}`;
  if (/^519\d{8}$/.test(d)) return d;
  return "";
}

/** Joins each client with its fiado balance (by id) and purchase history (by normalized name, as the RPC groups). */
export function mergeClients(rows: ClientRow[], balances: ClientBalance[], activity: ClientActivity[], today: string): ClientView[] {
  const byId = new Map(balances.map(b => [b.client_id, b]));
  const byName = new Map(activity.map(a => [a.client_key, a]));
  return rows.map(r => {
    const b = byId.get(r.id);
    const a = byName.get(r.name.trim().toLocaleLowerCase("es"));
    const balance = Math.round(num(b?.balance) * 100) / 100;
    const limit = r.credit_limit === null || r.credit_limit === undefined || r.credit_limit === "" ? null : num(r.credit_limit);
    const oldestDue = balance > 0 ? b?.oldest_due ?? null : null;
    return {
      ...r, balance, limit, oldestDue,
      overLimit: limit !== null && limit > 0 && balance > limit,
      overdue: !!oldestDue && oldestDue < today,
      purchases: a?.purchases ?? 0, spent: num(a?.total), lastPurchase: a?.last_purchase ?? null,
      daysSince: a?.days_since ?? null, avgGap: a?.avg_gap === null || a?.avg_gap === undefined ? null : num(a.avg_gap),
    };
  });
}

export type ClientFilter = "todos" | "con_deuda" | "vencidos" | "sin_volver";

export function matchesClient(c: ClientView, q: string, f: ClientFilter = "todos"): boolean {
  if (f === "con_deuda" && c.balance <= 0) return false;
  if (f === "vencidos" && !(c.overdue || c.overLimit)) return false;
  // A regular who usually comes back sooner than they have now: worth a message.
  if (f === "sin_volver" && !(c.purchases > 1 && c.daysSince !== null && c.avgGap !== null && c.daysSince > Math.max(14, c.avgGap * 2))) return false;
  const s = q.trim().toLocaleLowerCase("es");
  if (!s) return true;
  return [c.name, c.tax_id ?? "", c.phone ?? "", c.email ?? ""].some(v => v.toLocaleLowerCase("es").includes(s));
}

export function summarizeClients(list: ClientView[]) {
  let receivable = 0, debtors = 0, attention = 0;
  for (const c of list) {
    if (c.balance > 0) { receivable += c.balance; debtors++; }
    if (c.overdue || c.overLimit) attention++;
  }
  return { count: list.length, receivable: Math.round(receivable * 100) / 100, debtors, attention };
}
