/** Collections, credit, client segments and real profit for the web (ports of app finance.dart, growth.dart and credit.dart). Pure. */

const r2 = (n: number) => Math.round(n * 100) / 100;
export const addDaysIso = (d: string, n: number) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
export const daysBetween = (a: string, b: string) => Math.round((Date.parse(`${b}T12:00:00Z`) - Date.parse(`${a}T12:00:00Z`)) / 86_400_000);
export const clientKey = (name: string) => name.trim().toLowerCase();

// ── Cuentas por cobrar ──
export type Receivable = { id: string; number: string; client: string; client_id: string | null; phone: string | null; email: string | null; issue_date: string; due_date: string | null; currency: string; total: number; paid: number; balance: number; last_reminder: string | null };

/** Only issued, unpaid, not voided, not rejected by SUNAT and not credit notes, with something left to pay (app InvoiceRecord.receivable). */
export function isReceivable(i: { status: string; voided: boolean; fiscal_status: string | null; doc_kind: string | null; balance: number }): boolean {
  return i.status !== "draft" && i.status !== "paid" && i.fiscal_status !== "rejected" && !i.voided && i.doc_kind !== "nota_credito" && i.balance > 0.004;
}

export type Aging = { current: number; d1_30: number; d31_60: number; d60: number; total: number; overdue: number };
export function aging(rows: Receivable[], today: string): Aging {
  const a: Aging = { current: 0, d1_30: 0, d31_60: 0, d60: 0, total: 0, overdue: 0 };
  for (const r of rows) {
    a.total += r.balance;
    const late = r.due_date ? daysBetween(r.due_date, today) : 0;
    if (late <= 0) a.current += r.balance;
    else { a.overdue += r.balance; if (late <= 30) a.d1_30 += r.balance; else if (late <= 60) a.d31_60 += r.balance; else a.d60 += r.balance; }
  }
  return { current: r2(a.current), d1_30: r2(a.d1_30), d31_60: r2(a.d31_60), d60: r2(a.d60), total: r2(a.total), overdue: r2(a.overdue) };
}

// ── Puntaje de pago (finance.dart scoreClient) ──
export type PayStats = { key: string; settled: number; avg_days_to_pay: number | null; avg_days_late: number | null; max_days_late: number; overdue_balance: number };
export type Score = { score: number; grade: "A" | "B" | "C" | "D" | "?"; label: string; advice: string; probability: number };

export function scoreClient(s: PayStats | undefined): Score {
  if (!s || (s.settled < 2 && s.overdue_balance <= 0.004 && s.max_days_late === 0)) return { score: 70, grade: "?", label: "Cliente nuevo", advice: "Aún no hay historial suficiente. En montos altos, pide un adelanto.", probability: 0.75 };
  const late = s.avg_days_late ?? 0;
  let score = 100 - Math.min(50, late * 2.5);
  if (s.overdue_balance > 0.004) score -= 20;
  score -= s.max_days_late > 30 ? 15 : s.max_days_late > 15 ? 8 : 0;
  const v = Math.round(Math.min(100, Math.max(0, score)));
  const lateText = late >= 1 ? `Paga en promedio ${Math.round(late)} días después del vencimiento. ` : "";
  if (v >= 85) return { score: v, grade: "A", label: "Paga puntual", advice: `${lateText}Puedes darle crédito con confianza.`, probability: 0.95 };
  if (v >= 65) return { score: v, grade: "B", label: "A veces se demora", advice: `${lateText}Plazo corto (7–15 días) y recordatorio el día del vencimiento.`, probability: 0.85 };
  if (v >= 40) return { score: v, grade: "C", label: "Suele pagar tarde", advice: `${lateText}Pide 50 % de adelanto o acorta el plazo.`, probability: 0.65 };
  return { score: v, grade: "D", label: "Riesgo alto", advice: `${lateText}Mejor al contado hasta que se ponga al día.`, probability: 0.4 };
}

export function expectedPayDate(inv: { due_date: string | null; issue_date: string }, s: PayStats | undefined, today: string): string {
  const d = inv.due_date ? addDaysIso(inv.due_date, Math.round(s?.avg_days_late ?? 0)) : addDaysIso(inv.issue_date, Math.round(s?.avg_days_to_pay ?? 7));
  return d < today ? addDaysIso(today, 7) : d;
}

export type ForecastWeek = { start: string; inflow: number; outflow: number; cumulative: number };
/** Weekly cash projection: expected collections × probability in, spending pace out (finance.dart forecastCash). */
export function forecastCash(receivables: Receivable[], stats: Map<string, PayStats>, dailyExpense: number, today: string, weeks = 5): { weeks: ForecastWeek[]; warning: string | null } {
  const inflow = Array<number>(weeks).fill(0);
  for (const inv of receivables) {
    const s = stats.get(clientKey(inv.client));
    const k = Math.floor(daysBetween(today, expectedPayDate(inv, s, today)) / 7);
    if (k < 0 || k >= weeks) continue;
    inflow[k] += inv.balance * scoreClient(s).probability;
  }
  const out: ForecastWeek[] = [];
  let cum = 0, warning: string | null = null;
  for (let k = 0; k < weeks; k++) {
    const o = r2(dailyExpense * 7), i = r2(inflow[k]);
    cum = r2(cum + i - o);
    const start = addDaysIso(today, k * 7);
    out.push({ start, inflow: i, outflow: o, cumulative: cum });
    if (!warning && cum < 0) warning = `La semana del ${start.slice(8, 10)}/${start.slice(5, 7)} tus gastos superarían lo que esperas cobrar. Adelanta cobros o pospone compras.`;
  }
  return { weeks: out, warning };
}

/** WhatsApp reminder text for an invoice (friendly, never pushy). */
export function reminderText(r: Receivable, business: string, today: string, link: string | null): string {
  const name = r.client.trim().split(/\s+/)[0] || "";
  const money = `${r.currency === "USD" ? "US$" : "S/"} ${r.balance.toFixed(2)}`;
  const late = r.due_date ? daysBetween(r.due_date, today) : 0;
  const when = !r.due_date ? "" : late > 0 ? ` que venció el ${r.due_date.slice(8, 10)}/${r.due_date.slice(5, 7)}` : late === 0 ? " que vence hoy" : ` que vence el ${r.due_date.slice(8, 10)}/${r.due_date.slice(5, 7)}`;
  return `Hola${name ? ` ${name}` : ""}, te saluda ${business || "tu proveedor"}. Te recordamos el comprobante ${r.number} por ${money}${when}.${link ? ` Puedes pagarlo aquí: ${link}` : ""} ¡Gracias!`;
}

// ── Crédito por cliente (credit.dart) ──
export type CreditRow = { client_id: string; name: string; limit: number; used: number; left: number; level: "none" | "ok" | "near" | "over" };
export function creditLevel(limit: number | null, used: number): CreditRow["level"] {
  const l = limit ?? 0;
  if (l <= 0) return "none";
  if (used > l + 0.004) return "over";
  if (used >= l * 0.8) return "near";
  return "ok";
}

// ── Clientes 360 (growth.dart segmentClients) ──
export type Activity = { key: string; name: string; purchases: number; total: number; last_purchase: string; avg_gap: number | null; days_since: number };
export type Segment = "vip" | "loyal" | "atRisk" | "lost" | "newcomer" | "occasional";
export const segmentLabel: Record<Segment, string> = { vip: "VIP", loyal: "Fiel", atRisk: "Se está yendo", lost: "Perdido", newcomer: "Nuevo", occasional: "Ocasional" };
export type Insight = Activity & { segment: Segment; reason: string; next: string | null; avg_ticket: number; at_risk_value: number };

export function segmentClients(list: Activity[]): Insight[] {
  if (!list.length) return [];
  const sorted = [...list].sort((a, b) => b.total - a.total);
  const vip = new Set(sorted.slice(0, Math.max(1, Math.ceil(sorted.length * 0.2))).map(c => c.key));
  return sorted.map(c => {
    const usual = c.avg_gap == null ? null : Math.max(c.avg_gap, 7);
    const next = usual == null || c.last_purchase.length < 10 ? null : addDaysIso(c.last_purchase, Math.round(usual));
    let segment: Segment, reason: string;
    if (c.purchases >= 2 && usual != null && c.days_since > Math.max(90, usual * 3)) { segment = "lost"; reason = `Compraba cada ${Math.round(usual)} días y no vuelve hace ${c.days_since}.`; }
    else if (c.purchases >= 2 && usual != null && c.days_since > Math.max(30, usual * 1.8)) { segment = "atRisk"; reason = `Suele comprar cada ${Math.round(usual)} días; ya van ${c.days_since}.`; }
    else if (vip.has(c.key) && c.purchases >= 2) { segment = "vip"; reason = `De tus mejores clientes: ${c.purchases} compras.`; }
    else if (c.purchases >= 3) { segment = "loyal"; reason = `Compra con regularidad${usual == null ? "" : ` (cada ${Math.round(usual)} días)`}.`; }
    else if (c.purchases === 1 && c.days_since <= 45) { segment = "newcomer"; reason = `Primera compra hace ${c.days_since} días: invítalo a volver.`; }
    else { segment = "occasional"; reason = c.purchases === 1 ? `Compró una vez hace ${c.days_since} días.` : "Compra de vez en cuando."; }
    const avg = c.purchases ? r2(c.total / c.purchases) : 0;
    return { ...c, segment, reason, next, avg_ticket: avg, at_risk_value: segment === "atRisk" || segment === "lost" ? avg : 0 };
  });
}

export function clientMessage(i: Pick<Insight, "name" | "segment">, business: string): string {
  const name = i.name.trim().split(/\s+/)[0] ?? "";
  const biz = business.trim() || "nosotros";
  if (i.segment === "atRisk" || i.segment === "lost") return `Hola ${name}, ¡te extrañamos en ${biz}! Tenemos novedades y un precio especial para ti esta semana. ¿Te preparo tu pedido de siempre?`;
  if (i.segment === "vip") return `Hola ${name}, gracias por tu confianza en ${biz}. Como cliente preferente, te reservamos prioridad y una atención especial. ¿Necesitas algo esta semana?`;
  if (i.segment === "newcomer") return `Hola ${name}, gracias por tu primera compra en ${biz}. ¿Todo bien con tu pedido? Cuando necesites algo más, aquí estamos.`;
  return `Hola ${name}, te saluda ${biz}. ¿Te puedo ayudar con algo esta semana?`;
}

// ── Ganancia real (finance.dart ProfitSummary) ──
export type Profit = { sales: number; salesTax: number; expenses: number; expenseTax: number; cashIn: number; cashOut: number; count: number; profit: number; margin: number; netCash: number; igv: number };
export function profitOf(p: { sales: number; salesTax: number; expenses: { total: number; tax: number }[]; cashIn: number; count: number }): Profit {
  const exp = p.expenses.reduce((s, e) => s + (e.total - e.tax), 0), expTax = p.expenses.reduce((s, e) => s + e.tax, 0), out = p.expenses.reduce((s, e) => s + e.total, 0);
  const sales = r2(p.sales), profit = r2(sales - exp);
  return { sales, salesTax: r2(p.salesTax), expenses: r2(exp), expenseTax: r2(expTax), cashIn: r2(p.cashIn), cashOut: r2(out), count: p.count,
    profit, margin: sales <= 0 ? 0 : profit / sales, netCash: r2(p.cashIn - out), igv: Math.max(0, r2(p.salesTax - expTax)) };
}

/** "+12 %" against the previous month, or null when there is nothing to compare. */
export function deltaText(now: number, before: number): string | null {
  if (before <= 0) return null;
  const pct = Math.round(((now - before) / before) * 100);
  return `${pct >= 0 ? "+" : ""}${pct} %`;
}
