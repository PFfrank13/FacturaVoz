"use client";
import { useActionState, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createCoupon, redeemPoints, savePromotion, setLoyaltyRate, toggleCoupon, togglePromotion, type FormResult } from "@/app/erp/actions";
import { couponState, discountLabel, promoKinds, promoState, type Coupon, type LoyaltyRow, type Promotion } from "@/lib/erp/loyalty";

const empty: FormResult = { ok: false, message: "" };
const day = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
const tone = { activa: "is-ok", vigente: "is-ok", programada: "is-wait", terminada: "is-off", vencido: "is-off", agotado: "is-off", pausada: "is-off", pausado: "is-off" } as const;
const stateLabel = { activa: "Activa", programada: "Programada", terminada: "Terminada", pausada: "Pausada", vigente: "Vigente", agotado: "Agotado", vencido: "Vencido", pausado: "Pausado" } as const;

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

/** Points, promotions and coupons: the same program the mobile POS applies at checkout. */
export default function LoyaltyBoard({ org, view, currency, today, rate, balances, promotions, coupons, canEditPromos, canSetRate, canRedeem }: {
  org: string; view: "puntos" | "promociones"; currency: string; today: string; rate: number | null;
  balances: LoyaltyRow[]; promotions: Promotion[]; coupons: Coupon[];
  canEditPromos: boolean; canSetRate: boolean; canRedeem: boolean;
}) {
  const money = (v: number) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(v);
  if (view === "puntos") return <>
    <Points org={org} rate={rate} balances={balances} canSetRate={canSetRate} canRedeem={canRedeem} />
    <section className="fv-create fv-cash-card fv-coupons">
      <h3>Cupones</h3>
      <CouponList org={org} coupons={coupons} today={today} money={money} canEdit={canEditPromos} />
      {canEditPromos && <CouponForm org={org} />}
    </section>
  </>;
  const running = promotions.filter(p => promoState(p, today) === "activa").length;
  const live = coupons.filter(c => couponState(c, today) === "vigente").length;
  return <section className="fv-board">
    <div className="fv-kpis">
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Promociones activas</span><strong>{running}</strong><small>se aplican solas en el punto de venta</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Cupones vigentes</span><strong>{live}</strong><small>{coupons.reduce((a, c) => a + c.uses, 0)} usos en total</small></div>
      <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Programadas</span><strong>{promotions.filter(p => promoState(p, today) === "programada").length}</strong><small>empiezan solas en su fecha</small></div>
    </div>
    <div className="fv-cash-grid">
      <section className="fv-create fv-cash-card">
        <h3>Promociones</h3>
        {promotions.length ? <ul className="fv-lines fv-ledger">{promotions.map(p => {
          const s = promoState(p, today);
          return <li key={p.id}><span><b>{p.name}</b> {discountLabel(p.kind, p.value, p.min_qty, money)}{p.starts_on || p.ends_on ? ` · ${p.starts_on ? `desde ${day(p.starts_on)}` : ""}${p.ends_on ? ` hasta ${day(p.ends_on)}` : ""}` : ""}{p.product_ids?.length ? ` · ${p.product_ids.length} productos` : " · toda la tienda"}</span>
            <span><span className={`fv-pill ${tone[s]}`}>{stateLabel[s]}</span>{canEditPromos && <Toggle onToggle={() => togglePromotion(org, p.id, !p.active)} label={p.active ? "Pausar" : "Reanudar"} />}</span></li>;
        })}</ul> : <p className="fv-muted">Sin promociones. Crea la primera: por ejemplo, 10 % menos llevando 3 gaseosas.</p>}
        {canEditPromos && <PromoForm org={org} />}
      </section>
      <section className="fv-create fv-cash-card">
        <h3>Cupones</h3>
        <CouponList org={org} coupons={coupons} today={today} money={money} canEdit={canEditPromos} />
        {canEditPromos && <CouponForm org={org} />}
      </section>
    </div>
  </section>;
}

function CouponList({ org, coupons, today, money, canEdit }: { org: string; coupons: Coupon[]; today: string; money: (v: number) => string; canEdit: boolean }) {
  return coupons.length ? <ul className="fv-lines fv-ledger">{coupons.map(c => {
    const s = couponState(c, today);
    return <li key={c.id}><span><b>{c.code}</b> {discountLabel(c.kind, c.value, null, money)} · {c.uses}{c.max_uses != null ? ` de ${c.max_uses}` : ""} usos{c.expires_on ? ` · vence ${day(c.expires_on)}` : ""}</span>
      <span><span className={`fv-pill ${tone[s]}`}>{stateLabel[s]}</span>{canEdit && <Toggle onToggle={() => toggleCoupon(org, c.id, !c.active)} label={c.active ? "Pausar" : "Reanudar"} />}</span></li>;
  })}</ul> : <p className="fv-muted">Sin cupones. Un código como VECINO10 sirve para premiar a quien vuelve.</p>;
}

function Toggle({ onToggle, label }: { onToggle: () => Promise<FormResult>; label: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  return <button className="fv-link" disabled={pending} onClick={() => start(async () => { const r = await onToggle(); if (r.ok) router.refresh(); })}>{label}</button>;
}

function PromoForm({ org }: { org: string }) {
  const [kind, setKind] = useState("porcentaje");
  const [state, action, pending] = useActionState(savePromotion.bind(null, org), empty);
  const form = useRef<HTMLFormElement>(null);
  useDone(state, () => { form.current?.reset(); setKind("porcentaje"); });
  return <form ref={form} action={action} className="fv-fiado-form">
    <label className="fv-grow"><span>Nombre</span><input name="name" required maxLength={80} placeholder="Gaseosas de verano" /></label>
    <label><span>Tipo</span><select name="kind" value={kind} onChange={e => setKind(e.target.value)}>{Object.entries(promoKinds).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
    <label><span>{kind === "monto" ? "Monto menos" : "% menos"}</span><input name="value" inputMode="decimal" required placeholder={kind === "monto" ? "1.00" : "10"} /></label>
    {kind === "volumen" && <label><span>Desde (unid.)</span><input name="min_qty" inputMode="decimal" required placeholder="3" /></label>}
    <label><span>Desde</span><input type="date" name="starts_on" /></label>
    <label><span>Hasta</span><input type="date" name="ends_on" /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Crear promoción"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}

function CouponForm({ org }: { org: string }) {
  const [state, action, pending] = useActionState(createCoupon.bind(null, org), empty);
  const form = useRef<HTMLFormElement>(null);
  useDone(state, () => form.current?.reset());
  return <form ref={form} action={action} className="fv-fiado-form">
    <label><span>Código</span><input name="code" required maxLength={20} placeholder="VECINO10" style={{ textTransform: "uppercase" }} /></label>
    <label><span>Tipo</span><select name="kind" defaultValue="porcentaje"><option value="porcentaje">% menos</option><option value="monto">Monto menos</option></select></label>
    <label><span>Descuento</span><input name="value" inputMode="decimal" required placeholder="10" /></label>
    <label><span>Usos máx.</span><input name="max_uses" inputMode="numeric" placeholder="Sin límite" /></label>
    <label><span>Vence</span><input type="date" name="expires_on" /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Crear cupón"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}

function Points({ org, rate, balances, canSetRate, canRedeem }: { org: string; rate: number | null; balances: LoyaltyRow[]; canSetRate: boolean; canRedeem: boolean }) {
  const [state, action, pending] = useActionState(setLoyaltyRate.bind(null, org), empty);
  useDone(state);
  const [redeeming, setRedeeming] = useState<string | null>(null);
  const total = balances.reduce((a, b) => a + Math.max(0, b.points), 0);
  return <section className="fv-board">
    <div className="fv-kpis">
      <div style={{ "--tone": rate ? "#3ee6b0" : "#ffb35c" } as React.CSSProperties}><span>Programa de puntos</span><strong>{rate ? `${rate} por sol` : "Apagado"}</strong><small>{rate ? "se suman solos con cada cobro" : "actívalo para premiar a quien vuelve"}</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Clientes con puntos</span><strong>{balances.filter(b => b.points > 0).length}</strong><small>con saldo para canjear</small></div>
      <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Puntos por canjear</span><strong>{total.toLocaleString("es-PE")}</strong><small>en manos de tus clientes</small></div>
    </div>
    {canSetRate && <form action={action} className="fv-create fv-fiado-form">
      <label><span>Puntos por cada sol cobrado</span><input name="rate" inputMode="decimal" defaultValue={rate ?? ""} placeholder="1" /></label>
      <p className="fv-muted fv-grow">0 apaga el programa. Los puntos se suman al registrar el cobro de una venta con cliente identificado, aquí o en el móvil.</p>
      <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar"}</button>
      {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
    </form>}
    {balances.length ? <ul className="fv-lines fv-ledger fv-create">{balances.map(b => <li key={b.client_id}>
      <span><b>{b.client_name}</b>{b.phone ? ` · ${b.phone}` : ""}</span>
      <span>{b.points.toLocaleString("es-PE")} pts{canRedeem && b.points > 0 && <button className="fv-link" onClick={() => setRedeeming(redeeming === b.client_id ? null : b.client_id)}>Canjear</button>}</span>
      {redeeming === b.client_id && <Redeem org={org} row={b} onDone={() => setRedeeming(null)} />}
    </li>)}</ul> : <div className="fv-empty"><h2>Aún nadie tiene puntos</h2><p>Con el programa activo, cada cobro a un cliente identificado le suma puntos.</p></div>}
  </section>;
}

function Redeem({ org, row, onDone }: { org: string; row: LoyaltyRow; onDone: () => void }) {
  const [state, action, pending] = useActionState(redeemPoints.bind(null, org, row.client_id, row.points), empty);
  useDone(state, onDone);
  return <form action={action} className="fv-fiado-form" style={{ gridColumn: "1 / -1" }}>
    <label><span>Puntos a canjear</span><input name="points" inputMode="numeric" required placeholder={String(row.points)} /></label>
    <label className="fv-grow"><span>Premio</span><input name="reason" maxLength={120} placeholder="Gaseosa de regalo" /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Canjeando…" : "Canjear"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}
