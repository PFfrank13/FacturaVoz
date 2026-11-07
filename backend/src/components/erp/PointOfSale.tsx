"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { checkout, type CheckoutResult } from "@/app/erp/checkout";
import { money } from "@/lib/schemas";

export type SaleProduct = { id: string; name: string; unit_price: number };
import { cents, scaled, ticketTotals } from "@/lib/retail/money";
import { TicketStore } from "@/lib/retail/ticket-store";
export default function PointOfSale({ org, userId, products, currency, taxRate, canCollect, canEdit }: {
  org: string; userId: string; products: SaleProduct[]; currency: string; taxRate: number; canCollect: boolean; canEdit: boolean;
}) {
  const [query, setQuery] = useState("");
  const [cart, setCart] = useState<Record<string, number>>({});
  const [method, setMethod] = useState("efectivo");
  const [received, setReceived] = useState("");
  const [review, setReview] = useState(false);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<CheckoutResult | null>(null);
  const request = useRef<string | null>(null);
  const frozenProducts = useRef<SaleProduct[] | null>(null);
  const running = useRef(false);
  const frozenTerms = useRef<{ currency: string; taxBasisPoints: number } | null>(null);
  const store = useRef<TicketStore | null>(null);
  const revision = useRef(0);
  const [loaded, setLoaded] = useState(false);
  const [storageError, setStorageError] = useState("");
  const [savedAt, setSavedAt] = useState("");
  const locked = busy || request.current !== null || !loaded || !!storageError;
  const catalogue = frozenProducts.current ?? products;
  const items = catalogue.filter(p => cart[p.id] > 0);
  const ticketCurrency = frozenTerms.current?.currency ?? currency;
  const ticketTax = frozenTerms.current?.taxBasisPoints ?? cents(taxRate);
  const termsChanged = ticketCurrency !== currency || ticketTax !== cents(taxRate);
  const totals = ticketTotals(items.map(p => ({ unitPriceCents: cents(p.unit_price), quantityMilli: scaled(cart[p.id], 3) })), ticketTax);
  const { subtotal, tax } = totals;
  const total = totals.total / 100;
  let cashCents: number | null = null;
  try { cashCents = cents(received); } catch { /* incomplete input is not an amount */ }
  const priceChanged = termsChanged || items.some(p => products.find(current => current.id === p.id)?.unit_price !== p.unit_price);
  useEffect(() => {
    let cancelled = false;
    let release: (() => void) | undefined;
    if (!navigator.locks) {
      setStorageError("Este navegador no permite proteger el ticket entre pestañas. Abre el POS en un navegador actualizado.");
      return;
    }
    // Defer acquisition past React's setup/cleanup replay. A cancelled setup
    // must not briefly hold the lock and reject the replacement setup.
    void Promise.resolve().then(() => {
      if (cancelled) return;
      return navigator.locks.request(`retail-ticket:${org}:${userId}`, { ifAvailable: true }, async lock => {
      if (cancelled) return;
      if (!lock) { setStorageError("Este ticket está abierto en otra pestaña. Ciérrala y recarga para continuar aquí."); return; }
      try {
        const local = new TicketStore(window.localStorage, org, userId);
        const saved = local.read(); store.current = local;
        revision.current = saved?.revision ?? 0;
        if (saved) {
          frozenTerms.current = { currency: saved.currency, taxBasisPoints: saved.taxBasisPoints };
          const restored = saved.lines.map(l => ({ id: l.id, name: l.name, unit_price: l.unitPriceCents / 100 }));
          frozenProducts.current = [...restored, ...products.filter(p => !restored.some(r => r.id === p.id))];
          setCart(Object.fromEntries(saved.lines.map(l => [l.id, l.quantityMilli / 1000])));
          setMethod(saved.method); request.current = saved.operationId;
          setReview(!!saved.operationId); setSavedAt(saved.savedAt);
        }
        setLoaded(true);
        await new Promise<void>(resolve => { release = resolve; });
      } catch { if (!cancelled) setStorageError("No pudimos recuperar el ticket local. No lo sobrescribiremos. Revisa el almacenamiento del navegador."); }
      });
    }).catch(() => { if (!cancelled) setStorageError("No se pudo proteger el guardado del ticket. Recarga para reintentar."); });
    return () => { cancelled = true; release?.(); };
    // A tenant/user change remounts the POS; catalogue refresh must not restore over current edits.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [org, userId]);
  function persist() {
    if (!store.current) throw new Error("Almacenamiento no disponible");
    const saved = store.current.save({ operationId: request.current, currency: ticketCurrency, taxBasisPoints: ticketTax,
      method: method as "efectivo" | "yape" | "plin" | "tarjeta" | "transferencia",
      lines: items.map(p => ({ id: p.id, name: p.name, unitPriceCents: cents(p.unit_price), quantityMilli: scaled(cart[p.id], 3) })),
    }, revision.current);
    revision.current = saved.revision; setSavedAt(saved.savedAt);
  }
  useEffect(() => {
    if (!loaded || storageError) return;
    try { persist(); }
    catch (e) { setStorageError(e instanceof Error ? e.message : "No se pudo guardar el ticket local."); }
    // Persist user edits only; server catalogue changes never silently reprice a draft.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cart, method, loaded]);
  function change(id: string, amount: number) {
    if (locked) return;
    // Capture commercial terms on the first edit, before a server refresh can
    // change an in-progress ticket. New terms require explicit review below.
    frozenProducts.current ??= products.map(p => ({ ...p }));
    frozenTerms.current ??= { currency, taxBasisPoints: cents(taxRate) };
    const addedProduct = products.find(p => p.id === id);
    if (addedProduct && !frozenProducts.current.some(p => p.id === id)) {
      frozenProducts.current = [...frozenProducts.current, { ...addedProduct }];
    }
    setCart(c => ({ ...c, [id]: Math.max(0, Math.min(100000, (c[id] || 0) + amount)) }));
    setResult(null);
  }
  async function confirm() {
    if (running.current || !items.length || !canCollect || !loaded || storageError || (!request.current && priceChanged)) return;
    running.current = true; setBusy(true);
    frozenTerms.current ??= { currency: ticketCurrency, taxBasisPoints: ticketTax };
    frozenProducts.current ??= products.map(p => ({ ...p }));
    request.current ??= crypto.randomUUID();
    try {
      try { persist(); } catch (e) { setStorageError(e instanceof Error ? e.message : "No se pudo guardar el ticket."); return; }
      const response = await checkout(org, { requestId: request.current, method, currency: ticketCurrency, taxBasisPoints: ticketTax,
        items: items.map(p => ({ product_id: p.id, quantity: cart[p.id], unit_price: p.unit_price })) });
      setResult(response);
      if (!response.ok && !response.uncertain) { request.current = null; persist(); }
      if (response.ok) { setCart({}); request.current = null; frozenProducts.current = null; frozenTerms.current = null; setReview(false); setReceived(""); }
    } catch {
      setResult({ ok: false, message: "No recibimos confirmación. Conserva esta página y reintenta el mismo cobro." });
    } finally { running.current = false; setBusy(false); }
  }
  return <div className="fv-pos">
    <section aria-label="Catálogo para vender">
      <p className="sr-draft-state" role="status">{storageError || (!loaded ? "Recuperando ticket…" : request.current ? "Cobro pendiente de confirmación · Reintenta la misma operación" : savedAt ? "Borrador guardado en este navegador · No es una venta confirmada" : "Preparando guardado local")}</p>
      <label className="fv-pos-search">Buscar producto<input value={query} onChange={e => setQuery(e.target.value)} placeholder="Nombre del producto" /></label>
      {!products.length && <div className="fv-empty"><h2>Todavía no tienes productos</h2><p>Agrega el primero para comenzar a vender.</p>{canEdit && <Link className="fv-button" href={`/erp/${org}/productos`}>Agregar productos</Link>}</div>}
      <div className="fv-pos-products">{products.filter(p => p.name.toLocaleLowerCase().includes(query.toLocaleLowerCase())).map(p =>
        <button key={p.id} disabled={locked || (items.length >= 50 && !cart[p.id])} onClick={() => change(p.id, 1)}><span>{p.name}</span><strong>{money(p.unit_price, ticketCurrency)}</strong><small>Agregar{cart[p.id] ? ` · ${cart[p.id]} en carrito` : ""}</small></button>)}</div>
      <p>Precios antes del impuesto del ticket ({ticketTax / 100} %). Catálogo: hasta 500 productos.</p>
    </section>
    <section className="fv-pos-cart" aria-label="Venta actual">
      <h2>Ticket actual</h2>
      {priceChanged && !request.current && <div role="alert"><p>Cambió el precio, la disponibilidad, la moneda o el impuesto. El ticket conserva el precio anterior hasta que lo revises.</p><button className="fv-button secondary" disabled={locked} onClick={() => {
        frozenProducts.current = products.map(p => ({ ...p }));
        frozenTerms.current = { currency, taxBasisPoints: cents(taxRate) };
        setCart(c => Object.fromEntries(Object.entries(c).filter(([id]) => products.some(p => p.id === id))));
      }}>Revisar y usar catálogo actual</button></div>}
      {!items.length && <p>Selecciona productos para comenzar.</p>}
      {items.map(p => <div className="fv-pos-line" key={p.id}><span>{p.name}<strong>{money(ticketTotals([{ unitPriceCents: cents(p.unit_price), quantityMilli: scaled(cart[p.id], 3) }], 0).total / 100, ticketCurrency)}</strong></span><div>
        <button aria-label={`Quitar uno de ${p.name}`} disabled={locked} onClick={() => change(p.id, -1)}>−</button>
        <output aria-label={`Cantidad de ${p.name}`}>{cart[p.id]}</output>
        <button aria-label={`Agregar uno de ${p.name}`} disabled={locked} onClick={() => change(p.id, 1)}>+</button></div></div>)}
      <dl className="fv-details"><dt>Subtotal</dt><dd>{money(subtotal / 100, ticketCurrency)}</dd><dt>Impuesto</dt><dd>{money(tax / 100, ticketCurrency)}</dd><dt>Total</dt><dd aria-live="polite">{money(total, ticketCurrency)}</dd></dl>
      {!canCollect && <p>Tu rol permite preparar ventas, pero no registrar cobros.</p>}
      {!!items.length && canCollect && <>
        {!review ? <button className="fv-button" disabled={locked || priceChanged} onClick={() => setReview(true)}>Cobrar · {money(total, ticketCurrency)}</button> : <div className="fv-pos-payment">
          <label>Medio de pago<select disabled={locked} value={method} onChange={e => setMethod(e.target.value)}>{["efectivo", "yape", "plin", "tarjeta", "transferencia"].map(m => <option key={m} value={m}>{m}</option>)}</select></label>
          {method === "efectivo" && !request.current && <><label>Efectivo recibido<input inputMode="decimal" disabled={locked} value={received} onChange={e => setReceived(e.target.value)} /></label><p>{cashCents !== null && cashCents >= totals.total ? `Vuelto: ${money((cashCents - totals.total) / 100, ticketCurrency)}` : "Ingresa un importe igual o mayor al total."}</p></>}
          {request.current && <p>Recuperaremos el cobro original. No vuelvas a recibir el pago del cliente.</p>}
          {method !== "efectivo" && !request.current && <p>Confirma que recibiste el pago. No se verifica automáticamente con el banco.</p>}
          <button className="fv-button" disabled={busy || !!storageError || !loaded || total <= 0 || (!request.current && (priceChanged || (method === "efectivo" && (cashCents === null || cashCents < totals.total))))} onClick={confirm}>{busy ? "Confirmando…" : request.current ? "Reintentar mismo cobro" : "Confirmar cobro"}</button>
          {!locked && <button className="fv-button secondary" onClick={() => setReview(false)}>Volver al carrito</button>}
        </div>}
      </>}
      {result && <div role={result.ok ? "status" : "alert"}><p>{result.message}</p>{result.ok && <><p>Operación: {result.invoiceId} · {money(result.charged ?? 0, ticketCurrency)}</p><Link href={`/erp/${org}/comprobantes`}>Consultar historial</Link><p>El registro de venta no confirma emisión electrónica ante SUNAT.</p></>}</div>}
    </section>
  </div>;
}
