import type React from "react";
import Link from "next/link";
import type { workspaceContext } from "@/lib/erp/context";
import { money } from "@/lib/schemas";
import { limaDate } from "@/lib/erp/receipts";
import { waPhone } from "@/lib/erp/clients";
import LiveRefresh from "@/components/erp/LiveRefresh";
import { ClaimActions, CreditLimit, PayForm, RemindButton } from "@/components/erp/MoneyBoards";
import { ScanExpense } from "@/components/erp/OwnerBoards";
import { AgentBoard, OwnerPinForm, type AgentTask } from "@/components/erp/OwnerTools";
import { ApiBoard, type ApiKey, type Hook } from "@/components/erp/ApiBoard";
import {
  addDaysIso, aging, clientKey, clientMessage, creditLevel, daysBetween, deltaText, forecastCash, isReceivable, profitOf, scoreClient, segmentClients, segmentLabel,
  type Activity, type PayStats, type Receivable, type Segment,
} from "@/lib/erp/insights";

type Ctx = Awaited<ReturnType<typeof workspaceContext>>;
type Search = { mes?: string; seg?: string };
const failed = (what: string) => <div className="fv-empty" role="alert"><h2>No pudimos cargar {what}</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>;
const heading = (eyebrow: string, title: string, text: string, org: string, live?: readonly string[]) =>
  <section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{eyebrow}</p>{live && <LiveRefresh org={org} tables={live} />}</div><h1>{title}</h1><p>{text}</p></section>;
const tone = (t: string) => ({ "--tone": t }) as React.CSSProperties;
const one = <T,>(v: T | T[] | null | undefined): T | null => (Array.isArray(v) ? v[0] : v) ?? null;
const n = (v: unknown) => (v == null || v === "" ? 0 : Number(v) || 0);
const liveCollect = ["invoices", "payments", "payment_claims"] as const;
const dm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

/** Receivables with balance, client and last reminder (same rule as the mobile listReceivables). */
async function loadReceivables(c: Ctx, org: string) {
  const res = await c.db.from("invoices")
    .select("id,number,issue_date,due_date,status,currency,doc_kind,voided_at,amt_total,client_id,client:clients(name,phone,email),fiscal:fiscal_documents(status),payments(amount)")
    .eq("org_id", org).eq("status", "sent").order("due_date", { ascending: true, nullsFirst: false }).limit(1000);
  type Raw = { id: string; number: string | null; issue_date: string; due_date: string | null; status: string; currency: string; doc_kind: string | null; voided_at: string | null; amt_total: number | string | null; client_id: string | null;
    client: unknown; fiscal: unknown; payments: { amount: number | string }[] | null };
  const rows: Receivable[] = [];
  for (const i of (res.data ?? []) as unknown as Raw[]) {
    const cl = one(i.client as { name: string; phone: string | null; email: string | null } | null);
    const fs = one(i.fiscal as { status: string | null } | null);
    const paid = (i.payments ?? []).reduce((s, p) => s + n(p.amount), 0);
    const total = n(i.amt_total);
    const balance = Math.max(0, Math.round((total - paid) * 100) / 100);
    if (!isReceivable({ status: i.status, voided: !!i.voided_at, fiscal_status: fs?.status ?? null, doc_kind: i.doc_kind, balance })) continue;
    rows.push({ id: i.id, number: i.number ?? "", client: cl?.name ?? "Cliente varios", client_id: i.client_id, phone: cl?.phone ?? null, email: cl?.email ?? null, issue_date: i.issue_date, due_date: i.due_date,
      currency: i.currency || "PEN", total, paid: Math.round(paid * 100) / 100, balance, last_reminder: null });
  }
  return { rows, error: res.error };
}

async function loadStats(c: Ctx, org: string) {
  const { data } = await c.db.rpc("client_payment_stats", { p_org: org });
  return new Map(((data ?? []) as Record<string, unknown>[]).map(r => [String(r.client_key), { key: String(r.client_key), settled: n(r.settled), avg_days_to_pay: r.avg_days_to_pay == null ? null : n(r.avg_days_to_pay),
    avg_days_late: r.avg_days_late == null ? null : n(r.avg_days_late), max_days_late: n(r.max_days_late), overdue_balance: n(r.overdue_balance) } satisfies PayStats] as const));
}

/** Web modules added in v3.10: collections, credit, client analysis and real profit (same data as the mobile app). */
export async function renderExtra3(id: string, c: Ctx, org: string, title: string, search: Search) {
  const cur = c.organization.currency || "PEN";
  const fmt = (v: number, cc = cur) => money(v, cc);
  const name = c.organization.name;
  const today = limaDate(new Date());

  if (id === "cobranza") {
    const [{ rows, error }, stats, claims] = await Promise.all([
      loadReceivables(c, org), loadStats(c, org),
      c.db.from("payment_claims").select("id,amount,method,operation_code,payer_name,created_at,invoice:invoices(number,currency,client:clients(name))").eq("org_id", org).eq("status", "pending").order("created_at", { ascending: false }).limit(100),
    ]);
    if (error) return <>{heading(`COBRANZA / ${name}`, title, "", org)}{failed("lo que te deben")}</>;
    const ids = rows.map(r => r.id).slice(0, 300);
    const rem = ids.length ? await c.db.from("reminder_log").select("invoice_id,sent_at").in("invoice_id", ids).order("sent_at", { ascending: false }) : { data: [] };
    const last = new Map<string, string>();
    for (const r of (rem.data ?? []) as { invoice_id: string; sent_at: string }[]) if (!last.has(r.invoice_id)) last.set(r.invoice_id, r.sent_at);
    const mine = rows.filter(r => r.currency === cur).map(r => ({ ...r, last_reminder: last.get(r.id) ?? null }));
    const late = (r: Receivable) => (r.due_date ? daysBetween(r.due_date, today) : 0);
    mine.sort((a, b) => late(b) - late(a) || b.balance - a.balance);
    const ag = aging(mine, today);
    type Claim = { id: string; amount: number | string; method: string; operation_code: string | null; payer_name: string | null; created_at: string; invoice: unknown };
    const cl = (claims.data ?? []) as unknown as Claim[];
    return <>{heading(`COBRANZA / ${name}`, title, "Quién te debe, desde cuándo y qué tan buen pagador es. Recuérdale por WhatsApp con su enlace de pago y registra lo que te paguen.", org, liveCollect)}
      <section className="fv-board">
        <div className="fv-kpis fv-kpis-4">
          <div style={tone("#3ee6b0")}><span>Por cobrar</span><strong>{fmt(ag.total)}</strong><small>{mine.length} {mine.length === 1 ? "comprobante" : "comprobantes"}</small></div>
          <div style={tone("#e0457b")}><span>Vencido</span><strong>{fmt(ag.overdue)}</strong><small>{ag.total ? `${Math.round((ag.overdue / ag.total) * 100)} % de lo que te deben` : "nada vencido"}</small></div>
          <div style={tone("#ffb35c")}><span>1 a 30 días</span><strong>{fmt(ag.d1_30)}</strong><small>31–60 días: {fmt(ag.d31_60)}</small></div>
          <div style={tone("#a98bff")}><span>Más de 60 días</span><strong>{fmt(ag.d60)}</strong><small>al día: {fmt(ag.current)}</small></div>
        </div>
        {cl.length > 0 && <section className="fv-create fv-cash-card"><h3>Te avisaron que ya pagaron ({cl.length})</h3>
          <ul className="fv-lines fv-claims">{cl.map(x => { const inv = one(x.invoice as { number: string; currency: string; client: unknown } | null); const cn = one(inv?.client as { name: string } | null);
            return <li key={x.id}><span><strong>{fmt(n(x.amount), inv?.currency || cur)}</strong> por {x.method}{x.operation_code ? ` · operación ${x.operation_code}` : ""}<small>{x.payer_name || cn?.name || "Cliente"} · {inv?.number ?? ""}</small></span><ClaimActions org={org} id={x.id} /></li>; })}</ul>
        </section>}
        {!mine.length ? <div className="fv-empty"><h2>Nadie te debe</h2><p>Cuando emitas comprobantes al crédito aparecerán aquí con su vencimiento.</p></div>
          : <ul className="fv-collect">{mine.map(r => {
            const d = late(r); const sc = scoreClient(stats.get(clientKey(r.client))); const phone = waPhone(r.phone);
            return <li key={r.id} className={d > 0 ? "is-late" : ""}>
              <div className="fv-collect-main">
                <strong>{r.client}</strong>
                <small>{r.number} · emitido {dm(r.issue_date)}{r.due_date ? (d > 0 ? ` · venció hace ${d} ${d === 1 ? "día" : "días"}` : d === 0 ? " · vence hoy" : ` · vence el ${dm(r.due_date)}`) : " · sin vencimiento"}</small>
                <small><span className={`fv-grade g-${sc.grade === "?" ? "n" : sc.grade.toLowerCase()}`} title={sc.advice}>{sc.grade}</span> {sc.label}{r.last_reminder ? ` · recordado el ${dm(limaDate(new Date(r.last_reminder)))}` : ""}</small>
              </div>
              <div className="fv-collect-amount"><b>{fmt(r.balance, r.currency)}</b>{r.paid > 0 && <small>de {fmt(r.total, r.currency)}</small>}</div>
              <div className="fv-actions">{phone ? <RemindButton org={org} row={r} business={name} phone={phone} today={today} /> : <small className="fv-muted">Sin celular: agrégalo en Clientes</small>}<PayForm org={org} row={r} today={today} /></div>
            </li>;
          })}</ul>}
      </section></>;
  }

  if (id === "credito") {
    const [clients, rec, bal] = await Promise.all([
      c.db.from("clients").select("id,name,credit_limit").eq("org_id", org).order("name").limit(2000),
      loadReceivables(c, org),
      c.db.rpc("credit_balances", { p_org: org }),
    ]);
    if (clients.error) return <>{heading(`CRÉDITO / ${name}`, title, "", org)}{failed("los clientes")}</>;
    const usedInv = new Map<string, number>();
    for (const r of rec.rows) if (r.currency === cur) { const k = r.client_id ?? `n:${clientKey(r.client)}`; usedInv.set(k, (usedInv.get(k) ?? 0) + r.balance); }
    const fiado = new Map(((bal.data ?? []) as { client_id: string; balance: number | string }[]).map(b => [b.client_id, Math.max(0, n(b.balance))] as const));
    const rows = ((clients.data ?? []) as { id: string; name: string; credit_limit: number | string | null }[]).map(cl => {
      const inv = (usedInv.get(cl.id) ?? 0) + (usedInv.get(`n:${clientKey(cl.name)}`) ?? 0), fi = fiado.get(cl.id) ?? 0, used = Math.round((inv + fi) * 100) / 100, limit = n(cl.credit_limit);
      return { id: cl.id, name: cl.name, limit, used, inv, fi, left: Math.round((limit - used) * 100) / 100, level: creditLevel(limit, used) };
    }).filter(r => r.limit > 0 || r.used > 0.004).sort((a, b) => ({ over: 0, near: 1, ok: 2, none: 3 }[a.level] - { over: 0, near: 1, ok: 2, none: 3 }[b.level]) || b.used - a.used);
    const over = rows.filter(r => r.level === "over");
    return <>{heading(`CRÉDITO / ${name}`, title, "Cuánto le fías a cada cliente, cuánto ya usó y quién se pasó. Es solo un aviso: tú decides si le vendes igual.", org, liveCollect)}
      <section className="fv-board">
        <div className="fv-kpis">
          <div style={tone("#3ee6b0")}><span>Crédito usado</span><strong>{fmt(rows.reduce((s, r) => s + r.used, 0))}</strong><small>{rows.length} clientes con crédito</small></div>
          <div style={tone("#e0457b")}><span>Se pasaron del límite</span><strong>{over.length}</strong><small>{over.length ? `por ${fmt(over.reduce((s, r) => s - r.left, 0))} en total` : "nadie"}</small></div>
          <div style={tone("#ffb35c")}><span>Cerca del límite</span><strong>{rows.filter(r => r.level === "near").length}</strong><small>usan 80 % o más</small></div>
        </div>
        {!rows.length ? <div className="fv-empty"><h2>Nadie tiene crédito todavía</h2><p>Fija un límite aquí o en la ficha de cada cliente (Clientes) cuando le vendas al crédito o al fiado.</p></div>
          : <ul className="fv-credit">{rows.map(r => <li key={r.id} className={`is-${r.level}`}>
            <div><strong>{r.name}</strong>
              <small>{r.limit > 0 ? `Debe ${fmt(r.used)} de ${fmt(r.limit)} · ${r.left >= 0 ? `le queda ${fmt(r.left)}` : `pasó por ${fmt(-r.left)}`}` : `Debe ${fmt(r.used)} · sin límite fijado`}{r.fi > 0 && r.inv > 0 ? ` (fiado ${fmt(r.fi)}, comprobantes ${fmt(r.inv)})` : ""}</small>
              {r.limit > 0 && <span className="fv-bar"><i style={{ width: `${Math.min(100, (r.used / r.limit) * 100)}%` }} /></span>}
            </div>
            <CreditLimit org={org} clientId={r.id} limit={r.limit} />
          </li>)}</ul>}
      </section></>;
  }

  if (id === "clientes360") {
    const [act, cls] = await Promise.all([c.db.rpc("client_activity", { p_org: org }), c.db.from("clients").select("name,phone").eq("org_id", org).limit(3000)]);
    if (act.error) return <>{heading(`CLIENTES / ${name}`, title, "", org)}{failed("el historial de tus clientes")}</>;
    const list: Activity[] = ((act.data ?? []) as Record<string, unknown>[]).map(r => ({ key: String(r.client_key ?? ""), name: String(r.client_name ?? ""), purchases: n(r.purchases), total: n(r.total),
      last_purchase: String(r.last_purchase ?? ""), avg_gap: r.avg_gap == null ? null : n(r.avg_gap), days_since: n(r.days_since) }));
    const all = segmentClients(list);
    const phones = new Map(((cls.data ?? []) as { name: string; phone: string | null }[]).map(x => [clientKey(x.name), waPhone(x.phone)] as const));
    const order: Segment[] = ["atRisk", "lost", "vip", "loyal", "newcomer", "occasional"];
    const valid = order.includes(search.seg as Segment) ? search.seg as Segment : null;
    const seg = search.seg === "todos" ? null : valid ?? (all.some(i => i.segment === "atRisk") ? "atRisk" : null);
    const total = all.reduce((s, i) => s + i.total, 0), vipTotal = all.filter(i => i.segment === "vip").reduce((s, i) => s + i.total, 0);
    const shown = all.filter(i => !seg || i.segment === seg).slice(0, 200);
    return <>{heading(`CLIENTES / ${name}`, title, "Tus mejores clientes y los que se están yendo, según su costumbre de compra. Escríbeles con un mensaje listo.", org)}
      {!all.length ? <div className="fv-empty"><h2>Aún no hay historial</h2><p>Cuando tengas ventas emitidas a clientes con nombre verás aquí a tus mejores clientes y a los que se están yendo.</p></div> : <section className="fv-board">
        <div className="fv-kpis">
          <div style={tone("#3ee6b0")}><span>Tus VIP</span><strong>{total > 0 ? `${Math.round((vipTotal / total) * 100)} %` : "—"}</strong><small>de tus ventas vienen de {all.filter(i => i.segment === "vip").length} clientes</small></div>
          <div style={tone("#e0457b")}><span>Se están yendo</span><strong>{all.filter(i => i.segment === "atRisk").length}</strong><small>{fmt(all.reduce((s, i) => s + i.at_risk_value, 0))} en riesgo por compra</small></div>
          <div style={tone("#6fb7ff")}><span>Clientes con historial</span><strong>{all.length}</strong><small>{all.filter(i => i.segment === "newcomer").length} nuevos este mes y medio</small></div>
        </div>
        <nav className="fv-chips" aria-label="Segmentos">
          <Link className="fv-chip" aria-pressed={!seg} href={`/erp/${org}/clientes360?seg=todos`}>Todos ({all.length})</Link>
          {order.map(s => <Link key={s} className="fv-chip" aria-pressed={seg === s} href={`/erp/${org}/clientes360?seg=${s}`}>{segmentLabel[s]} ({all.filter(i => i.segment === s).length})</Link>)}
        </nav>
        <ul className="fv-collect">{shown.map(i => { const ph = phones.get(i.key) ?? ""; return <li key={i.key}>
          <div className="fv-collect-main"><strong>{i.name}</strong><small><span className={`fv-seg s-${i.segment}`}>{segmentLabel[i.segment]}</span> {i.reason}</small>
            <small>{i.purchases} {i.purchases === 1 ? "compra" : "compras"} · ticket promedio {fmt(i.avg_ticket)}{i.next ? ` · debería volver ~${dm(i.next)}` : ""}</small></div>
          <div className="fv-collect-amount"><b>{fmt(i.total)}</b><small>en total</small></div>
          <div className="fv-actions">{ph ? <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/${ph}?text=${encodeURIComponent(clientMessage(i, name))}`}>Escribirle por WhatsApp</a> : <small className="fv-muted">Sin celular registrado</small>}</div>
        </li>; })}</ul>
      </section>}</>;
  }

  if (id === "negocio") {
    const cm = /^\d{4}-(0[1-9]|1[0-2])$/.test(search.mes ?? "") && (search.mes ?? "") <= today.slice(0, 7) ? search.mes! : today.slice(0, 7);
    const [y, m] = cm.split("-").map(Number);
    const key = (yy: number, mm: number) => { const d = new Date(Date.UTC(yy, mm - 1, 1)); return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`; };
    const keys = Array.from({ length: 6 }, (_, k) => key(y, m - 5 + k));
    const endOf = (k: string) => { const [yy, mm] = k.split("-").map(Number); return key(yy, mm + 1) + "-01"; };
    const from6 = `${keys[0]}-01`, monthFrom = `${cm}-01`, monthTo = endOf(cm);
    const expFrom = [from6, addDaysIso(today, -90)].sort()[0];
    const [summaries, exp, pays, rec, stats, vel] = await Promise.all([
      Promise.all(keys.map(k => c.db.rpc("sales_summary", { p_org: org, p_from: `${k}-01`, p_to: endOf(k), p_currency: cur }))),
      c.db.from("expenses").select("spent_on,category,total,tax,currency").eq("org_id", org).gte("spent_on", expFrom).lt("spent_on", [monthTo, addDaysIso(today, 1)].sort().reverse()[0]).limit(8000),
      c.db.from("payments").select("amount,invoice:invoices(currency)").eq("org_id", org).gte("paid_on", monthFrom).lt("paid_on", monthTo).limit(8000),
      loadReceivables(c, org), loadStats(c, org), c.db.rpc("product_velocity", { p_org: org, p_days: 30 }),
    ]);
    const sv = summaries.map(s => (s.data ?? {}) as { sales_base?: number | string; sales_tax?: number | string; sales_count?: number });
    if (summaries[5].error) return <>{heading(`MI NEGOCIO / ${name}`, title, "", org)}{failed("tus números del mes")}</>;
    const expenses = ((exp.data ?? []) as { spent_on: string; category: string; total: number | string; tax: number | string | null; currency: string | null }[]).filter(e => (e.currency || "PEN") === cur).map(e => ({ ...e, total: n(e.total), tax: n(e.tax) }));
    const inMonth = (k: string) => expenses.filter(e => e.spent_on.startsWith(k));
    const cashIn = ((pays.data ?? []) as { amount: number | string; invoice: unknown }[]).filter(p => (one(p.invoice as { currency: string } | null)?.currency || cur) === cur).reduce((s, p) => s + n(p.amount), 0);
    const p = profitOf({ sales: n(sv[5].sales_base), salesTax: n(sv[5].sales_tax), expenses: inMonth(cm), cashIn, count: n(sv[5].sales_count) });
    const prev = profitOf({ sales: n(sv[4].sales_base), salesTax: n(sv[4].sales_tax), expenses: inMonth(keys[4]), cashIn: 0, count: n(sv[4].sales_count) });
    const series = keys.map((k, i) => ({ k, label: months[Number(k.slice(5, 7)) - 1], sales: n(sv[i].sales_base), exp: inMonth(k).reduce((s, e) => s + e.total - e.tax, 0) }));
    const peak = Math.max(1, ...series.map(s => Math.max(s.sales, s.exp)));
    const cats = Object.entries(inMonth(cm).reduce<Record<string, number>>((a, e) => { a[e.category || "otros"] = (a[e.category || "otros"] ?? 0) + e.total; return a; }, {})).sort((a, b) => b[1] - a[1]);
    const daily = Math.round(expenses.filter(e => e.spent_on >= addDaysIso(today, -90)).reduce((s, e) => s + e.total, 0) / 90 * 100) / 100;
    const fc = forecastCash(rec.rows.filter(r => r.currency === cur), stats, daily, today);
    type V = { product_id: string; name: string; stock: number | string | null; reorder_point: number | string | null; per_day: number | string };
    const risky = ((vel.data ?? []) as V[]).map(v => { const st = v.stock == null ? null : n(v.stock), pd = n(v.per_day); const left = st == null || pd <= 0 ? null : st <= 0 ? 0 : st / pd;
      return { ...v, st, left, risk: st != null && (st <= n(v.reorder_point) || (left != null && left <= 14)) }; }).filter(v => v.risk).sort((a, b) => (a.left ?? 999) - (b.left ?? 999)).slice(0, 6);
    const prevKey = keys[4], nextKey = key(y, m + 1);
    const d = (now: number, before: number, good: boolean) => { const t = deltaText(now, before); return t ? <em className={good ? "fv-up" : "fv-down"}>{t} vs {months[Number(prevKey.slice(5, 7)) - 1]}</em> : null; };
    return <>{heading(`MI NEGOCIO / ${name}`, title, "Lo que de verdad te queda: ventas sin IGV menos gastos, lo que entró y salió de caja y lo que viene en las próximas semanas.", org)}
      <nav className="fv-month-nav" aria-label="Mes">
        <Link className="fv-button secondary" href={`/erp/${org}/negocio?mes=${prevKey}`}>‹ {months[Number(prevKey.slice(5, 7)) - 1]}</Link>
        <strong>{months[m - 1]} {y}</strong>
        {cm < today.slice(0, 7) ? <Link className="fv-button secondary" href={`/erp/${org}/negocio?mes=${nextKey}`}>{months[Number(nextKey.slice(5, 7)) - 1]} ›</Link> : <span />}
      </nav>
      <section className="fv-board">
        <div className={`fv-profit-hero${p.profit < 0 ? " is-loss" : ""}`}>
          <span>{p.profit < 0 ? "Pérdida del mes" : "Ganancia del mes"}</span>
          <strong>{fmt(p.profit)}</strong>
          <small>margen {Math.round(p.margin * 100)} % · {p.count} {p.count === 1 ? "venta" : "ventas"} · caja neta {fmt(p.netCash)}</small>
        </div>
        <div className="fv-kpis fv-kpis-4">
          <div style={tone("#3ee6b0")}><span>Ventas sin IGV</span><strong>{fmt(p.sales)}</strong><small>{d(p.sales, prev.sales, p.sales >= prev.sales)}</small></div>
          <div style={tone("#ffb35c")}><span>Gastos sin IGV</span><strong>{fmt(p.expenses)}</strong><small>{d(p.expenses, prev.expenses, p.expenses <= prev.expenses)}</small></div>
          <div style={tone("#6fb7ff")}><span>Cobrado</span><strong>{fmt(p.cashIn)}</strong><small>pagado {fmt(p.cashOut)}</small></div>
          <div style={tone("#a98bff")}><span>IGV estimado</span><strong>{fmt(p.igv)}</strong><small>ventas {fmt(p.salesTax)} − compras {fmt(p.expenseTax)}</small></div>
        </div>
        <p className="fv-caption">Aquí las ventas van sin IGV para calcular tu ganancia. Solo cuentan comprobantes emitidos (sin anulados ni borradores). Registra tus gastos en <Link className="fv-link" href={`/erp/${org}/gastos`}>Gastos</Link>.</p>
        <div className="fv-cash-grid">
          <section className="fv-create fv-cash-card"><h3>Últimos 6 meses</h3>
            <div className="fv-dual" role="img" aria-label="Ventas y gastos de los últimos 6 meses">{series.map(s => <div key={s.k} title={`${s.label}: ventas ${fmt(s.sales)} · gastos ${fmt(s.exp)}`}>
              <span className="fv-dual-bars"><i className="is-sales" style={{ height: `${(s.sales / peak) * 100}%` }} /><i className="is-exp" style={{ height: `${(s.exp / peak) * 100}%` }} /></span><small>{s.label}</small></div>)}</div>
            <p className="fv-legend"><i className="is-sales" /> Ventas <i className="is-exp" /> Gastos</p>
          </section>
          <section className="fv-create fv-cash-card"><h3>En qué se fue la plata</h3>
            {cats.length ? <ul className="fv-shares">{cats.slice(0, 7).map(([k, v]) => { const share = p.cashOut ? Math.round((v / p.cashOut) * 100) : 0; return <li key={k} style={{ "--share": `${share}%` } as React.CSSProperties}><span>{k}</span><span>{fmt(v)} · {share} %</span><i aria-hidden="true" /></li>; })}</ul>
              : <p className="fv-muted">Sin gastos registrados este mes.</p>}
          </section>
        </div>
        <section className="fv-create fv-cash-card"><h3>Proyección de caja · 5 semanas</h3>
          <p className="fv-caption">Entradas: lo que te deben, según cuándo suele pagar cada cliente. Salidas: tu ritmo de gasto de los últimos 90 días ({fmt(daily)} al día).</p>
          <ul className="fv-forecast">{fc.weeks.map(w => <li key={w.start} className={w.cumulative < 0 ? "is-bad" : ""}><span>Semana del {dm(w.start)}</span><span className="fv-up">+{fmt(w.inflow)}</span><span className="fv-down">−{fmt(w.outflow)}</span><b>{fmt(w.cumulative)}</b></li>)}</ul>
          {fc.warning && <p className="fv-note-box" role="status">{fc.warning}</p>}
        </section>
        {risky.length > 0 && <section className="fv-create fv-cash-card"><h3>Productos por reponer</h3>
          <ul className="fv-lines">{risky.map(v => <li key={v.product_id}><span>{v.name}</span><span>{v.left == null ? `quedan ${v.st}` : v.left < 1 ? "sin stock" : `se acaba en ~${Math.round(v.left)} días`}</span></li>)}</ul>
          <p className="fv-caption">Haz el pedido en <Link className="fv-link" href={`/erp/${org}/compras`}>Compras</Link>.</p>
        </section>}
      </section></>;
  }

  if (id === "escanear") {
    const recent = await c.db.from("expenses").select("id,spent_on,supplier_name,doc_number,total,tax,category").eq("org_id", org).eq("source", "scan").order("created_at", { ascending: false }).limit(10);
    type E = { id: string; spent_on: string; supplier_name: string | null; doc_number: string | null; total: number | string; tax: number | string | null; category: string };
    const rows = (recent.data ?? []) as E[];
    return <>{heading(`GASTOS / ${name}`, title, "Tómale foto a la factura o boleta de tu proveedor: la leemos y la guardas como gasto en segundos.", org)}
      <ScanExpense org={org} today={today} />
      {rows.length > 0 && <section className="fv-create" style={{ padding: 18 }}><h3>Últimos comprobantes escaneados</h3>
        <ul className="fv-lines">{rows.map(e => <li key={e.id}><span>{dm(e.spent_on)} · {e.supplier_name || "Proveedor"}{e.doc_number ? ` · ${e.doc_number}` : ""}</span><span>{fmt(n(e.total))}{n(e.tax) > 0 ? ` (IGV ${fmt(n(e.tax))})` : ""}</span></li>)}</ul>
        <p className="fv-caption">Todos tus gastos están en <Link className="fv-link" href={`/erp/${org}/gastos`}>Gastos</Link>.</p></section>}
    </>;
  }

  if (id === "pin") {
    const st = await c.db.rpc("pin_status", { p_org: org });
    const enabled = !!(st.data as { enabled?: boolean } | null)?.enabled;
    return <>{heading(`CONTROL / ${name}`, title, "Con el PIN del dueño activo, tu equipo te lo pide para anular comprobantes o borrar cobros. Así nadie lo hace a tus espaldas.", org)}
      {st.error ? failed("el estado del PIN") : <section className="fv-board">
        <div className="fv-kpis"><div style={tone(enabled ? "#3ee6b0" : "#ffb35c")}><span>PIN del dueño</span><strong>{enabled ? "Activo" : "Desactivado"}</strong><small>{enabled ? "se pide para anular y borrar cobros" : "cualquiera con permiso puede anular"}</small></div></div>
        <OwnerPinForm org={org} enabled={enabled} />
      </section>}
    </>;
  }

  if (id === "agente") {
    const res = await c.db.from("agent_tasks").select("id,title,prompt,status,plan,result,created_at").eq("org_id", org).order("created_at", { ascending: false }).limit(30);
    type T = { id: string; title: string | null; prompt: string | null; status: string; plan: { results?: Record<string, unknown>[] } | null; result: { reminders_created?: number; error?: string } | null; created_at: string };
    const tasks: AgentTask[] = ((res.data ?? []) as T[]).map(t => ({ id: t.id, title: t.title ?? "Tarea", prompt: t.prompt ?? "", status: t.status, created_at: t.created_at,
      results: Array.isArray(t.plan?.results) ? t.plan!.results! : [],
      summary: t.status === "done" ? (n(t.result?.reminders_created) ? `Listo: se programaron ${n(t.result?.reminders_created)} recordatorios de cobro.` : "Listo.") : null }));
    return <>{heading(`COPILOTO / ${name}`, title, "Encárgale una tarea al Copiloto: la prepara con tus datos y tú decides si se hace.", org, ["agent_tasks"] as const)}
      {res.error ? failed("tus tareas") : <AgentBoard org={org} tasks={tasks} />}
    </>;
  }

  if (id === "api") {
    const [keys, hooks] = await Promise.all([
      c.db.from("org_api_keys").select("id,name,prefix,scopes,created_at,last_used_at,revoked_at").eq("org_id", org).order("created_at", { ascending: false }),
      c.db.from("org_webhooks").select("id,url,events,active,last_status,secret").eq("org_id", org).order("created_at"),
    ]);
    const base = `${(process.env.NEXT_PUBLIC_SITE_URL ?? process.env.APP_URL ?? "https://factura-voz-two.vercel.app").replace(/\/$/, "")}/api/v1`;
    return <>{heading(`CONEXIONES / ${name}`, title, "Conecta tu página web o tu sistema: lee comprobantes y clientes, crea pedidos y recibe avisos al instante.", org)}
      {keys.error ? failed("tus llaves") : <ApiBoard org={org} keys={(keys.data ?? []) as ApiKey[]} hooks={((hooks.data ?? []) as Hook[]).map(h => ({ ...h, secret: h.secret ?? null }))} base={base} />}
    </>;
  }

  return null;
}
