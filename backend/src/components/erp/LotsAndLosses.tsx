"use client";
import { useActionState, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { addLot, getProductLots, recordLoss, removeLot, type FormResult } from "@/app/erp/actions";
import { activeLots, expiryBucket, lossReasons, suggestedPrice, summarizeLosses, summarizeLots, type LossRow, type LotStatus } from "@/lib/erp/lots";

const empty: FormResult = { ok: false, message: "" };
const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const qty = (q: number) => (Number.isInteger(q) ? String(q) : q.toFixed(2));
const dateText = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
const daysText = (d: number) => d < 0 ? (d === -1 ? "venció ayer" : `venció hace ${-d} días`) : d === 0 ? "vence hoy" : d === 1 ? "vence mañana" : `vence en ${d} días`;
const newId = () => crypto.randomUUID();

/** Runs once per successful result: refresh the server data, then the caller's reset. */
function useDone(state: FormResult, then?: () => void) {
  const router = useRouter();
  const done = useRef(state);
  const after = useRef(then);
  after.current = then;
  useEffect(() => {
    if (state === done.current || !state.ok) return;
    done.current = state;
    router.refresh();
    after.current?.();
  }, [state, router]);
}

/** Inventory home: what expires soon, what already expired with stock, and this month's shrinkage. */
export function ExpiryOverview({ org, lots, losses, currency, salesTotal, canEdit }: {
  org: string; lots: LotStatus[]; losses: LossRow[]; currency: string; salesTotal: number | null; canEdit: boolean;
}) {
  const sum = summarizeLots(lots);
  const urgent = activeLots(lots).filter(l => l.days_left <= 30).slice(0, 40);
  const lossSum = summarizeLosses(losses, salesTotal);
  const [writing, setWriting] = useState<string | null>(null);
  return <section className="fv-expiry" aria-labelledby="fv-expiry-title">
    <div className="fv-expiry-head">
      <h2 id="fv-expiry-title">Vencimientos y mermas</h2>
      <p className="fv-muted">Se calcula con tus compras y lo que queda en stock: se asume que vendes primero lo que vence antes.</p>
    </div>
    <div className="fv-kpis">
      <div style={{ "--tone": "#ff6b6b" } as React.CSSProperties}><span>Vencidos con stock</span><strong>{sum.vencido.count ? `${sum.vencido.count} ${sum.vencido.count === 1 ? "lote" : "lotes"}` : "Ninguno"}</strong><small>{sum.vencido.count ? `${fmt(sum.vencido.value, currency)} por retirar` : "nada que retirar del anaquel"}</small></div>
      <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Vencen esta semana</span><strong>{sum.semana.count ? `${qty(sum.semana.units)} u.` : "Nada"}</strong><small>{sum.semana.count ? `${fmt(sum.semana.value, currency)} en riesgo: ponlos adelante` : "sin urgencias en 7 días"}</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Vencen este mes</span><strong>{sum.mes.count ? `${qty(sum.mes.units)} u.` : "Nada"}</strong><small>{sum.mes.count ? fmt(sum.mes.value, currency) : "próximos 30 días tranquilos"}</small></div>
      <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Merma de este mes</span><strong>{fmt(lossSum.total, currency)}</strong><small>{lossSum.share !== null ? `${lossSum.share} % de lo vendido` : losses.length ? `${losses.length} registros` : "sin mermas registradas"}</small></div>
    </div>

    {urgent.length ? <ul className="fv-lots">{urgent.map(l => {
      const bucket = expiryBucket(l.days_left);
      const offer = suggestedPrice(l.unit_price == null ? null : Number(l.unit_price), l.unit_cost == null ? null : Number(l.unit_cost), l.days_left);
      return <li key={l.lot_id} className={`is-${bucket}`}>
        <div>
          <strong>{l.product_name}</strong>
          <span>{qty(l.remaining)} {l.unit === "KGM" ? "kg" : "u."} · {daysText(l.days_left)} ({dateText(l.expires_on)}){l.lot_code ? ` · lote ${l.lot_code}` : ""}</span>
          {offer !== null && <span className="fv-offer">Rebájalo a {fmt(offer, currency)} para venderlo antes de que venza.</span>}
        </div>
        {canEdit && <button className={`fv-button ${bucket === "vencido" ? "" : "secondary"}`} onClick={() => setWriting(writing === l.lot_id ? null : l.lot_id)} aria-expanded={writing === l.lot_id}>
          {bucket === "vencido" ? "Retirar como merma" : "Registrar merma"}
        </button>}
        {writing === l.lot_id && <LossForm org={org} productId={l.product_id} stock={null} lots={[l]} defaults={{ reason: bucket === "vencido" ? "vencido" : "danado", quantity: l.remaining, lot: l.lot_id }} onDone={() => setWriting(null)} />}
      </li>;
    })}</ul> : <p className="fv-muted">{lots.length ? "Ningún lote vence en los próximos 30 días." : "Aún no hay fechas de vencimiento. Anótalas al registrar una compra o en la ficha de cada producto."}</p>}

    {losses.length > 0 && <details className="fv-losses">
      <summary>Mermas del mes por motivo{lossSum.uncosted ? ` · ${lossSum.uncosted} sin costo` : ""}</summary>
      <ul className="fv-shares">{lossSum.reasons.map(r => <li key={r.reason} style={{ "--share": `${lossSum.total ? Math.round((r.value / lossSum.total) * 100) : 0}%` } as React.CSSProperties}>
        <span>{r.label} · {r.count}</span><span>{fmt(r.value, currency)}</span><i aria-hidden="true" />
      </li>)}</ul>
      <ul className="fv-lines fv-ledger">{losses.slice(0, 30).map(r => <li key={r.id}>
        <span><b className="is-out">{lossReasons[r.reason]}</b> {r.product_name}{r.note ? ` · ${r.note}` : ""}{r.user_name ? ` · ${r.user_name}` : ""}</span>
        <span>−{qty(r.quantity)}{r.unit_cost != null ? ` · ${fmt(r.quantity * Number(r.unit_cost), currency)}` : ""}</span>
      </li>)}</ul>
    </details>}
  </section>;
}

/** Shrinkage form: quantity, reason (and lot when known). The database lowers stock in the same step. */
export function LossForm({ org, productId, stock, lots, defaults, onDone }: {
  org: string; productId: string; stock: number | null; lots: LotStatus[];
  defaults?: { reason?: string; quantity?: number; lot?: string }; onDone?: () => void;
}) {
  const [requestId, setRequestId] = useState(newId);
  const [reason, setReason] = useState(defaults?.reason ?? "vencido");
  const [state, action, pending] = useActionState(recordLoss.bind(null, org, stock ?? defaults?.quantity ?? null), empty);
  const form = useRef<HTMLFormElement>(null);
  useDone(state, () => { form.current?.reset(); setRequestId(newId()); onDone?.(); });
  return <form ref={form} action={action} className="fv-fiado-form fv-loss-form">
    <input type="hidden" name="request_id" value={requestId} />
    <input type="hidden" name="product_id" value={productId} />
    <label><span>Cantidad</span><input name="quantity" inputMode="decimal" required autoComplete="off" defaultValue={defaults?.quantity ?? ""} placeholder="0" /></label>
    <label><span>Motivo</span><select name="reason" value={reason} onChange={e => setReason(e.target.value)}>
      {Object.entries(lossReasons).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
    </select></label>
    {lots.length > 0 && <label><span>Lote</span><select name="lot_id" defaultValue={defaults?.lot ?? ""}>
      <option value="">Sin lote</option>
      {lots.map(l => <option key={l.lot_id} value={l.lot_id}>{dateText(l.expires_on)}{l.lot_code ? ` · ${l.lot_code}` : ""}</option>)}
    </select></label>}
    <label className="fv-grow"><span>{reason === "otro" ? "Motivo (obligatorio)" : "Nota"}</span><input name="note" maxLength={200} required={reason === "otro"} placeholder={reason === "robo" ? "Qué faltó y cuándo se notó" : "Opcional"} /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Registrar merma"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}

/** The product sheet's expiry dates: what is left of each lot, add one, remove one, and record shrinkage. */
export function ProductLots({ org, productId, unit, stock, canEdit }: { org: string; productId: string; unit: string; stock: number; canEdit: boolean }) {
  const [data, setData] = useState<Awaited<ReturnType<typeof getProductLots>> | null>(null);
  const [version, setVersion] = useState(0);
  const [removing, startRemove] = useTransition();
  const [message, setMessage] = useState("");
  useEffect(() => {
    let alive = true;
    getProductLots(org, productId).then(d => { if (alive) setData(d); });
    return () => { alive = false; };
  }, [org, productId, version]);
  const [state, action, pending] = useActionState(addLot.bind(null, org, productId), empty);
  const form = useRef<HTMLFormElement>(null);
  useDone(state, () => { form.current?.reset(); setVersion(v => v + 1); });
  const lots = data?.ok ? data.lots : [];
  const shown = lots.filter(l => l.remaining > 0 || l.days_left >= -30);
  const u = unit === "KGM" ? "kg" : "u.";
  return <section className="fv-client-block">
    <h3>Vencimientos</h3>
    {!data ? <div className="fv-skeleton" aria-label="Cargando vencimientos"><i /></div>
      : !data.ok ? <p role="alert" className="fv-error">{data.message}</p>
      : !shown.length ? <p className="fv-muted">Sin fechas de vencimiento. Anótalas al recibir la compra o aquí abajo.</p>
      : <ul className="fv-lines fv-ledger">{shown.map(l => <li key={l.lot_id} className={`is-${expiryBucket(l.days_left)}`}>
        <span><b className={l.days_left < 0 ? "is-out" : l.days_left <= 7 ? "is-warn" : "is-in"}>{dateText(l.expires_on)}</b> {daysText(l.days_left)}{l.lot_code ? ` · ${l.lot_code}` : ""}</span>
        <span>quedan {qty(l.remaining)} de {qty(l.quantity)} {u}
          {canEdit && <button className="fv-link" disabled={removing} onClick={() => startRemove(async () => { const r = await removeLot(org, l.lot_id); setMessage(r.message); if (r.ok) setVersion(v => v + 1); })} aria-label={`Quitar el lote que vence el ${dateText(l.expires_on)}`}>Quitar</button>}
        </span>
      </li>)}</ul>}
    {message && <p className="fv-caption" role="status">{message}</p>}
    {canEdit && <form ref={form} action={action} className="fv-fiado-form">
      <label><span>Vence el</span><input type="date" name="expires_on" required /></label>
      <label><span>Cantidad ({u})</span><input name="quantity" inputMode="decimal" required autoComplete="off" placeholder="0" /></label>
      <label className="fv-grow"><span>Lote</span><input name="lot_code" maxLength={40} placeholder="Opcional" /></label>
      <button className="fv-button secondary" disabled={pending}>{pending ? "Guardando…" : "Añadir fecha"}</button>
      {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
    </form>}
    {canEdit && stock > 0 && <>
      <h3>Registrar merma</h3>
      <LossForm org={org} productId={productId} stock={stock} lots={lots.filter(l => l.remaining > 0)} onDone={() => setVersion(v => v + 1)} />
    </>}
  </section>;
}
