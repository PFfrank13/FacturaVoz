import type React from "react";
import Link from "next/link";
import type { workspaceContext } from "@/lib/erp/context";
import { can, hasFeature } from "@/lib/erp/access";
import { money } from "@/lib/schemas";
import { limaDate } from "@/lib/erp/receipts";
import { estimateTaxes, type Regime } from "@/lib/taxes";
import { suggestMatches, type Receivable } from "@/lib/erp/bank";
import NewInvoice from "@/components/NewInvoice";
import LiveRefresh from "@/components/erp/LiveRefresh";
import { BankImport, BankMatch, ImportBoard, InStoreToggle, RecurringActions, RecurringForm, RecurringRun, RegimePicker, StoreForm, SurveyToggle } from "@/components/erp/GrowthBoards";

type Ctx = Awaited<ReturnType<typeof workspaceContext>>;
const addDay = (d: string) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + 1); return x.toISOString().slice(0, 10); };
const dateOnly = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
const dateTime = (iso: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));
const failed = (what: string) => <div className="fv-empty" role="alert"><h2>No pudimos cargar {what}</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>;
const heading = (eyebrow: string, title: string, text: string, org: string, live?: readonly string[]) =>
  <section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{eyebrow}</p>{live && <LiveRefresh org={org} tables={live} />}</div><h1>{title}</h1><p>{text}</p></section>;
const tone = (t: string) => ({ "--tone": t }) as React.CSSProperties;
const liveRec = ["recurring_invoices"] as const;
const liveBank = ["bank_lines", "payments"] as const;
const liveSurveys = ["surveys"] as const;

/** Web modules added in v3.9 (same tables and rules as the mobile app). Returns null for any other module. */
export async function renderExtra2(id: string, c: Ctx, org: string, title: string, mes?: string) {
  const cur = c.organization.currency || "PEN";
  const fmt = (v: number) => money(v, cur);
  const name = c.organization.name;
  const today = limaDate(new Date());
  const monthStart = `${today.slice(0, 7)}-01`;

  if (id === "impuestos") {
    const yearStart = `${today.slice(0, 4)}-01-01`;
    const [settings, month, year, exp, yearExp] = await Promise.all([
      c.db.from("org_settings").select("tax_regime").eq("org_id", org).maybeSingle(),
      c.db.rpc("sales_summary", { p_org: org, p_from: monthStart, p_to: addDay(today), p_currency: "PEN" }),
      c.db.rpc("sales_summary", { p_org: org, p_from: yearStart, p_to: addDay(today), p_currency: "PEN" }),
      c.db.from("expenses").select("total,tax,category,currency").eq("org_id", org).gte("spent_on", monthStart).limit(5000),
      c.db.from("expenses").select("total,tax,category,currency").eq("org_id", org).gte("spent_on", yearStart).eq("category", "mercaderia").limit(20000),
    ]);
    const regime = ((settings.data as { tax_regime: string | null } | null)?.tax_regime ?? null) as Regime | null;
    const m = (month.data ?? {}) as { sales_base?: number | string; sales_tax?: number | string };
    const y = (year.data ?? {}) as { sales_base?: number | string };
    type E = { total: number | string; tax: number | string | null; category: string; currency: string };
    const pen = ((exp.data ?? []) as E[]).filter(e => e.currency === "PEN");
    const expTax = pen.reduce((s, e) => s + Number(e.tax ?? 0), 0);
    const expBase = pen.reduce((s, e) => s + Number(e.total) - Number(e.tax ?? 0), 0);
    const monthBuys = pen.filter(e => e.category === "mercaderia").reduce((s, e) => s + Number(e.total), 0);
    const yearBuys = ((yearExp.data ?? []) as E[]).filter(e => e.currency === "PEN").reduce((s, e) => s + Number(e.total), 0);
    const base = Number(m.sales_base ?? 0);
    const est = estimateTaxes({ regime, monthSalesBase: base, monthSalesTax: Number(m.sales_tax ?? 0), monthPurchasesTax: expTax, yearSalesBase: Number(y.sales_base ?? 0), monthPurchasesTotal: monthBuys, yearPurchasesTotal: yearBuys });
    const [yy, mm] = today.split("-").map(Number);
    const daysLeft = Math.max(1, new Date(Date.UTC(yy, mm, 0)).getUTCDate() - Number(today.slice(8)) + 1);
    const left = Math.round((base - expBase - est.renta) * 100) / 100;
    return <>{heading(`IMPUESTOS / ${name}`, title, "Lo que deberías guardar para SUNAT este mes y lo que realmente te queda. Es referencial: confírmalo con tu contador.", org)}
      <RegimePicker org={org} current={regime} canSave={can(c.access, "settings")} />
      {month.error ? failed("tus cifras") : !regime ? <div className="fv-empty"><h2>Elige tu régimen</h2><p>Con él calculamos cuánto separar cada día para pagar a SUNAT sin sustos.</p></div> : <>
        <div className="fv-kpis fv-kpis-4">
          <div style={tone("#ff8aa8")}><span>Guarda para SUNAT</span><strong>{fmt(est.total)}</strong><small>{regime === "nrus" ? "cuota del Nuevo RUS" : `IGV ${fmt(est.igv)} + renta ${fmt(est.renta)}`}</small></div>
          <div style={tone("#ffb35c")}><span>Separa por día</span><strong>{fmt(Math.round(est.total / daysLeft * 100) / 100)}</strong><small>{daysLeft} días para fin de mes</small></div>
          <div style={tone("#3ee6b0")}><span>Vendiste (sin IGV)</span><strong>{fmt(base)}</strong><small>este mes</small></div>
          <div style={tone("#6fb7ff")}><span>Te queda</span><strong>{fmt(left)}</strong><small>ventas − gastos − renta</small></div>
        </div>
        {est.warnings.map((w, i) => <p key={`w${i}`} className="fv-error">{w}</p>)}
        {est.notes.map((n, i) => <p key={`n${i}`} className="fv-note-box">{n}</p>)}
        <p className="fv-caption">Los gastos con comprobante que registras (Gastos o Compras) bajan el IGV a pagar. <Link className="fv-link" href={`/erp/${org}/gastos`}>Ver gastos</Link></p>
      </>}
    </>;
  }

  if (id === "comisiones") {
    const ym = /^\d{4}-\d{2}$/.test(mes ?? "") ? mes! : today.slice(0, 7);
    const from = `${ym}-01`;
    const [y, mo] = ym.split("-").map(Number);
    const to = mo === 12 ? `${y + 1}-01-01` : `${y}-${String(mo + 1).padStart(2, "0")}-01`;
    const res = await c.db.rpc("seller_ranking", { p_org: org, p_from: from, p_to: to });
    type Row = { user_id: string; name: string | null; sales_count: number; sales_total: number | string; commission_pct: number | string | null; commission: number | string | null; goal: number | string | null };
    const rows = ((res.data ?? []) as Row[]).map(r => ({ ...r, sales_total: Number(r.sales_total), commission: Number(r.commission ?? 0), goal: r.goal == null ? null : Number(r.goal) }));
    const top = rows[0]?.sales_total ?? 0;
    return <>{heading(`EQUIPO / ${name}`, title, "Quién vende más este mes, cuánto le toca de comisión y cómo va contra su meta. El porcentaje y la meta se fijan en el móvil (Equipo).", org)}
      <form className="fv-board-tools" method="get"><label className="fv-search fv-narrow"><span>Mes</span><input type="month" name="mes" defaultValue={ym} /></label><button className="fv-button secondary">Ver</button></form>
      {res.error ? failed("el ranking") : !rows.length ? <div className="fv-empty"><h2>Sin ventas en este mes</h2><p>Cada venta queda a nombre de quien la hizo.</p></div>
        : <ol className="fv-ranking">{rows.map((r, i) => <li key={r.user_id}>
          <b className="fv-rank">{i + 1}</b>
          <div><strong>{r.name || "Sin nombre"}</strong><small>{r.sales_count} {r.sales_count === 1 ? "venta" : "ventas"}{r.commission_pct ? ` · comisión ${Number(r.commission_pct)}%` : ""}</small>
            <span className="fv-bar"><i style={{ width: `${top ? Math.round(r.sales_total / top * 100) : 0}%` }} /></span>
            {r.goal ? <small>{Math.round(r.sales_total / r.goal * 100)}% de su meta de {fmt(r.goal)}</small> : null}</div>
          <div className="fv-rank-amounts"><strong>{fmt(r.sales_total)}</strong>{r.commission ? <small>Comisión {fmt(r.commission)}</small> : null}</div>
        </li>)}</ol>}
    </>;
  }

  if (id === "recurrentes") {
    const res = await c.db.from("recurring_invoices").select("id,client_name,items,tax_rate,currency,day_of_month,next_run,active,runs,last_error").eq("org_id", org).order("created_at", { ascending: false }).limit(500);
    type Rec = { id: string; client_name: string; items: { description: string; quantity: number; unit_price: number }[]; tax_rate: number | string; currency: string; day_of_month: number; next_run: string; active: boolean; runs: number; last_error: string | null };
    const rows = (res.data ?? []) as Rec[];
    const gross = (r: Rec) => Math.round(r.items.reduce((s, i) => s + i.quantity * i.unit_price, 0) * (1 + Number(r.tax_rate) / 100) * 100) / 100;
    const monthly = rows.filter(r => r.active).reduce((s, r) => s + gross(r), 0);
    return <>{heading(`VENDER / ${name}`, title, "Alquileres, mensualidades y pensiones que se facturan solos cada mes como borrador. Tú solo revisas y emites.", org, liveRec)}
      <div className="fv-actions-row"><RecurringRun org={org} /></div>
      <RecurringForm org={org} currency={cur} />
      {res.error ? failed("las mensualidades") : <>
        <div className="fv-kpis"><div style={tone("#3ee6b0")}><span>Facturas al mes</span><strong>{fmt(monthly)}</strong><small>{rows.filter(r => r.active).length} activas</small></div></div>
        {!rows.length ? <div className="fv-empty"><h2>Sin mensualidades</h2><p>Crea la primera: cada mes se genera sola en el día que elijas.</p></div>
          : <div className="fv-table-scroll fv-data"><table><thead><tr><th>Cliente</th><th>Concepto</th><th>Importe</th><th>Día</th><th>Próxima</th><th>Estado</th><th /></tr></thead><tbody>
            {rows.map(r => <tr key={r.id}><td><strong>{r.client_name}</strong></td><td>{r.items[0]?.description ?? "—"}{r.items.length > 1 ? ` +${r.items.length - 1}` : ""}</td><td><b>{money(gross(r), r.currency || cur)}</b></td><td>{r.day_of_month}</td><td>{dateOnly(r.next_run)}</td>
              <td>{r.last_error ? <span className="fv-pill is-bad" title={r.last_error}>Revisar</span> : r.active ? <span className="fv-pill is-ok">Activa · {r.runs}</span> : <span className="fv-pill is-off">Pausada</span>}</td>
              <td><RecurringActions org={org} id={r.id} active={r.active} /></td></tr>)}
          </tbody></table></div>}
      </>}
    </>;
  }

  if (id === "tienda") {
    const [store, prods, orders] = await Promise.all([
      c.db.from("org_store").select("slug,enabled,headline,whatsapp").eq("org_id", org).maybeSingle(),
      c.db.from("products").select("id,name,unit_price,in_store,active").eq("org_id", org).eq("active", true).order("name").limit(1000),
      c.db.from("quotes").select("id,number,created_at,status").eq("org_id", org).eq("source", "store").order("created_at", { ascending: false }).limit(20),
    ]);
    const s = (store.data ?? { slug: "", enabled: false, headline: "", whatsapp: "" }) as { slug: string; enabled: boolean; headline: string | null; whatsapp: string | null };
    type P = { id: string; name: string; unit_price: number | string; in_store: boolean | null };
    const products = (prods.data ?? []) as P[];
    const rate = Number(c.organization.default_tax_rate ?? 18);
    const base = process.env.NEXT_PUBLIC_SITE_URL || "https://factura-voz-two.vercel.app";
    return <>{heading(`VENDER MÁS / ${name}`, title, "Tu catálogo como página web: tus clientes eligen y te llega el pedido por WhatsApp. Lo que cambies aquí se ve también en el móvil.", org)}
      <StoreForm org={org} slug={s.slug ?? ""} enabled={!!s.enabled} headline={s.headline ?? ""} whatsapp={s.whatsapp ?? ""} base={base.replace(/^https?:\/\//, "")} />
      <section className="fv-create" style={{ padding: 18 }}><h3>Productos en la tienda ({products.filter(p => p.in_store !== false).length} de {products.length})</h3>
        {prods.error ? failed("los productos") : <ul className="fv-lines">{products.slice(0, 300).map(p => <li key={p.id}><span>{p.name} · <b>{fmt(Math.round(Number(p.unit_price) * (1 + rate / 100) * 100) / 100)}</b></span><InStoreToggle org={org} id={p.id} on={p.in_store !== false} /></li>)}</ul>}
      </section>
      <section className="fv-create" style={{ padding: 18 }}><h3>Últimos pedidos de la tienda</h3>
        {!(orders.data ?? []).length ? <p className="fv-caption">Aún no hay pedidos. Comparte el enlace de tu tienda por WhatsApp y redes.</p>
          : <ul className="fv-lines">{((orders.data ?? []) as { id: string; number: string | null; created_at: string; status: string }[]).map(o => <li key={o.id}><span>{o.number ?? "Pedido"} · {dateTime(o.created_at)}</span><span className={o.status === "sent" ? "fv-pill is-wait" : "fv-pill is-ok"}>{o.status === "sent" ? "Nuevo" : o.status === "converted" ? "Vendido" : o.status}</span></li>)}</ul>}
        <p className="fv-caption"><Link className="fv-link" href={`/erp/${org}/cotizaciones`}>Los pedidos llegan como cotización: ábrelos en Cotizaciones →</Link></p>
      </section>
    </>;
  }

  if (id === "encuestas") {
    const [res, settings] = await Promise.all([
      c.db.from("surveys").select("token,score,comment,answered_at,created_at").eq("org_id", org).order("created_at", { ascending: false }).limit(300),
      c.db.from("org_settings").select("survey_auto").eq("org_id", org).maybeSingle(),
    ]);
    type S = { token: string; score: number | null; comment: string | null; answered_at: string | null; created_at: string };
    const rows = (res.data ?? []) as S[];
    const answered = rows.filter(r => r.answered_at && r.score != null);
    const avg = answered.length ? answered.reduce((s, r) => s + (r.score ?? 0), 0) / answered.length : 0;
    const happy = answered.filter(r => (r.score ?? 0) >= 4).length;
    return <>{heading(`CLIENTES / ${name}`, title, "Después de cada venta, tu cliente califica de 1 a 5 estrellas y te deja un comentario. Así sabes qué mejorar antes de que se vaya.", org, liveSurveys)}
      <SurveyToggle org={org} on={(settings.data as { survey_auto: boolean | null } | null)?.survey_auto === true} canSave={can(c.access, "settings")} />
      {res.error ? failed("las encuestas") : <>
        <div className="fv-kpis">
          <div style={tone("#ffb35c")}><span>Calificación promedio</span><strong>{answered.length ? `${avg.toFixed(1)} ★` : "—"}</strong><small>{answered.length} respuestas</small></div>
          <div style={tone("#3ee6b0")}><span>Contentos (4–5 ★)</span><strong>{answered.length ? `${Math.round(happy / answered.length * 100)}%` : "—"}</strong></div>
          <div style={tone("#6fb7ff")}><span>Enviadas</span><strong>{rows.length}</strong><small>{rows.length - answered.length} sin responder</small></div>
        </div>
        {!answered.length ? <div className="fv-empty"><h2>Aún no hay respuestas</h2><p>Activa el envío automático o envía la encuesta desde un comprobante en el móvil.</p></div>
          : <ul className="fv-alerts">{answered.slice(0, 100).map(r => <li key={r.token} className={(r.score ?? 0) <= 2 ? "is-bad" : (r.score ?? 0) === 3 ? "is-warn" : ""}><i aria-hidden="true" /><div><strong>{"★".repeat(r.score ?? 0)}{"☆".repeat(5 - (r.score ?? 0))}</strong>{r.comment && <p>{r.comment}</p>}<small>{dateTime(r.answered_at!)}</small></div></li>)}</ul>}
      </>}
    </>;
  }

  if (id === "conciliacion") {
    const [lines, inv] = await Promise.all([
      c.db.from("bank_lines").select("id,line_date,description,amount,reference,status").eq("org_id", org).eq("status", "pendiente").order("line_date", { ascending: false }).limit(500),
      c.db.from("invoices").select("id,number,issue_date,amt_total,client:clients(name),payments(amount)").eq("org_id", org).eq("status", "sent").is("voided_at", null).order("issue_date", { ascending: false }).limit(1000),
    ]);
    type L = { id: string; line_date: string; description: string; amount: number | string; reference: string | null };
    type I = { id: string; number: string; issue_date: string; amt_total: number | string | null; client: unknown; payments: { amount: number | string }[] | null };
    const ls = (lines.data ?? []) as L[];
    const open: Receivable[] = ((inv.data ?? []) as unknown as I[]).map(i => {
      const cl = (Array.isArray(i.client) ? i.client[0] : i.client) as { name: string } | null;
      const paid = (i.payments ?? []).reduce((s, p) => s + Number(p.amount), 0);
      return { invoiceId: i.id, number: i.number ?? "", client: cl?.name ?? "", balance: Math.round((Number(i.amt_total ?? 0) - paid) * 100) / 100, issueDate: i.issue_date };
    }).filter(r => r.balance > 0.009);
    const suggestions = suggestMatches(ls.map(l => ({ date: l.line_date, description: l.description, amount: Number(l.amount), reference: l.reference ?? "" })), open);
    const byKey = new Map(suggestions.map(s => [`${s.line.date}|${s.line.amount}|${s.line.reference}|${s.line.description}`, s] as const));
    return <>{heading(`COBROS / ${name}`, title, "Sube el extracto del banco y te decimos qué depósito paga qué factura. Confirmas con un clic y el cobro queda registrado.", org, liveBank)}
      <BankImport org={org} />
      {lines.error ? failed("los movimientos") : !ls.length ? <div className="fv-empty"><h2>Todo conciliado</h2><p>Cuando subas un extracto, los depósitos sin asociar aparecerán aquí.</p></div>
        : <div className="fv-table-scroll fv-data"><table><thead><tr><th>Fecha</th><th>Detalle</th><th>Monto</th><th>Sugerencia</th><th /></tr></thead><tbody>
          {ls.map(l => {
            const s = byKey.get(`${l.line_date}|${Number(l.amount)}|${l.reference ?? ""}|${l.description}`);
            return <tr key={l.id}><td>{dateOnly(l.line_date)}</td><td>{l.description}{l.reference ? <small className="fv-muted"> · Op. {l.reference}</small> : null}</td>
              <td><b className={Number(l.amount) < 0 ? "fv-neg" : ""}>{fmt(Number(l.amount))}</b></td>
              <td>{s ? <><strong>{s.invoice.number}</strong> · {s.invoice.client}<br /><small className="fv-muted">{s.why} · {Math.round(s.score * 100)}%</small></> : Number(l.amount) > 0 ? <small className="fv-muted">Sin factura parecida</small> : <small className="fv-muted">Egreso</small>}</td>
              <td><BankMatch org={org} lineId={l.id} invoiceId={s?.invoice.invoiceId ?? null} label="Confirmar cobro" /></td></tr>;
          })}
        </tbody></table></div>}
    </>;
  }

  if (id === "importar") {
    const hist = await c.db.from("wb_imports").select("id,file_name,status,result,created_at,undone_at").eq("org_id", org).order("created_at", { ascending: false }).limit(20);
    type H = { id: string; file_name: string; status: string; result: Record<string, unknown> | null; created_at: string; undone_at: string | null };
    return <>{heading(`DATOS / ${name}`, title, "Trae clientes, productos y comprobantes de tu sistema anterior en minutos. Lo importado se puede deshacer desde el móvil.", org)}
      <ImportBoard org={org} taxRate={Number(c.organization.default_tax_rate ?? 18)} />
      {!hist.error && (hist.data ?? []).length > 0 && <section className="fv-create" style={{ padding: 18 }}><h3>Importaciones anteriores</h3>
        <ul className="fv-lines">{((hist.data ?? []) as H[]).map(h => <li key={h.id}><span>{h.file_name} · {dateTime(h.created_at)}</span><span className={h.undone_at ? "fv-pill is-off" : h.status === "done" || h.status === "terminado" ? "fv-pill is-ok" : "fv-pill is-wait"}>{h.undone_at ? "Deshecha" : h.status}</span></li>)}</ul></section>}
    </>;
  }

  if (id === "cuaderno") {
    return <>{heading(`VENDER / ${name}`, title, "Tómale foto a tu cuaderno, a una nota o a un pedido de WhatsApp: lo convertimos en un borrador de venta que revisas antes de guardar.", org)}
      <NewInvoice key={`nb-${org}`} org={org} currency={cur} defaultTaxRate={Number(c.organization.default_tax_rate ?? 18)} voiceAllowed={hasFeature(c.license, "voz")} notebookAllowed />
      <p className="fv-caption">Los borradores aparecen en <Link className="fv-link" href={`/erp/${org}/comprobantes`}>Comprobantes</Link>, listos para emitir.</p>
    </>;
  }

  return null;
}
