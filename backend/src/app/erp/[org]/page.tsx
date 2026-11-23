import Link from "next/link";
import { workspaceContext } from "@/lib/erp/context";
import { can, licenseReady, moduleAllowed, modules, sectors, visibleModules } from "@/lib/erp/access";
import { limaDate } from "@/lib/erp/receipts";
import { attentionList, hourLabel, hourlyRhythm, monthChange, topProducts, OPEN_HOURS } from "@/lib/erp/dashboard";
import LiveRefresh from "@/components/erp/LiveRefresh";

const liveHome = ["invoices", "products", "cash_movements", "credit_ledger"] as const;
const addDays = (d: string, n: number) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
type Summary = { sales_total?: number | string; sales_count?: number } | null;

/** Home: how the store is doing today and what needs attention, from real data and only what the person may see. */
export default async function Dashboard({ params }: { params: Promise<{ org: string }> }) {
  const { org } = await params;
  const c = await workspaceContext(org);
  const sector = c.sector ? sectors[c.sector] : null;
  const available = visibleModules(c.license, c.access, c.sector);
  const base = `/erp/${org}`;
  const cur = c.organization.currency || "PEN";
  const money = (v: number) => new Intl.NumberFormat("es-PE", { style: "currency", currency: cur }).format(v);
  const allowed = (id: string) => moduleAllowed(modules.find(m => m.id === id)!, c.license, c.access, c.sector);

  if (!licenseReady(c.license)) return <>
    <section className="fv-heading"><h1>{sector?.title ?? "Tu empresa, en un mismo lugar"}</h1><p>{sector?.detail}</p></section>
    <section className="fv-empty"><h2>Verifica el acceso de tu empresa</h2><p>{c.license.message || "La licencia no permite operar en este momento. Consulta con el administrador de tu empresa."}</p>{available.some(m => m.id === "plan") && <Link className="fv-button" href={`${base}/plan`}>Consultar mi plan</Link>}</section>
  </>;

  const today = limaDate(new Date());
  const tomorrow = addDays(today, 1);
  const monthStart = `${today.slice(0, 7)}-01`;
  const prevStart = `${addDays(monthStart, -1).slice(0, 7)}-01`;
  const prevSameDay = addDays(prevStart, Math.min(Number(today.slice(8, 10)), new Date(Date.UTC(Number(prevStart.slice(0, 4)), Number(prevStart.slice(5, 7)), 0)).getUTCDate()));
  const finance = can(c.access, "finance") && allowed("comprobantes");
  const rpc = (from: string, to: string) => c.db.rpc("sales_summary", { p_org: org, p_from: from, p_to: to, p_currency: cur });
  const none = Promise.resolve({ data: null, error: null });

  const [dayS, monthS, prevS, daySales, monthItems, stock, balances, sunat, payables, opening, closing] = await Promise.all([
    finance ? rpc(today, tomorrow) : none,
    finance ? rpc(monthStart, tomorrow) : none,
    finance ? rpc(prevStart, prevSameDay) : none,
    finance ? c.db.from("invoices").select("created_at,amt_total").eq("org_id", org).eq("issue_date", today).neq("status", "draft").is("voided_at", null).limit(2000) : none,
    finance ? c.db.from("invoice_items").select("description,quantity,unit_price,invoice:invoices!inner(org_id,issue_date,status,voided_at)").eq("invoice.org_id", org).gte("invoice.issue_date", monthStart).neq("invoice.status", "draft").is("invoice.voided_at", null).limit(3000) : none,
    allowed("inventario") ? c.db.from("products").select("name,stock,reorder_point").eq("org_id", org).eq("active", true).not("reorder_point", "is", null).not("stock", "is", null).limit(2000) : none,
    allowed("clientes") ? c.db.rpc("credit_balances", { p_org: org }) : none,
    allowed("comprobantes") ? c.db.from("fiscal_documents").select("invoice_id", { count: "exact", head: true }).eq("org_id", org).in("status", ["rejected", "error"]) : none,
    allowed("compras") && c.access.is_admin ? c.db.from("retail_receipts").select("total_cents,paid:retail_purchase_settlements(id)").eq("org_id", org).eq("payment_method", "pendiente").gt("total_cents", 0).limit(500) : none,
    allowed("caja") ? c.db.from("cash_movements").select("id", { count: "exact", head: true }).eq("org_id", org).eq("day", today).eq("kind", "apertura") : none,
    allowed("caja") ? c.db.from("day_closings").select("id").eq("org_id", org).eq("day", today).maybeSingle() : none,
  ]);

  const day = (dayS.data ?? null) as Summary;
  const month = (monthS.data ?? null) as Summary;
  const prev = (prevS.data ?? null) as Summary;
  const dayTotal = Number(day?.sales_total ?? 0), dayCount = Number(day?.sales_count ?? 0);
  const monthTotal = Number(month?.sales_total ?? 0), monthCount = Number(month?.sales_count ?? 0);
  const change = monthChange(monthTotal, Number(prev?.sales_total ?? 0));
  const rhythm = hourlyRhythm((daySales.data ?? []) as { created_at: string; amt_total: number }[]);
  const nowHour = Number(new Intl.DateTimeFormat("en-US", { hour: "numeric", hourCycle: "h23", timeZone: "America/Lima" }).format(new Date()));
  const top = topProducts((monthItems.data ?? []) as { description: string; quantity: number; unit_price: number }[]);
  const low = ((stock.data ?? []) as { name: string; stock: number; reorder_point: number }[]).filter(p => Number(p.stock) <= Number(p.reorder_point)).sort((a, b) => Number(a.stock) - Number(b.stock));
  const owed = ((balances.data ?? []) as { balance: number; credit_limit: number | null; oldest_due: string | null }[])
    .filter(b => Number(b.balance) > 0 && ((b.oldest_due && b.oldest_due < today) || (b.credit_limit && Number(b.balance) > Number(b.credit_limit))));
  const pend = ((payables.data ?? []) as { total_cents: number; paid: unknown[] | null }[]).filter(p => !(p.paid ?? []).length);
  const till = !allowed("caja") ? null : closing.data ? "cerrada" : (opening as { count?: number | null }).count ? "abierta" : "sin_apertura";
  const todo = attentionList({
    base, lowStock: allowed("inventario") ? low : null,
    overdueFiado: owed.length ? { count: owed.length, amount: money(owed.reduce((a, b) => a + Number(b.balance), 0)) } : null,
    sunatProblems: (sunat as { count?: number | null }).count ?? null,
    payables: pend.length ? { count: pend.length, amount: money(pend.reduce((a, p) => a + Number(p.total_cents), 0) / 100) } : null,
    till, afterHours: nowHour >= 21,
  });
  const dateLine = new Intl.DateTimeFormat("es-PE", { weekday: "long", day: "numeric", month: "long", timeZone: "America/Lima" }).format(new Date());
  const monthName = new Intl.DateTimeFormat("es-PE", { month: "long", timeZone: "UTC" }).format(new Date(`${monthStart}T12:00:00Z`)).toLocaleLowerCase("es");
  const shortcuts = available.filter(m => !["plan", "configuracion", "equipo"].includes(m.id)).slice(0, 6);

  return <>
    <section className="fv-home">
      <div className="fv-home-top"><p className="fv-home-date">{dateLine} en {c.organization.name}</p><LiveRefresh org={org} tables={liveHome} /></div>
      {finance ? <>
        <h1 className="fv-home-title">Hoy llevas <span>{money(dayTotal)}</span> en {dayCount === 1 ? "una venta" : `${dayCount} ventas`}.</h1>
        <p className="fv-home-sub">
          En {monthName} vas {money(monthTotal)}{monthCount ? `, con un ticket promedio de ${money(monthTotal / monthCount)}` : ""}.
          {change !== null && ` Son ${Math.abs(change)} % ${change >= 0 ? "más" : "menos"} que en los mismos días del mes pasado.`}
        </p>
        <figure className="fv-rhythm" aria-label={`Ventas por hora de hoy${rhythm.peak !== null ? `; la hora con más ventas fue ${hourLabel(rhythm.peak)}` : ""}`}>
          <div className="fv-rhythm-bars">
            {rhythm.rows.map(r => <span key={r.hour} className={`${r.hour === nowHour ? "is-now" : ""}${r.hour === rhythm.peak ? " is-peak" : ""}`} style={{ "--h": r.height } as React.CSSProperties} title={`${hourLabel(r.hour)}: ${money(r.total)} en ${r.count} ${r.count === 1 ? "venta" : "ventas"}`} />)}
          </div>
          <div className="fv-rhythm-axis" aria-hidden="true">{OPEN_HOURS.filter(h => h % 3 === 0).map(h => <span key={h} style={{ "--col": h - 5 } as React.CSSProperties}>{hourLabel(h)}</span>)}</div>
          <figcaption>{rhythm.peak !== null ? `Tu hora fuerte de hoy: ${hourLabel(rhythm.peak)}` : "Aún no hay ventas hoy: las barras se llenan con cada venta, también las del móvil."}</figcaption>
        </figure>
      </> : <>
        <h1 className="fv-home-title">{sector?.title ?? "Tu jornada, en orden"}</h1>
        <p className="fv-home-sub">{sector?.detail ?? "Lo que puedes hacer hoy según tus permisos."}</p>
      </>}
    </section>

    <div className="fv-home-grid">
      <section className="fv-home-card">
        <h2>Para resolver hoy</h2>
        {todo.length ? <ul className="fv-todo">{todo.map(t => <li key={t.id} className={`is-${t.tone}`}><p>{t.text}</p><Link href={t.href}>{t.action}</Link></li>)}</ul>
          : <p className="fv-muted">Todo en orden: sin stock bajo, fiados vencidos ni comprobantes con problemas.</p>}
      </section>
      {finance ? <section className="fv-home-card">
        <h2>Lo que más se vende en {monthName}</h2>
        {top.length ? <ol className="fv-top">{top.map(t => <li key={t.name}><span>{t.name}</span><small>{Number.isInteger(t.units) ? t.units : t.units.toFixed(2)} u.</small><strong>{money(t.revenue)}</strong></li>)}</ol>
          : <p className="fv-muted">Cuando emitas ventas este mes verás aquí tus productos estrella.</p>}
      </section> : <section className="fv-home-card">
        <h2>Ir a</h2>
        <ul className="fv-shortcuts">{shortcuts.map(m => <li key={m.id}><Link href={`${base}/${m.id}`}>{m.title}</Link></li>)}</ul>
      </section>}
    </div>
  </>;
}
