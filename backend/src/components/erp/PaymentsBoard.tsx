"use client";
import { useMemo, useState } from "react";
import Link from "next/link";
import { methodLabel } from "@/lib/erp/cash";
import { groupByDay, matchesPayment, paymentReceipt, shiftMonth, summarizePayments, type PaymentRow } from "@/lib/erp/payments";

const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const monthName = (m: string) => new Intl.DateTimeFormat("es-PE", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(`${m}-15T12:00:00Z`));
const longDay = (d: string) => new Intl.DateTimeFormat("es-PE", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));

/** Money that came in during a month, from the same `payments` the mobile app records (RLS: company members). */
export default function PaymentsBoard({ rows, currency, month, today, capped = false }: { rows: PaymentRow[]; currency: string; month: string; today: string; capped?: boolean }) {
  const [q, setQ] = useState("");
  const [method, setMethod] = useState("todos");
  const s = useMemo(() => summarizePayments(rows, currency, month, today), [rows, currency, month, today]);
  const visible = useMemo(() => rows.filter(r => matchesPayment(r, { q, method })), [rows, q, method]);
  const groups = groupByDay(visible);
  const isCurrent = month === today.slice(0, 7);
  const used = [...new Set(rows.map(r => r.method))];
  return <section className="fv-board fv-cash">
    <nav className="fv-daybar" aria-label="Elegir mes">
      <Link className="fv-icon-button" href={`?mes=${shiftMonth(month, -1)}`} aria-label="Mes anterior">‹</Link>
      <div><strong>{monthName(month)}</strong>{isCurrent && <span className="fv-pill is-ok">Mes en curso</span>}</div>
      {isCurrent ? <span className="fv-icon-button is-disabled" aria-hidden="true">›</span> : <Link className="fv-icon-button" href={`?mes=${shiftMonth(month, 1)}`} aria-label="Mes siguiente">›</Link>}
      {!isCurrent && <Link className="fv-button secondary" href="?">Ir a este mes</Link>}
    </nav>

    <div className="fv-kpis">
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Cobrado en el mes</span><strong>{fmt(s.total, currency)}</strong><small>{s.count} {s.count === 1 ? "cobro registrado" : "cobros registrados"}</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Cobro promedio</span><strong>{fmt(s.average, currency)}</strong><small>{s.best ? `el mejor día fue el ${s.best}` : "sin cobros todavía"}</small></div>
      <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Pagos digitales</span><strong>{s.digitalShare} %</strong><small>Yape, Plin, tarjeta y transferencias</small></div>
    </div>

    <div className="fv-cash-grid">
      <section className="fv-create fv-cash-card">
        <h3>Cómo te pagaron</h3>
        {s.methods.length ? <ul className="fv-shares">{s.methods.map(m => <li key={m.method} style={{ "--share": `${m.share}%` } as React.CSSProperties}>
          <span>{m.label}</span><span>{fmt(m.total, currency)} · {m.share} %</span><i aria-hidden="true" />
        </li>)}</ul> : <p className="fv-muted">Todavía no hay cobros en este mes.</p>}
        {s.other > 0 && <p className="fv-muted">{s.other} {s.other === 1 ? "cobro" : "cobros"} en otra moneda no se suman aquí.</p>}
      </section>
      <section className="fv-create fv-cash-card">
        <h3>Día a día</h3>
        <figure className="fv-rhythm fv-month-rhythm" aria-label={s.best ? `Cobros por día; el mejor día fue el ${s.best}` : "Cobros por día"}>
          <div className="fv-rhythm-bars" style={{ "--cols": s.days.length } as React.CSSProperties}>
            {s.days.map(d => <span key={d.day} className={`${d.day === s.best ? "is-peak" : ""}${d.future ? " is-future" : ""}`} style={{ "--h": d.height } as React.CSSProperties} title={`Día ${d.day}: ${fmt(d.total, currency)} en ${d.count} ${d.count === 1 ? "cobro" : "cobros"}`} />)}
          </div>
          <figcaption>{s.best ? `Tu mejor día: el ${s.best}, con ${fmt(s.days[s.best - 1].total, currency)}.` : "Las barras se llenan con cada cobro, también los del móvil."}</figcaption>
        </figure>
      </section>
    </div>

    <div className="fv-board-tools">
      <label className="fv-search"><span>Buscar</span><input type="search" value={q} onChange={e => setQ(e.target.value)} placeholder="Comprobante, cliente, DNI, RUC o nota…" /></label>
      <label className="fv-search fv-narrow"><span>Medio</span>
        <select value={method} onChange={e => setMethod(e.target.value)}>
          <option value="todos">Todos</option>
          {used.map(m => <option key={m} value={m}>{methodLabel[m] ?? m}</option>)}
        </select>
      </label>
    </div>
    <p className="fv-caption" aria-live="polite">{visible.length} {visible.length === 1 ? "cobro" : "cobros"}{capped ? " · se muestran los 500 más recientes del mes" : ""}</p>

    {groups.map(g => <section key={g.day} className="fv-pay-day">
      <header><strong>{longDay(g.day)}</strong><span>{fmt(g.total, currency)}</span></header>
      <ul className="fv-lines fv-ledger">{g.items.map(p => <li key={p.id}>
        <span><b className="is-in">{methodLabel[p.method] ?? p.method}</b> {paymentReceipt(p)} · {p.invoice?.client?.name || "Cliente varios"}{p.note ? ` · ${p.note}` : ""}</span>
        <span>+{fmt(p.amount, p.invoice?.currency || currency)}</span>
      </li>)}</ul>
    </section>)}
    {!visible.length && <div className="fv-empty"><h2>{q || method !== "todos" ? "Sin coincidencias" : "Sin cobros en este mes"}</h2><p>Los pagos que registras en un comprobante, aquí o en el móvil, aparecen en esta lista.</p></div>}
  </section>;
}
