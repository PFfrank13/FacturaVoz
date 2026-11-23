"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useRouter } from "next/navigation";
import { receivePurchase, settlePurchase } from "@/app/erp/actions";
import { isPending, lineCents, paymentLabel, purchaseCents, purchaseProblem, summarizePurchases, supplierSuggestions, type OrderSuggestion, type PurchaseLine, type PurchaseRow } from "@/lib/erp/purchases";

export type PurchaseProduct = { id: string; name: string; unit: string; unit_cost: number | null; stock: number | null };

const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const day = (iso: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "America/Lima" }).format(new Date(iso));
const qty = (q: number) => (Number.isInteger(q) ? String(q) : q.toFixed(2));
const newId = () => crypto.randomUUID();

/** Supplier purchases shared with the mobile «Compras y recepción»: receiving updates stock, cost and the till. */
export default function PurchasesBoard({ org, rows, products, currency, month, suggestions = [] }: { org: string; rows: PurchaseRow[]; products: PurchaseProduct[]; currency: string; month: string; suggestions?: OrderSuggestion[] }) {
  const [q, setQ] = useState("");
  const [onlyPending, setOnlyPending] = useState(false);
  const [openId, setOpenId] = useState<string | "new" | null>(null);
  const [preset, setPreset] = useState<{ supplier: string; lines: OrderSuggestion[] } | null>(null);
  const s = summarizePurchases(rows, month);
  const visible = useMemo(() => rows.filter(r => (!onlyPending || isPending(r)) && (!q.trim() || `${r.supplier_name} ${r.document_ref ?? ""} ${r.items.map(i => i.name).join(" ")}`.toLocaleLowerCase("es").includes(q.trim().toLocaleLowerCase("es")))), [rows, q, onlyPending]);
  const open = openId && openId !== "new" ? rows.find(r => r.id === openId) ?? null : null;
  return <section className="fv-board">
    <div className="fv-kpis">
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Compras del mes</span><strong>{fmt(s.month, currency)}</strong><small>mercadería recibida</small></div>
      <div style={{ "--tone": s.payableCount ? "#ffb35c" : "#3ee6b0" } as React.CSSProperties}><span>Por pagar a proveedores</span><strong>{fmt(s.payable, currency)}</strong><small>{s.payableCount} {s.payableCount === 1 ? "compra pendiente" : "compras pendientes"}</small></div>
      <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Por reponer</span><strong>{suggestions.length ? `${suggestions.length} ${suggestions.length === 1 ? "producto" : "productos"}` : "Nada urgente"}</strong><small>según lo que vendes y tu mínimo</small></div>
    </div>
    {suggestions.length > 0 && <SuggestedOrder suggestions={suggestions} currency={currency} onUse={(supplier, lines) => { setPreset({ supplier, lines }); setOpenId("new"); }} />}
    <div className="fv-board-tools">
      <label className="fv-search"><span>Buscar</span><input type="search" value={q} onChange={e => setQ(e.target.value)} placeholder="Proveedor, comprobante o producto…" /></label>
      <div className="fv-segment" role="group" aria-label="Filtrar compras">
        <button aria-pressed={!onlyPending} onClick={() => setOnlyPending(false)}>Todas</button>
        <button aria-pressed={onlyPending} onClick={() => setOnlyPending(true)}>Por pagar</button>
      </div>
      <button className="fv-button" disabled={!products.length} onClick={() => { setPreset(null); setOpenId("new"); }}>Registrar compra</button>
    </div>
    <p className="fv-caption" aria-live="polite">{visible.length} {visible.length === 1 ? "compra" : "compras"}</p>
    <ul className="fv-receipts">
      {visible.map((r, i) => <li key={r.id} style={{ "--i": Math.min(i, 14) } as React.CSSProperties}>
        <button onClick={() => setOpenId(r.id)} aria-label={`${r.supplier_name}, ${fmt(r.total_cents / 100, currency)}, ${isPending(r) ? "por pagar" : "pagada"}`}>
          <span className="fv-avatar" aria-hidden="true">{r.supplier_name.slice(0, 2).toUpperCase()}</span>
          <span className="fv-receipt-main"><strong>{r.supplier_name}</strong><small>{[r.document_ref, `${r.items.length} ${r.items.length === 1 ? "producto" : "productos"}`].filter(Boolean).join(" · ")}</small></span>
          <span className="fv-receipt-date">{day(r.created_at)}</span>
          <span className={`fv-pill ${isPending(r) ? "is-wait" : "is-ok"}`}>{isPending(r) ? "Por pagar" : "Pagada"}</span>
          <span className="fv-receipt-total">{fmt(r.total_cents / 100, currency)}</span>
        </button>
      </li>)}
    </ul>
    {!visible.length && <div className="fv-empty"><h2>{q || onlyPending ? "Sin coincidencias" : "Todavía no hay compras"}</h2>
      <p>{products.length ? "Registra lo que te llega del proveedor: el stock y el costo se actualizan solos, también en el móvil." : "Primero crea tus productos (por unidad o por kilo) en «Productos y servicios»."}</p></div>}
    {openId === "new" && <NewPurchase org={org} products={products} suppliers={supplierSuggestions(rows)} currency={currency} preset={preset} onClose={() => setOpenId(null)} onDone={id => setOpenId(id)} />}
    {open && <PurchaseSheet key={open.id} org={org} row={open} currency={currency} onClose={() => setOpenId(null)} />}
    {openId && openId !== "new" && !open && <Sheet title="Compra recibida" kicker="Actualizando…" onClose={() => setOpenId(null)}><div className="fv-skeleton" aria-label="Cargando la compra"><i /><i /><i /></div></Sheet>}
  </section>;
}

/** What to reorder, grouped by the supplier each product was last bought from. */
function SuggestedOrder({ suggestions, currency, onUse }: { suggestions: OrderSuggestion[]; currency: string; onUse: (supplier: string, lines: OrderSuggestion[]) => void }) {
  const groups = new Map<string, OrderSuggestion[]>();
  for (const s of suggestions) groups.set(s.supplier, [...(groups.get(s.supplier) ?? []), s]);
  return <section className="fv-reorder" aria-labelledby="fv-reorder-title">
    <h2 id="fv-reorder-title">Pedido sugerido</h2>
    <p className="fv-muted">Calculado con lo que vendiste en los últimos 30 días para cubrir dos semanas, y con el mínimo de cada producto. Revísalo antes de pedir.</p>
    <div className="fv-reorder-groups">{[...groups.entries()].map(([supplier, lines]) => {
      const total = lines.reduce((a, l) => a + (l.unit_cost ?? 0) * l.quantity, 0);
      return <article key={supplier || "-"} className="fv-reorder-card">
        <header><strong>{supplier || "Sin proveedor anterior"}</strong>{total > 0 && <span>≈ {fmt(total, currency)}</span>}</header>
        <ul>{lines.slice(0, 8).map(l => <li key={l.product_id}><span>{l.name}</span><small>{l.cover_days === null ? `stock ${qty(l.stock)}` : l.cover_days === 0 ? "se acaba hoy" : `alcanza ${l.cover_days} ${l.cover_days === 1 ? "día" : "días"}`}</small><b>{l.quantity}</b></li>)}</ul>
        {lines.length > 8 && <p className="fv-caption">y {lines.length - 8} más</p>}
        <button className="fv-button secondary" onClick={() => onUse(supplier, lines.slice(0, 50))}>Registrar esta compra</button>
      </article>;
    })}</div>
  </section>;
}

function Sheet({ title, kicker, onClose, children }: { title: string; kicker: string; onClose: () => void; children: React.ReactNode }) {
  const panel = useRef<HTMLDivElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    panel.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") close.current(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  const root = typeof document === "undefined" ? null : document.querySelector(".fv-workspace");
  const sheet = <div className="fv-sheet-layer" onClick={onClose}>
    <div ref={panel} tabIndex={-1} className="fv-sheet fv-client-sheet" role="dialog" aria-modal="true" aria-labelledby="fv-sheet-title" onClick={e => e.stopPropagation()}>
      <header><div><small>{kicker}</small><h2 id="fv-sheet-title">{title}</h2></div><button className="fv-icon-button" onClick={onClose} aria-label="Cerrar">✕</button></header>
      {children}
    </div>
  </div>;
  return root ? createPortal(sheet, root) : sheet;
}

type Draft = { key: string; product_id: string; quantity: string; unit_cost: string; expires_on: string };

function NewPurchase({ org, products, suppliers, currency, preset, onClose, onDone }: { org: string; products: PurchaseProduct[]; suppliers: string[]; currency: string; preset: { supplier: string; lines: OrderSuggestion[] } | null; onClose: () => void; onDone: (id: string) => void }) {
  const router = useRouter();
  const requestId = useRef(newId()); // same id on retries: the database never receives it twice
  const [supplier, setSupplier] = useState(preset?.supplier ?? "");
  const [reference, setReference] = useState("");
  const [method, setMethod] = useState("pendiente");
  const [drafts, setDrafts] = useState<Draft[]>(() => preset?.lines.length
    ? preset.lines.map(l => ({ key: newId(), product_id: l.product_id, quantity: String(l.quantity), unit_cost: l.unit_cost == null ? "" : String(l.unit_cost), expires_on: "" }))
    : [{ key: newId(), product_id: "", quantity: "1", unit_cost: "", expires_on: "" }]);
  const [state, setState] = useState<{ busy: boolean; error: string }>({ busy: false, error: "" });
  const byId = useMemo(() => new Map(products.map(p => [p.id, p])), [products]);
  const lines: PurchaseLine[] = drafts.map(d => ({ product_id: d.product_id, quantity: Number(d.quantity.replace(",", ".")), unit_cost: Number(d.unit_cost.replace(",", ".")), expires_on: d.expires_on }));
  const total = purchaseCents(lines.filter(l => l.quantity > 0 && l.unit_cost >= 0)) / 100;
  const set = (key: string, patch: Partial<Draft>) => setDrafts(ds => ds.map(d => d.key === key ? { ...d, ...patch } : d));
  const pick = (key: string, id: string) => {
    const p = byId.get(id);
    set(key, { product_id: id, unit_cost: p?.unit_cost ? String(p.unit_cost) : "" });
  };

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (state.busy) return;
    const problem = purchaseProblem(supplier, reference, lines);
    if (problem) return setState({ busy: false, error: problem });
    setState({ busy: true, error: "" });
    const r = await receivePurchase(org, { request_id: requestId.current, supplier, reference, payment_method: method, lines }).catch(() => null);
    if (!r?.ok || !r.id) return setState({ busy: false, error: r?.message ?? "Sin conexión. Vuelve a intentarlo: no se duplicará." });
    router.refresh();
    onDone(r.id);
  }

  return <Sheet title="Registrar compra" kicker="Mercadería que llegó" onClose={onClose}>
    <form className="fv-form fv-client-form" onSubmit={submit}>
      <div className="fv-form-row">
        <label><span>Proveedor</span><input list="fv-suppliers" required maxLength={120} value={supplier} onChange={e => setSupplier(e.target.value)} placeholder="Distribuidora, mayorista…" /></label>
        <label><span>Comprobante del proveedor</span><input maxLength={40} value={reference} onChange={e => setReference(e.target.value)} placeholder="F001-123 (opcional)" /></label>
      </div>
      <datalist id="fv-suppliers">{suppliers.map(s => <option key={s} value={s} />)}</datalist>
      <div className="fv-draft-lines" role="group" aria-label="Productos recibidos">
        <div className="fv-draft-head fv-buy-head" aria-hidden="true"><span>Producto</span><span>Cant.</span><span>Costo unit.</span><span>Importe</span><span /></div>
        {drafts.map((d, i) => {
          const p = byId.get(d.product_id);
          const l = lines[i];
          return <div key={d.key} className="fv-draft-line fv-buy-line">
            <select aria-label={`Producto de la línea ${i + 1}`} value={d.product_id} onChange={e => pick(d.key, e.target.value)}>
              <option value="">Elige un producto…</option>
              {products.map(o => <option key={o.id} value={o.id} disabled={o.id !== d.product_id && drafts.some(x => x.product_id === o.id)}>{o.name}</option>)}
            </select>
            <input aria-label={`Cantidad de la línea ${i + 1}`} inputMode="decimal" value={d.quantity} onChange={e => set(d.key, { quantity: e.target.value })} />
            <input aria-label={`Costo unitario de la línea ${i + 1}`} inputMode="decimal" value={d.unit_cost} placeholder="0.00" onChange={e => set(d.key, { unit_cost: e.target.value })} />
            <span className="fv-draft-amount">{l.quantity > 0 && l.unit_cost >= 0 ? fmt(lineCents(l) / 100, currency) : "—"}</span>
            <button type="button" className="fv-icon-button" disabled={drafts.length === 1} aria-label={`Quitar línea ${i + 1}`} onClick={() => setDrafts(ds => ds.filter(x => x.key !== d.key))}>−</button>
            {p && <small className="fv-buy-hint">Stock {qty(Number(p.stock ?? 0))} → {qty(Number(p.stock ?? 0) + (l.quantity > 0 ? l.quantity : 0))} {p.unit === "KGM" ? "kg" : "u."}{p.unit_cost ? ` · último costo ${fmt(Number(p.unit_cost), currency)}` : ""}</small>}
            {p && <label className="fv-buy-expiry"><span>Vence</span><input type="date" value={d.expires_on} aria-label={`Fecha de vencimiento de la línea ${i + 1} (opcional)`} onChange={e => set(d.key, { expires_on: e.target.value })} /><small>opcional: activa la alerta antes de que venza</small></label>}
          </div>;
        })}
      </div>
      <div className="fv-draft-foot">
        <button type="button" className="fv-button secondary" disabled={drafts.length >= 50} onClick={() => setDrafts(ds => [...ds, { key: newId(), product_id: "", quantity: "1", unit_cost: "", expires_on: "" }])}>Añadir producto</button>
        <label className="fv-search fv-narrow"><span>Pago</span>
          <select value={method} onChange={e => setMethod(e.target.value)}>{Object.entries(paymentLabel).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
        </label>
        <dl className="fv-sums"><div className="is-total"><dt>Total</dt><dd>{fmt(total, currency)}</dd></div></dl>
      </div>
      {method === "efectivo" && <p className="fv-hint">Se registrará un retiro de caja de hoy por el total.</p>}
      {state.error && <p className="fv-error" role="alert">{state.error}</p>}
      <div className="fv-actions">
        <button className="fv-button" disabled={state.busy}>{state.busy ? "Recibiendo…" : "Recibir mercadería"}</button>
        <button type="button" className="fv-button secondary" onClick={onClose}>Cancelar</button>
      </div>
    </form>
  </Sheet>;
}

function PurchaseSheet({ org, row, currency, onClose }: { org: string; row: PurchaseRow; currency: string; onClose: () => void }) {
  const router = useRouter();
  const requestId = useRef(newId());
  const [method, setMethod] = useState("efectivo");
  const [evidence, setEvidence] = useState("");
  const [state, setState] = useState<{ busy: boolean; ok: boolean; message: string }>({ busy: false, ok: false, message: "" });
  async function pay() {
    if (state.busy) return;
    setState({ busy: true, ok: false, message: "" });
    const r = await settlePurchase(org, { receipt: row.id, request_id: requestId.current, method, evidence }).catch(() => null);
    setState({ busy: false, ok: !!r?.ok, message: r?.message ?? "Sin conexión. Vuelve a intentarlo: no se duplicará." });
    if (r?.ok) router.refresh();
  }
  return <Sheet title={row.supplier_name} kicker={`Compra del ${day(row.created_at)}${row.document_ref ? ` · ${row.document_ref}` : ""}`} onClose={onClose}>
    <div className={`fv-sunat ${isPending(row) ? "is-wait" : "is-ok"}`}>
      <strong>{isPending(row) ? `Por pagar ${fmt(row.total_cents / 100, currency)}` : "Pagada"}</strong>
      <span>{row.paid ? `${paymentLabel[row.paid.method] ?? row.paid.method} el ${day(row.paid.created_at)}` : row.payment_method !== "pendiente" ? `Pagada al recibir: ${paymentLabel[row.payment_method] ?? row.payment_method}` : "Registra el pago cuando le pagues al proveedor."}</span>
    </div>
    <ul className="fv-lines">{row.items.map(it => <li key={it.product_id}>
      <span>{qty(it.quantity)} × {it.name}<small className="fv-buy-hint"> · stock {qty(it.stock_before)} → {qty(it.stock_after)} · {fmt(it.unit_cost_cents / 100, currency)} c/u</small></span>
      <span>{fmt(it.line_total_cents / 100, currency)}</span>
    </li>)}</ul>
    <dl className="fv-sums"><div className="is-total"><dt>Total</dt><dd>{fmt(row.total_cents / 100, currency)}</dd></div></dl>
    {isPending(row) && !state.ok && <div className="fv-fiado-form">
      <label><span>Pagar con</span><select value={method} onChange={e => setMethod(e.target.value)}>{["efectivo", "yape", "plin", "transferencia", "tarjeta"].map(k => <option key={k} value={k}>{paymentLabel[k]}</option>)}</select></label>
      <label className="fv-grow"><span>Referencia</span><input maxLength={200} value={evidence} onChange={e => setEvidence(e.target.value)} placeholder="N.° de operación (opcional)" /></label>
      <button className="fv-button" disabled={state.busy} onClick={pay}>{state.busy ? "Pagando…" : "Registrar pago"}</button>
    </div>}
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </Sheet>;
}
