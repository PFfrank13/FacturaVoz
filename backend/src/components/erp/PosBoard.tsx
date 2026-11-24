"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { posCheckout, posCoupon, posLookup } from "@/app/erp/actions";
import { addToCart, bestPrice, cartTotals, changeFor, findByCode, priceCart, quickCash, searchProducts, setQuantity, shelfPrice, stockProblems, type CartLine, type PosCoupon, type PosProduct, type PosPromo, type Wholesale } from "@/lib/erp/pos";

type Method = "efectivo" | "yape" | "plin" | "tarjeta" | "transferencia";
const methods: { id: Method; label: string }[] = [
  { id: "efectivo", label: "Efectivo" }, { id: "yape", label: "Yape" }, { id: "plin", label: "Plin" }, { id: "tarjeta", label: "Tarjeta" }, { id: "transferencia", label: "Transferencia" },
];
type Done = { invoice_id: string; charged: number; change: number | null; method: Method };
type Emit = { kind: "03" | "01"; doc: string; name: string; address: string; busy: boolean; msg: string; result: string };

/** Quick sale on the web: scan with the barcode gun (or search), cart, charge and, if wanted, boleta or factura. */
export default function PosBoard({ org, products, extraCodes, currency, taxRate, canEmit, promos = [], pricing = false, today }: {
  org: string; products: PosProduct[]; extraCodes: Record<string, string>; currency: string; taxRate: number; canEmit: boolean; promos?: PosPromo[]; pricing?: boolean; today: string;
}) {
  const sym = currency === "USD" ? "US$" : "S/";
  const fmt = (n: number) => `${sym} ${n.toFixed(2)}`;
  const [q, setQ] = useState("");
  const [cat, setCat] = useState<string | null>(null);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [method, setMethod] = useState<Method>("efectivo");
  const [received, setReceived] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<Done | null>(null);
  const [emit, setEmit] = useState<Emit | null>(null);
  const [flash, setFlash] = useState<string | null>(null);
  const requestId = useRef<string>(crypto.randomUUID());
  const scan = useRef<HTMLInputElement>(null);

  const cats = useMemo(() => [...new Set(products.map(p => p.category).filter((c): c is string => !!c))].sort().slice(0, 14), [products]);
  const list = useMemo(() => searchProducts(q, cat ? products.filter(p => p.category === cat) : products, 48), [q, cat, products]);
  const [coupon, setCoupon] = useState<PosCoupon | null>(null);
  const [couponOpen, setCouponOpen] = useState(false);
  const [couponCode, setCouponCode] = useState("");
  const [couponMsg, setCouponMsg] = useState("");
  const wholesale = useMemo<Wholesale>(() => Object.fromEntries(products.filter(p => p.wholesale_price != null).map(p => [p.id, { price: p.wholesale_price ?? null, min: p.wholesale_min_qty ?? null }])), [products]);
  // Same prices the server charges: best of wholesale / promotions per line, then the coupon.
  const priced = priceCart(cart, promos, today, wholesale, coupon);
  const pricedById = new Map(priced.lines.map(l => [l.product_id, l] as const));
  const totals = cartTotals(priced.lines, taxRate);
  const gross = (net: number) => Math.round(net * (1 + taxRate / 100) * 100) / 100;
  const cash = Number(received.replace(",", "."));
  const change = method === "efectivo" && received ? changeFor(totals.total, cash) : null;
  const problems = stockProblems(cart);

  useEffect(() => { if (!done) scan.current?.focus(); }, [done, cart.length]);

  function add(p: PosProduct, quantity = 1) {
    setCart(c => addToCart(c, p, quantity));
    setFlash(p.id); setTimeout(() => setFlash(f => f === p.id ? null : f), 450);
    setMsg(null);
  }

  /** Enter in the scan box: an exact code (gun or typed) sells it; otherwise the only search result. */
  function onEnter() {
    const code = q.trim();
    if (!code) return;
    const hit = findByCode(code, products, extraCodes);
    if (hit) { add(hit.product, hit.quantity); setQ(""); return; }
    if (list.length === 1) { add(list[0]); setQ(""); return; }
    if (/^\d{6,14}$/.test(code)) setMsg({ ok: false, text: `El código ${code} no está registrado. Agrégalo en Productos → Códigos de barras.` });
  }

  async function charge() {
    if (busy || !cart.length) return;
    if (problems.length) { setMsg({ ok: false, text: `No hay stock suficiente: ${problems.join(" · ")}.` }); return; }
    if (method === "efectivo" && received && change === null) { setMsg({ ok: false, text: "Lo recibido no cubre el total." }); return; }
    setBusy(true); setMsg(null);
    try {
      const r = await posCheckout(org, { request_id: requestId.current, method, items: cart.map(l => ({ product_id: l.product_id, quantity: l.quantity })), coupon: coupon?.code });
      if (!r.ok) { setMsg({ ok: false, text: r.message }); return; }
      setDone({ invoice_id: r.invoice_id, charged: r.charged, change: method === "efectivo" && received ? changeFor(r.charged, cash) : null, method });
    } catch { setMsg({ ok: false, text: "Sin conexión. Vuelve a cobrar: la venta no se duplicará." }); }
    finally { setBusy(false); }
  }

  function next() {
    requestId.current = crypto.randomUUID();
    setCart([]); setReceived(""); setMethod("efectivo"); setDone(null); setEmit(null); setMsg(null); setQ("");
    setCoupon(null); setCouponOpen(false); setCouponCode(""); setCouponMsg("");
  }

  async function applyCoupon() {
    const code = couponCode.trim().toUpperCase();
    if (!code) return;
    setCouponMsg("");
    const r = await posCoupon(org, code).catch(() => ({ ok: false as const, message: "Sin conexión." }));
    if (!r.ok) { setCouponMsg(r.message); return; }
    setCoupon(r.coupon); setCouponOpen(false); setCouponCode("");
  }

  async function lookup() {
    if (!emit) return;
    const digits = emit.doc.replace(/\D/g, "");
    if (digits.length !== 8 && digits.length !== 11) return;
    setEmit({ ...emit, busy: true, msg: "" });
    const r = await posLookup(org, digits).catch(() => null);
    setEmit(e => e && ({ ...e, busy: false, name: r?.ok && r.data ? r.data.name : e.name, address: r?.ok && r.data ? r.data.address : e.address, msg: r?.ok ? "" : (r?.message ?? "No se encontró. Escribe el nombre.") }));
  }

  async function sendSunat() {
    if (!emit || !done || emit.busy) return;
    const digits = emit.doc.replace(/\D/g, "");
    const factura = emit.kind === "01";
    if (factura && digits.length !== 11) { setEmit({ ...emit, msg: "La factura necesita el RUC del cliente (11 dígitos)." }); return; }
    if (factura && !emit.name.trim()) { setEmit({ ...emit, msg: "Escribe la razón social." }); return; }
    if (!factura && totals.total > 700 && digits.length !== 8 && done.charged > 700) { setEmit({ ...emit, msg: "Boletas de más de S/ 700 van con DNI y nombre." }); return; }
    setEmit({ ...emit, busy: true, msg: "" });
    try {
      const { data } = await createClient().auth.getSession();
      const token = data.session?.access_token;
      const res = await fetch("/api/fiscal/emit", {
        method: "POST", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ invoice_id: done.invoice_id, doc_type: emit.kind, afectacion: "gravado", unit: "NIU",
          client_doc_type: factura ? "6" : digits.length === 8 ? "1" : "0", client_doc_number: factura || digits.length === 8 ? digits : "",
          client_name: emit.name.trim() || "Cliente varios", client_address: emit.address.trim() }),
      });
      const j = await res.json().catch(() => ({}));
      if (!res.ok) { setEmit(e => e && ({ ...e, busy: false, msg: j.error ?? "SUNAT no respondió. Puedes reintentar desde Comprobantes." })); return; }
      const number = j.series ? `${j.series}-${String(j.correlative ?? "").padStart(8, "0")}` : "";
      setEmit(e => e && ({ ...e, busy: false, result: j.status === "accepted" || j.status === "aceptado" ? `Aceptada por SUNAT ${number}` : `${number} ${j.message ?? j.status ?? ""}`.trim() }));
    } catch { setEmit(e => e && ({ ...e, busy: false, msg: "Sin conexión. Reintenta desde Comprobantes." })); }
  }

  if (done) return <section className="fv-pos-done" aria-live="polite">
    <div className="fv-pos-check" aria-hidden="true">✓</div>
    <h2>Venta registrada</h2>
    <p className="fv-pos-done-total">{fmt(done.charged)}</p>
    <p className="fv-muted">{methods.find(m => m.id === done.method)?.label}{done.change != null ? ` · Vuelto ${fmt(done.change)}` : ""}</p>
    {canEmit && !emit && <div className="fv-actions" style={{ justifyContent: "center" }}>
      <button className="fv-button secondary" onClick={() => setEmit({ kind: "03", doc: "", name: "", address: "", busy: false, msg: "", result: "" })}>Emitir boleta</button>
      <button className="fv-button secondary" onClick={() => setEmit({ kind: "01", doc: "", name: "", address: "", busy: false, msg: "", result: "" })}>Emitir factura</button>
    </div>}
    {emit && <div className="fv-pos-emit">
      <h3>{emit.kind === "01" ? "Factura" : "Boleta"} electrónica</h3>
      {emit.result ? <p className="fv-ok">{emit.result}</p> : <>
        <div className="fv-two">
          <label className="fv-search"><span>{emit.kind === "01" ? "RUC" : "DNI (opcional)"}</span><input inputMode="numeric" value={emit.doc} maxLength={11} onChange={e => setEmit({ ...emit, doc: e.target.value.replace(/\D/g, "") })} onBlur={() => void lookup()} /></label>
          <label className="fv-search"><span>{emit.kind === "01" ? "Razón social" : "Nombre"}</span><input value={emit.name} maxLength={200} onChange={e => setEmit({ ...emit, name: e.target.value })} placeholder={emit.kind === "01" ? "" : "Cliente varios"} /></label>
        </div>
        <button className="fv-button" disabled={emit.busy} onClick={() => void sendSunat()}>{emit.busy ? "Enviando a SUNAT…" : "Emitir"}</button>
      </>}
      {emit.msg && <p className="fv-error" role="alert">{emit.msg}</p>}
    </div>}
    <button className="fv-button fv-pos-next" autoFocus onClick={next}>Nueva venta</button>
  </section>;

  return <div className="fv-pos">
    <section className="fv-pos-catalog">
      <div className="fv-pos-scan">
        <span aria-hidden="true">▍▌▍▎▌</span>
        <input ref={scan} value={q} onChange={e => { setQ(e.target.value); setMsg(null); }} onKeyDown={e => { if (e.key === "Enter") { e.preventDefault(); onEnter(); } if (e.key === "Escape") setQ(""); }}
          placeholder="Escanea con la pistola o busca por nombre…" aria-label="Escanear código o buscar producto" autoComplete="off" />
      </div>
      {cats.length > 0 && <div className="fv-chips fv-pos-cats">
        <button className="fv-chip" aria-pressed={cat === null} onClick={() => setCat(null)}>Todo</button>
        {cats.map(c => <button key={c} className="fv-chip" aria-pressed={cat === c} onClick={() => setCat(cat === c ? null : c)}>{c}</button>)}
      </div>}
      {msg && !msg.ok && <p className="fv-error" role="alert">{msg.text}</p>}
      {!products.length ? <div className="fv-empty"><h2>Aún no hay productos</h2><p>Créalos en Productos (o en el móvil) y aparecerán aquí para vender.</p></div>
        : !list.length ? <div className="fv-empty"><h2>Sin coincidencias</h2><p>Prueba con otra palabra o escanea el código.</p></div>
        : <div className="fv-pos-grid">{list.map(p => {
          const low = p.stock != null && p.stock <= 0;
          return <button key={p.id} className={`fv-pos-item${flash === p.id ? " is-added" : ""}${low ? " is-out" : ""}`} onClick={() => add(p)} title={p.barcode ?? undefined}>
            <span className="fv-pos-thumb">{p.image_url ? <img src={p.image_url} alt="" /> : <b>{p.name.slice(0, 1).toUpperCase()}</b>}</span>
            <strong>{p.name}</strong>
            {(() => { const b = bestPrice(p.id, p.unit_price, 1, promos, today); return b.reason
              ? <span className="fv-pos-price"><s>{fmt(shelfPrice(p, taxRate))}</s> {fmt(gross(b.price))}{p.unit === "KGM" ? " /kg" : ""}<em className="fv-pos-promo">{b.reason}</em></span>
              : <span className="fv-pos-price">{fmt(shelfPrice(p, taxRate))}{p.unit === "KGM" ? " /kg" : ""}</span>; })()}
            {p.stock != null && <small className={low ? "is-bad" : ""}>{low ? "Sin stock" : `Quedan ${p.stock}`}</small>}
          </button>;
        })}</div>}
    </section>
    <aside className="fv-pos-cart" aria-label="Carrito">
      <header><h2>Venta</h2>{cart.length > 0 && <button className="fv-link" onClick={() => setCart([])}>Vaciar</button>}</header>
      {!cart.length ? <p className="fv-muted fv-pos-empty">Escanea o toca un producto para empezar.</p>
        : <ul className="fv-pos-lines">{cart.map(l => { const pl = pricedById.get(l.product_id); const unit = pl ? gross(pl.unit_price) : shelfPrice(l, taxRate); const off = pl && pl.unit_price < pl.list_price - 0.004; return <li key={l.product_id}>
          <div><strong>{l.name}</strong><small>{off && <s>{fmt(shelfPrice(l, taxRate))}</s>} {fmt(unit)}{l.unit === "KGM" ? " /kg" : " c/u"}</small>{pl?.reason && <em className="fv-pos-promo">{pl.reason}</em>}</div>
          <div className="fv-pos-qty">
            <button aria-label="Uno menos" onClick={() => setCart(c => setQuantity(c, l.product_id, l.unit === "KGM" ? l.quantity - 0.1 : l.quantity - 1))}>−</button>
            <input aria-label={`Cantidad de ${l.name}`} inputMode="decimal" value={l.quantity} onChange={e => { const v = Number(e.target.value.replace(",", ".")); if (Number.isFinite(v)) setCart(c => setQuantity(c, l.product_id, v)); }} />
            <button aria-label="Uno más" onClick={() => setCart(c => setQuantity(c, l.product_id, l.unit === "KGM" ? l.quantity + 0.1 : l.quantity + 1))}>+</button>
          </div>
          <b>{fmt(Math.round(unit * l.quantity * 100) / 100)}</b>
        </li>; })}</ul>}
      {pricing && cart.length > 0 && <div className="fv-pos-coupon">
        {coupon ? <p><span className="fv-pill is-ok">Cupón {coupon.code}</span> <button className="fv-link" onClick={() => setCoupon(null)}>Quitar</button></p>
          : couponOpen ? <form onSubmit={e => { e.preventDefault(); void applyCoupon(); }} className="fv-pos-coupon-form">
              <input aria-label="Código del cupón" value={couponCode} onChange={e => setCouponCode(e.target.value.toUpperCase())} placeholder="Código del cupón" maxLength={40} autoFocus />
              <button className="fv-button secondary">Aplicar</button></form>
          : <button className="fv-link" onClick={() => setCouponOpen(true)}>¿Tiene un cupón?</button>}
        {couponMsg && <p className="fv-error" role="alert">{couponMsg}</p>}
      </div>}
      <div className="fv-pos-sums">
        {priced.promoSaving > 0.004 && <div className="is-saving"><span>Ahorro en promociones</span><span>−{fmt(gross(priced.promoSaving))}</span></div>}
        {priced.couponSaving > 0.004 && <div className="is-saving"><span>Cupón {coupon?.code}</span><span>−{fmt(gross(priced.couponSaving))}</span></div>}
        <div><span>Subtotal</span><span>{fmt(totals.subtotal)}</span></div>
        <div><span>IGV {taxRate}%</span><span>{fmt(totals.tax)}</span></div>
        <div className="is-total"><span>Total</span><span>{fmt(totals.total)}</span></div>
      </div>
      <div className="fv-segment fv-pos-methods" role="group" aria-label="Medio de pago">
        {methods.map(m => <button key={m.id} aria-pressed={method === m.id} onClick={() => setMethod(m.id)}>{m.label}</button>)}
      </div>
      {method === "efectivo" && cart.length > 0 && <div className="fv-pos-cash">
        <label className="fv-search"><span>Recibido</span><input inputMode="decimal" value={received} onChange={e => setReceived(e.target.value)} placeholder={totals.total.toFixed(2)} /></label>
        <div className="fv-chips">{quickCash(totals.total).map(v => <button key={v} className="fv-chip" onClick={() => setReceived(v.toFixed(2))}>{fmt(v)}</button>)}</div>
        {change != null && <p className="fv-pos-change">Vuelto <b>{fmt(change)}</b></p>}
      </div>}
      {problems.length > 0 && <p className="fv-error">Sin stock suficiente: {problems.join(" · ")}</p>}
      <button className="fv-button fv-pos-pay" disabled={!cart.length || busy} onClick={() => void charge()}>{busy ? "Cobrando…" : `Cobrar ${fmt(totals.total)}`}</button>
      {msg?.ok === false && cart.length > 0 && <p className="fv-error" role="alert">{msg.text}</p>}
    </aside>
  </div>;
}
