"use client";
import { useActionState, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { addCashMove, closeCashDay, type FormResult } from "@/app/erp/actions";
import type { DaySummary } from "@/lib/dayclose";
import { cashBreakdown, cashDifference, countText, countTotal, denominations, methodLabel, methodShares, parseAmount, serviceMoves, serviceSummary, type CashierRow, type CashMove, type DayClosing } from "@/lib/erp/cash";

const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const longDay = (d: string) => new Intl.DateTimeFormat("es-PE", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
const hour = (iso: string) => new Intl.DateTimeFormat("es-PE", { hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));
const shift = (d: string, days: number) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + days); return x.toISOString().slice(0, 10); };
const kindLabel = { apertura: "Apertura", ingreso: "Ingreso", egreso: "Retiro" } as const;

/** The day's till: what was sold, how it was paid, cash movements and the blind count, shared with the mobile app. */
export default function CashBoard({ org, day, today, summary, moves, closing, showExpected, cashiers = [], business = "" }: {
  org: string; day: string; today: string; summary: DaySummary; moves: CashMove[]; closing: DayClosing | null; showExpected: boolean; cashiers?: CashierRow[]; business?: string;
}) {
  const cur = summary.currency || "PEN";
  const shares = methodShares(summary);
  const collected = shares.reduce((a, r) => a + r.total, 0);
  const opened = moves.some(m => m.kind === "apertura");
  const isToday = day === today;
  const status = closing ? { tone: "is-off", text: "Caja cerrada" } : opened ? { tone: "is-ok", text: "Caja abierta" } : { tone: "is-wait", text: isToday ? "Aún no se abre la caja" : "Día sin apertura" };
  return <section className="fv-board fv-cash">
    <nav className="fv-daybar" aria-label="Elegir día">
      <Link className="fv-icon-button" href={`?dia=${shift(day, -1)}`} aria-label="Día anterior">‹</Link>
      <div><strong>{longDay(day)}</strong><span className={`fv-pill ${status.tone}`}>{status.text}</span></div>
      {isToday ? <span className="fv-icon-button is-disabled" aria-hidden="true">›</span> : <Link className="fv-icon-button" href={`?dia=${shift(day, 1)}`} aria-label="Día siguiente">›</Link>}
      {!isToday && <Link className="fv-button secondary" href="?">Ir a hoy</Link>}
    </nav>

    <ol className="fv-steps" aria-label="Proceso de caja">
      <li className={opened ? "is-done" : "is-now"}><b>1</b><span>Apertura</span><small>{opened ? "Fondo registrado" : "Cuenta el sencillo y abre"}</small></li>
      <li className={closing ? "is-done" : opened ? "is-now" : ""}><b>2</b><span>Durante el día</span><small>Ventas, ingresos y retiros con motivo</small></li>
      <li className={closing ? "is-done" : opened ? "is-next" : ""}><b>3</b><span>Arqueo</span><small>Billetes, monedas y pagos digitales</small></li>
      <li className={closing ? "is-done" : ""}><b>4</b><span>Cierre y reporte</span><small>{closing ? "Caja cerrada" : "Diferencia explicada"}</small></li>
    </ol>

    <div className="fv-kpis">
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Ventas del día</span><strong>{fmt(Number(summary.sales?.sales_total ?? 0), cur)}</strong><small>{summary.sales?.sales_count ?? 0} ventas emitidas</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Cobrado</span><strong>{fmt(collected, cur)}</strong><small>{shares.length ? shares.map(s => s.label).join(" · ") : "sin cobros registrados"}</small></div>
      {showExpected || closing
        ? <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Efectivo esperado en caja</span><strong>{fmt(Number(closing?.expected_cash ?? summary.expected_cash ?? 0), cur)}</strong><small>apertura + efectivo − retiros</small></div>
        : <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Arqueo ciego</span><strong>Cuenta y escribe</strong><small>el esperado lo ve el dueño al cerrar</small></div>}
    </div>

    <div className="fv-cash-grid">
      <section className="fv-create fv-cash-card">
        <h3>Cómo cobraste</h3>
        {shares.length ? <ul className="fv-shares">{shares.map(s => <li key={s.method} style={{ "--share": `${s.share}%` } as React.CSSProperties}>
          <span>{s.label}</span><span>{fmt(s.total, cur)} · {s.share} %</span><i aria-hidden="true" />
        </li>)}</ul> : <p className="fv-muted">Todavía no hay cobros este día.</p>}
        {(Number(summary.fiado_charged ?? 0) > 0 || Number(summary.fiado_paid ?? 0) > 0) && <p className="fv-muted">Fiado: se anotaron {fmt(Number(summary.fiado_charged ?? 0), cur)} y se abonaron {fmt(Number(summary.fiado_paid ?? 0), cur)}.</p>}
        {showExpected && <>
          <h3>Cómo se forma el efectivo</h3>
          <dl className="fv-sums">
            {cashBreakdown(summary).map(l => <div key={l.label}><dt>{l.label}</dt><dd>{l.sign < 0 ? "−" : ""}{fmt(l.value, cur)}</dd></div>)}
            <div className="is-total"><dt>Esperado</dt><dd>{fmt(Number(summary.expected_cash ?? 0), cur)}</dd></div>
          </dl>
        </>}
      </section>

      <section className="fv-create fv-cash-card">
        <h3>Movimientos de caja</h3>
        {moves.length ? <ul className="fv-lines fv-ledger">{moves.map(m => <li key={m.id}>
          <span><b className={m.kind === "egreso" ? "is-out" : "is-in"}>{kindLabel[m.kind]}</b> {hour(m.created_at)} · {methodLabel[m.method] ?? m.method}{m.note ? ` · ${m.note}` : ""}</span>
          <span>{m.kind === "egreso" ? "−" : "+"}{fmt(m.amount, cur)}</span>
        </li>)}</ul> : <p className="fv-muted">Sin movimientos. Empieza registrando la apertura con el sencillo del día.</p>}
        {(() => { const sv = serviceSummary(moves); return sv.count > 0 && <p className="fv-muted">Agente y recargas (no son ventas): entraron {fmt(sv.inflow, cur)}, salieron {fmt(sv.outflow, cur)} · neto en caja {fmt(sv.net, cur)}.</p>; })()}
        {isToday && !closing && <MoveForm org={org} opened={opened} />}
      </section>
    </div>

    {showExpected && cashiers.length > 1 && <section className="fv-create fv-cash-card">
      <h3>Por cajero</h3>
      <p className="fv-muted">Cuenta el cajón de cada persona contra lo que cobró en efectivo y lo que registró en caja. Lo digital ya está en tu cuenta.</p>
      <ul className="fv-lines fv-ledger">{cashiers.map(r => <li key={r.user_id}>
        <span><b>{r.name}</b> {r.count} {r.count === 1 ? "cobro" : "cobros"} · efectivo {fmt(r.cashSales, cur)} · digital {fmt(r.digital, cur)}{r.cashOut ? ` · retiros ${fmt(r.cashOut, cur)}` : ""}</span>
        <span>debe tener {fmt(r.expected, cur)}</span>
      </li>)}</ul>
    </section>}

    {closing ? <><ClosingCard closing={closing} currency={cur} /><DayReport day={day} summary={summary} moves={moves} closing={closing} currency={cur} business={business} /></>
      : (isToday || day < today) && opened ? <CloseForm org={org} day={day} expected={showExpected ? Number(summary.expected_cash ?? 0) : null} currency={cur} digital={shares.filter(x => x.method !== "efectivo")} />
      : isToday || day < today ? <p className="fv-muted">Primero abre la caja con el sencillo del día (paso 1); luego podrás hacer el arqueo y cerrar.</p> : null}
  </section>;
}

function useDone(state: FormResult, then: () => void) {
  const router = useRouter();
  const done = useRef(state);
  const after = useRef(then);
  after.current = then;
  useEffect(() => {
    if (state === done.current || !state.ok) return;
    done.current = state;
    router.refresh();
    after.current();
  }, [state, router]);
}

function MoveForm({ org, opened }: { org: string; opened: boolean }) {
  const [kind, setKind] = useState<"apertura" | "ingreso" | "egreso">(opened ? "egreso" : "apertura");
  const [note, setNote] = useState("");
  const [amount, setAmount] = useState("");
  const [state, action, pending] = useActionState<FormResult, FormData>(addCashMove.bind(null, org), { ok: false, message: "" });
  const form = useRef<HTMLFormElement>(null);
  useDone(state, () => { form.current?.reset(); setNote(""); setAmount(""); });
  return <form ref={form} action={action} className="fv-fiado-form">
    {opened && <div className="fv-chips" role="group" aria-label="Agente y recargas">
      {serviceMoves.map(m => <button key={m.id} type="button" className="fv-chip" aria-pressed={note === m.note} onClick={() => { setKind(m.kind); setNote(m.note); }}>{m.label}</button>)}
    </div>}
    <div className="fv-segment" role="group" aria-label="Tipo de movimiento">
      {(opened ? ["egreso", "ingreso"] as const : ["apertura", "ingreso", "egreso"] as const).map(k => <button key={k} type="button" aria-pressed={kind === k} onClick={() => setKind(k)}>{k === "apertura" ? "Abrir caja" : k === "ingreso" ? "Ingreso" : "Retiro o pago"}</button>)}
    </div>
    <input type="hidden" name="kind" value={kind} />
    <label><span>{kind === "apertura" ? "Fondo inicial (sencillo)" : "Importe"}</span><input name="amount" inputMode="decimal" required autoComplete="off" placeholder="0.00" value={amount} onChange={e => setAmount(e.target.value)} /></label>
    {kind === "apertura" && <details className="fv-denom-wrap"><summary className="fv-link">Contar billete por billete</summary><DenomCounter onTotal={t => setAmount(t ? t.toFixed(2) : "")} /></details>}
    {kind === "apertura" ? <input type="hidden" name="method" value="efectivo" />
      : <label><span>Medio</span><select name="method" defaultValue="efectivo">{Object.entries(methodLabel).filter(([k]) => k !== "mercadopago").map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>}
    <label className="fv-grow"><span>{kind === "egreso" ? "Motivo (obligatorio)" : "Nota"}</span><input name="note" maxLength={200} required={kind === "egreso"} value={note} onChange={e => setNote(e.target.value)} placeholder={kind === "egreso" ? "Pago a proveedor, pasajes…" : "Opcional"} /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : kind === "apertura" ? "Abrir caja" : "Registrar"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}

/** Count by notes and coins; reports the total. */
function DenomCounter({ onTotal }: { onTotal: (total: number, qty: Record<string, number>) => void }) {
  const [qty, setQty] = useState<Record<string, number>>({});
  const set = (d: number, v: string) => { const next = { ...qty, [String(d)]: Math.max(0, Math.min(99999, Math.floor(Number(v) || 0))) }; setQty(next); onTotal(countTotal(next), next); };
  return <div className="fv-denoms">{denominations.map(d => <label key={d} className={d >= 10 ? "is-bill" : "is-coin"}>
    <span>{d >= 1 ? `S/ ${d}` : `${Math.round(d * 100)} cént.`}</span>
    <input inputMode="numeric" aria-label={`Cantidad de ${d >= 1 ? `S/ ${d}` : `${Math.round(d * 100)} céntimos`}`} value={qty[String(d)] || ""} onChange={e => set(d, e.target.value)} placeholder="0" />
    <small>{qty[String(d)] ? fmt(d * qty[String(d)], "PEN") : ""}</small></label>)}
    <p className="fv-denom-total">Total contado: <b>{fmt(countTotal(qty), "PEN")}</b></p></div>;
}

/** Steps 3 and 4: blind count by notes and coins, digital methods checked one by one, float for tomorrow and reason. */
function CloseForm({ org, day, expected, currency, digital }: { org: string; day: string; expected: number | null; currency: string; digital: { method: string; label: string; total: number }[] }) {
  const [counted, setCounted] = useState("");
  const [qty, setQty] = useState<Record<string, number>>({});
  const [byDenom, setByDenom] = useState(true);
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [float, setFloat] = useState("");
  const [reason, setReason] = useState("");
  const [err, setErr] = useState("");
  const [state, action, pending] = useActionState<FormResult, FormData>(closeCashDay.bind(null, org), { ok: false, message: "" });
  useDone(state, () => { setCounted(""); setQty({}); setFloat(""); setReason(""); });
  const value = byDenom ? (Object.values(qty).some(v => v > 0) ? countTotal(qty) : null) : parseAmount(counted);
  const diff = expected !== null && value !== null ? cashDifference(expected, value) : null;
  const keep = parseAmount(float);
  const allChecked = digital.every(d => checked[d.method]);
  const note = [reason.trim(), byDenom && countText(qty) ? `Conteo: ${countText(qty)}` : "", keep != null && keep > 0 ? `Fondo para mañana ${keep.toFixed(2)}` : ""].filter(Boolean).join(" · ").slice(0, 300);
  return <form action={action} className="fv-create fv-close fv-close-pro" onSubmit={e => {
    if (!allChecked) { e.preventDefault(); setErr("Marca cada medio digital cuando lo hayas visto en tu app o voucher."); return; }
    if (diff && diff.kind !== "cuadra" && !reason.trim()) { e.preventDefault(); setErr("No cuadra: explica el motivo antes de cerrar."); return; }
    setErr("");
  }}>
    <div><h3>Arqueo y cierre</h3><p className="fv-muted">{expected === null ? "Es un arqueo ciego: cuentas sin ver el esperado y el dueño ve la diferencia." : "Cuenta el efectivo del cajón. Si no cuadra, explica el motivo."}</p></div>
    <input type="hidden" name="day" value={day} />
    <input type="hidden" name="counted" value={value == null ? "" : value.toFixed(2)} />
    <input type="hidden" name="note" value={note} />
    <div className="fv-segment" role="group" aria-label="Forma de contar"><button type="button" aria-pressed={byDenom} onClick={() => setByDenom(true)}>Billetes y monedas</button><button type="button" aria-pressed={!byDenom} onClick={() => setByDenom(false)}>Escribir el total</button></div>
    {byDenom ? <DenomCounter onTotal={(_, q) => setQty(q)} /> : <label className="fv-search"><span>Efectivo contado</span><input inputMode="decimal" autoComplete="off" value={counted} onChange={e => setCounted(e.target.value)} placeholder="0.00" /></label>}
    {diff && <p className={`fv-pill ${diff.kind === "cuadra" ? "is-ok" : "is-bad"}`} aria-live="polite">{diff.kind === "cuadra" ? "Cuadra exacto" : `${diff.kind === "sobra" ? "Sobran" : "Faltan"} ${fmt(diff.amount, currency)}`}</p>}
    {digital.length > 0 && <fieldset className="fv-digital-check"><legend>Pagos digitales: revísalos en tu app o en el voucher</legend>
      {digital.map(d => <label key={d.method} className="fv-check"><input type="checkbox" checked={!!checked[d.method]} onChange={e => setChecked(c => ({ ...c, [d.method]: e.target.checked }))} /> {d.label}: {fmt(d.total, currency)} llegó completo</label>)}</fieldset>}
    <div className="fv-two">
      <label className="fv-search"><span>Fondo que dejas para mañana</span><input inputMode="decimal" value={float} onChange={e => setFloat(e.target.value)} placeholder="0.00" /></label>
      {value != null && keep != null && keep > 0 && <p className="fv-muted">Retira para guardar o depositar: <b>{fmt(Math.max(0, value - keep), currency)}</b></p>}
    </div>
    <label className="fv-search fv-grow"><span>Motivo o nota{diff && diff.kind !== "cuadra" ? " (obligatorio)" : ""}</span><input maxLength={180} value={reason} onChange={e => setReason(e.target.value)} placeholder="Ej.: di mal un vuelto, pagué el gas" /></label>
    <button className="fv-button" disabled={pending || value === null}>{pending ? "Cerrando…" : "Cerrar caja y enviar reporte"}</button>
    {err && <p className="fv-error" role="alert">{err}</p>}
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}

/** Printable closing report of the day and a WhatsApp summary for the owner. */
function DayReport({ day, summary, moves, closing, currency, business }: { day: string; summary: DaySummary; moves: CashMove[]; closing: DayClosing; currency: string; business: string }) {
  const shares = methodShares(summary);
  const d = cashDifference(Number(closing.expected_cash), Number(closing.counted_cash));
  const text = [`Cierre de caja ${business} · ${longDay(day)}`, `Ventas: ${fmt(Number(summary.sales?.sales_total ?? 0), currency)} (${summary.sales?.sales_count ?? 0})`,
    ...shares.map(x => `${x.label}: ${fmt(x.total, currency)}`), `Efectivo esperado: ${fmt(Number(closing.expected_cash), currency)}`, `Contado: ${fmt(Number(closing.counted_cash), currency)}`,
    d.kind === "cuadra" ? "Cuadró exacto" : `${d.kind === "sobra" ? "Sobraron" : "Faltaron"} ${fmt(d.amount, currency)}`, closing.note ? `Nota: ${closing.note}` : ""].filter(Boolean).join("\n");
  const extra = moves.filter(m => m.kind !== "apertura");
  return <section className="fv-create fv-cash-card fv-report" id="reporte-caja">
    <header><h3>Reporte de cierre</h3><span className="fv-actions"><button type="button" className="fv-button secondary" onClick={() => window.print()}>Imprimir</button>
      <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/?text=${encodeURIComponent(text)}`}>Enviar por WhatsApp</a></span></header>
    <p className="fv-muted">{business} · {longDay(day)} · cerrado a las {hour(closing.created_at)}</p>
    <dl className="fv-sums">
      <div><dt>Ventas emitidas ({summary.sales?.sales_count ?? 0})</dt><dd>{fmt(Number(summary.sales?.sales_total ?? 0), currency)}</dd></div>
      {shares.map(x => <div key={x.method}><dt>Cobrado en {x.label}</dt><dd>{fmt(x.total, currency)}</dd></div>)}
      {cashBreakdown(summary).map(l => <div key={l.label}><dt>{l.label}</dt><dd>{l.sign < 0 ? "−" : ""}{fmt(l.value, currency)}</dd></div>)}
      <div className="is-total"><dt>Efectivo esperado</dt><dd>{fmt(Number(closing.expected_cash), currency)}</dd></div>
      <div className="is-total"><dt>Efectivo contado</dt><dd>{fmt(Number(closing.counted_cash), currency)}</dd></div>
      <div><dt>Diferencia</dt><dd className={d.kind === "falta" ? "fv-neg" : ""}>{d.kind === "cuadra" ? "Cuadra" : `${d.kind === "sobra" ? "+" : "−"}${fmt(d.amount, currency)}`}</dd></div>
    </dl>
    {extra.length > 0 && <><h4>Ingresos y retiros</h4><ul className="fv-lines">{extra.map(m => <li key={m.id}><span>{hour(m.created_at)} · {m.note || kindLabel[m.kind]}</span><span>{m.kind === "egreso" ? "−" : "+"}{fmt(m.amount, currency)}</span></li>)}</ul></>}
    {closing.note && <p><b>Nota:</b> {closing.note}</p>}
    <p className="fv-sign">Firma del cajero: ____________________ &nbsp; Firma del dueño: ____________________</p>
  </section>;
}

function ClosingCard({ closing, currency }: { closing: DayClosing; currency: string }) {
  const d = cashDifference(Number(closing.expected_cash), Number(closing.counted_cash));
  return <div className={`fv-sunat ${d.kind === "cuadra" ? "is-ok" : "is-bad"} fv-closed`}>
    <strong>{d.kind === "cuadra" ? "La caja cuadró" : `${d.kind === "sobra" ? "Sobraron" : "Faltaron"} ${fmt(d.amount, currency)}`}</strong>
    <span>Contado {fmt(Number(closing.counted_cash), currency)} · esperado {fmt(Number(closing.expected_cash), currency)} · cerrada a las {hour(closing.created_at)}</span>
    {closing.note && <span>Motivo: {closing.note}</span>}
  </div>;
}
