"use client";
import { useActionState, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { addProductCode, getKardex, getProductCodes, removeProductCode, updateProduct, uploadProductPhoto, type FormResult } from "@/app/erp/actions";
import { kardexTotals, type KardexEntry } from "@/lib/erp/kardex";
import { ProductLots } from "@/components/erp/LotsAndLosses";

export type ProductRow = {
  id: string; name: string; unit_price: number | string; unit: string; active: boolean;
  category: string | null; stock: number | string | null; reorder_point: number | string | null; unit_cost: number | string | null;
  image_path: string | null; photo_url: string | null; icbper?: boolean | null;
  sku?: string | null; barcode?: string | null; description?: string | null; wholesale_price?: number | string | null; wholesale_min_qty?: number | string | null; in_store?: boolean | null;
};

const empty: FormResult = { ok: false, message: "" };
const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const initials = (name: string) => name.trim().split(/\s+/).slice(0, 2).map(w => w[0]?.toUpperCase() ?? "").join("");

/** Catalog administration: the same rows the mobile POS sells from. */
type Filter = "todos" | "bajo" | "agotados" | "sincosto" | "sincodigo" | "inactivos";
const filterLabel: Record<Filter, string> = { todos: "Todos", bajo: "Stock bajo", agotados: "Agotados", sincosto: "Sin costo", sincodigo: "Sin código", inactivos: "Inactivos" };

export default function ProductBoard({ org, rows, currency, canEdit, canKardex = false, canLots = false, taxRate = 18 }: { org: string; rows: ProductRow[]; currency: string; canEdit: boolean; canKardex?: boolean; canLots?: boolean; taxRate?: number }) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Filter>("todos");
  const [cat, setCat] = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const gross = (net: number | string) => Math.round(Number(net) * (1 + taxRate / 100) * 100) / 100;
  const low = (p: ProductRow) => p.stock != null && p.reorder_point != null && Number(p.stock) <= Number(p.reorder_point);
  const test: Record<Filter, (p: ProductRow) => boolean> = { todos: () => true, bajo: low, agotados: p => p.stock != null && Number(p.stock) <= 0, sincosto: p => p.unit !== "ZZ" && p.unit_cost == null,
    sincodigo: p => p.unit !== "ZZ" && !p.barcode, inactivos: p => !p.active };
  const cats = useMemo(() => [...new Set(rows.map(p => p.category).filter((x): x is string => !!x))].sort((a, b) => a.localeCompare(b, "es")), [rows]);
  const visible = useMemo(() => rows.filter(p => test[filter](p) && (!cat || p.category === cat) &&
    `${p.name} ${p.category ?? ""} ${p.sku ?? ""} ${p.barcode ?? ""}`.toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))), // eslint-disable-next-line react-hooks/exhaustive-deps
  [rows, filter, query, cat]);
  const tracked = rows.filter(p => p.active && p.stock != null);
  const atCost = tracked.reduce((s, p) => s + Math.max(0, Number(p.stock)) * Number(p.unit_cost ?? 0), 0);
  const atPrice = tracked.reduce((s, p) => s + Math.max(0, Number(p.stock)) * gross(p.unit_price), 0);
  function exportCsv() {
    const head = ["Producto", "Categoría", "Código", "SKU", "Unidad", "Precio con IGV", "Precio sin IGV", "Costo", "Stock", "Mínimo", "Valor al costo", "Activo"];
    const q = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const lines = rows.map(p => [p.name, p.category, p.barcode, p.sku, p.unit === "KGM" ? "kg" : p.unit === "ZZ" ? "servicio" : "unidad", gross(p.unit_price).toFixed(2), Number(p.unit_price).toFixed(2),
      p.unit_cost == null ? "" : Number(p.unit_cost).toFixed(2), p.stock ?? "", p.reorder_point ?? "", p.stock == null || p.unit_cost == null ? "" : (Math.max(0, Number(p.stock)) * Number(p.unit_cost)).toFixed(2), p.active ? "sí" : "no"].map(q).join(";"));
    const blob = new Blob(["\uFEFF" + [head.map(q).join(";"), ...lines].join("\r\n")], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `inventario-${new Date().toISOString().slice(0, 10)}.csv`; a.click(); URL.revokeObjectURL(a.href);
  }
  const open = rows.find(p => p.id === openId) ?? null;
  return <section className="fv-board">
    {canLots && <div className="fv-kpis fv-kpis-4">
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Inventario al costo</span><strong>{fmt(atCost, currency)}</strong><small>{tracked.length} productos con stock controlado</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>A precio de venta</span><strong>{fmt(atPrice, currency)}</strong><small>ganancia potencial {fmt(Math.max(0, atPrice / (1 + taxRate / 100) - atCost), currency)}</small></div>
      <div style={{ "--tone": "#ff8aa8" } as React.CSSProperties}><span>Agotados / bajo mínimo</span><strong>{rows.filter(test.agotados).length} / {rows.filter(low).length}</strong><small>repón antes de perder ventas</small></div>
      <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Fichas incompletas</span><strong>{rows.filter(p => test.sincosto(p) || test.sincodigo(p)).length}</strong><small>sin costo o sin código de barras</small></div>
    </div>}
    <div className="fv-board-tools">
      <label className="fv-search"><span>Buscar producto</span><input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Nombre, categoría, código o SKU…" /></label>
      <div className="fv-chips" role="group" aria-label="Filtrar productos">
        {(Object.keys(filterLabel) as Filter[]).map(f => <button key={f} className="fv-chip" aria-pressed={filter === f} onClick={() => setFilter(f)}>{filterLabel[f]} · {rows.filter(test[f]).length}</button>)}
      </div>
      <button className="fv-button secondary" onClick={exportCsv}>Exportar a Excel (CSV)</button>
    </div>
    {cats.length > 1 && <div className="fv-chips" role="group" aria-label="Categorías"><button className="fv-chip" aria-pressed={!cat} onClick={() => setCat(null)}>Todas las categorías</button>
      {cats.map(x => <button key={x} className="fv-chip" aria-pressed={cat === x} onClick={() => setCat(cat === x ? null : x)}>{x}</button>)}</div>}
    <p className="fv-caption" aria-live="polite">{visible.length} productos</p>
    <div className="fv-products">
      {visible.map((p, i) => <button key={p.id} className={`fv-product${p.active ? "" : " is-off"}`} style={{ "--i": Math.min(i, 12) } as React.CSSProperties}
        onClick={() => setOpenId(p.id)} aria-label={`${p.name}, ${fmt(gross(p.unit_price), currency)}${canEdit ? ", editar" : ""}`}>
        <span className="fv-studio">
          {p.photo_url ? <img src={p.photo_url} alt="" loading="lazy" /> : <b aria-hidden="true">{initials(p.name)}</b>}
          {p.stock != null && <em className={low(p) ? "is-low" : ""}>Stock {Number(p.stock)}</em>}
        </span>
        <span className="fv-product-body">
          <small>{p.category || (p.unit === "ZZ" ? "Servicio" : p.unit === "KGM" ? "Por kilo" : "Producto")}</small>
          <strong>{p.name}</strong>
          <span className="fv-price">{fmt(gross(p.unit_price), currency)}{p.unit === "KGM" ? " / kg" : ""}</span>
        </span>
      </button>)}
    </div>
    {!visible.length && <div className="fv-empty"><h2>{query || filter !== "todos" ? "Sin coincidencias" : "Todavía no hay productos"}</h2><p>Los productos creados en el móvil o aquí aparecen al instante.</p></div>}
    {open && <ProductPanel key={open.id} org={org} product={open} currency={currency} canEdit={canEdit} canKardex={canKardex} canLots={canLots} taxRate={taxRate} onClose={() => setOpenId(null)} />}
  </section>;
}

function ProductPanel({ org, product, currency, canEdit, canKardex, canLots, taxRate, onClose }: { org: string; product: ProductRow; currency: string; canEdit: boolean; canKardex: boolean; canLots: boolean; taxRate: number; onClose: () => void }) {
  const gross = (net: number | string | null | undefined) => net == null || net === "" ? "" : (Math.round(Number(net) * (1 + taxRate / 100) * 100) / 100).toFixed(2);
  const [state, save, saving] = useActionState(updateProduct.bind(null, org, product.id), empty);
  const [photoState, upload, uploading] = useActionState(uploadProductPhoto.bind(null, org, product.id), empty);
  const [preview, setPreview] = useState<string | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  useEffect(() => {
    panel.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  const photo = preview ?? product.photo_url;
  // Mounted at the workspace root: above the sticky top bar, and still inside
  // the element that defines the theme's color variables.
  const root = typeof document === "undefined" ? null : document.querySelector(".fv-workspace");
  const sheet = <div className="fv-sheet-layer" onClick={onClose}>
    <div ref={panel} tabIndex={-1} className="fv-sheet" role="dialog" aria-modal="true" aria-labelledby="fv-sheet-title" onClick={e => e.stopPropagation()}>
      <header><div><small>{product.category || "Producto"}</small><h2 id="fv-sheet-title">{product.name}</h2></div>
        <button className="fv-icon-button" onClick={onClose} aria-label="Cerrar">✕</button></header>
      <div className="fv-studio is-large">{photo ? <img src={photo} alt={`Fotografía de ${product.name}`} /> : <b aria-hidden="true">{initials(product.name)}</b>}</div>
      {canEdit ? <>
        <form action={upload} className="fv-photo-form">
          <label className="fv-button secondary fv-file">Elegir foto<input type="file" name="photo" accept="image/jpeg,image/png,image/webp" className="fv-visually-hidden"
            onChange={e => { const f = e.target.files?.[0]; setPreview(f ? URL.createObjectURL(f) : null); }} /></label>
          <button className="fv-button" disabled={uploading || !preview}>{uploading ? "Subiendo…" : "Subir foto"}</button>
          {photoState.message && <p role={photoState.ok ? "status" : "alert"} className={photoState.ok ? "fv-ok" : "fv-error"}>{photoState.message}</p>}
        </form>
        <form action={save} className="fv-form fv-sheet-form">
          <label>Nombre<input name="name" defaultValue={product.name} required maxLength={120} /></label>
          <input type="hidden" name="extras_shown" value="1" />
          <div className="fv-two">
            <label>Precio de venta {taxRate > 0 ? "(con IGV)" : ""}<input name="price_gross" type="number" min="0" max="12000000" step="0.01" defaultValue={gross(product.unit_price)} required /></label>
            <label>Costo de compra (sin IGV)<input name="unit_cost" type="number" min="0" max="10000000" step="0.01" defaultValue={product.unit_cost == null ? "" : Number(product.unit_cost)} /></label>
          </div>
          <div className="fv-two">
            <label>Precio por mayor {taxRate > 0 ? "(con IGV)" : ""}<input name="wholesale_gross" type="number" min="0" step="0.01" defaultValue={gross(product.wholesale_price)} /></label>
            <label>Desde cuántas unidades<input name="wholesale_min" type="number" min="0" step="0.01" defaultValue={product.wholesale_min_qty == null ? "" : Number(product.wholesale_min_qty)} /></label>
          </div>
          <label>Código interno / SKU<input name="sku" defaultValue={product.sku ?? ""} maxLength={40} /></label>
          <label>Descripción para la tienda<textarea name="description" rows={2} maxLength={400} defaultValue={product.description ?? ""} /></label>
          <label className="fv-check"><input type="checkbox" name="in_store" defaultChecked={product.in_store !== false} /> Mostrar en mi tienda en línea</label>
          <div className="fv-two">
            <label>Stock mínimo<input name="reorder_point" type="number" min="0" step="1" defaultValue={product.reorder_point == null ? "" : Number(product.reorder_point)} /></label>
            <label>Categoría<input name="category" defaultValue={product.category ?? ""} maxLength={60} /></label>
          </div>
          <MarginHint price={Number(product.unit_price)} cost={product.unit_cost == null ? null : Number(product.unit_cost)} />
          <label className="fv-check"><input type="checkbox" name="active" defaultChecked={product.active} /> Activo en el punto de venta</label>
          {product.unit === "NIU" && <><input type="hidden" name="icbper_shown" value="1" />
            <label className="fv-check"><input type="checkbox" name="icbper" defaultChecked={product.icbper === true} /> Es bolsa plástica: el comprobante declara el impuesto a la bolsa (S/ 0.50 c/u) dentro del precio</label></>}
          <button className="fv-button" disabled={saving}>{saving ? "Guardando…" : "Guardar cambios"}</button>
          {state.message && <p role={state.ok ? "status" : "alert"} className={state.ok ? "fv-ok" : "fv-error"}>{state.message}</p>}
        </form>
      </> : <dl className="fv-details">
        <dt>Precio de venta</dt><dd>{fmt(Number(gross(product.unit_price)), currency)}</dd>
        <dt>Existencias</dt><dd>{product.stock == null ? "No controla stock" : Number(product.stock)}</dd>
        <p className="fv-caption">Tu rol puede consultar el catálogo, pero no editarlo.</p>
      </dl>}
      {product.unit !== "ZZ" && <ProductCodes org={org} productId={product.id} canEdit={canEdit} />}
      {canLots && product.stock != null && <ProductLots org={org} productId={product.id} unit={product.unit} stock={Number(product.stock)} canEdit={canEdit} />}
      {canKardex && product.stock != null && <Kardex org={org} productId={product.id} />}
    </div>
  </div>;
  return root ? createPortal(sheet, root) : sheet;
}

/** Margin from the saved price and cost, the same figure the mobile app shows. */
function MarginHint({ price, cost }: { price: number; cost: number | null }) {
  if (cost == null || price <= 0) return <p className="fv-margin">Margen: añade el costo</p>;
  const margin = Math.round(((price - cost) / price) * 100);
  return <p className={`fv-margin${margin < 0 ? " is-bad" : ""}`}>Margen guardado: {margin} %</p>;
}

const when = (iso: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));
const units = (q: number) => (Number.isInteger(q) ? String(q) : q.toFixed(2));

/** Purchases and sales that moved this product's stock, newest first. */
function Kardex({ org, productId }: { org: string; productId: string }) {
  const [data, setData] = useState<Awaited<ReturnType<typeof getKardex>> | null>(null);
  useEffect(() => {
    let alive = true;
    getKardex(org, productId).then(d => { if (alive) setData(d); });
    return () => { alive = false; };
  }, [org, productId]);
  const totals = data?.ok ? kardexTotals(data.rows) : null;
  return <section className="fv-client-block">
    <h3>Kardex</h3>
    {!data ? <div className="fv-skeleton" aria-label="Cargando kardex"><i /><i /></div>
      : !data.ok ? <p role="alert" className="fv-error">{data.message}</p>
      : !data.rows.length ? <p className="fv-muted">Aún no hay compras, ventas ni mermas que hayan movido su stock.</p>
      : <>
        <p className="fv-muted">Últimos movimientos: entraron {units(totals!.entered)} y salieron {units(totals!.left)} unidades.</p>
        <ul className="fv-lines fv-ledger">{data.rows.map((r: KardexEntry, i: number) => <li key={i}>
          <span><b className={r.delta > 0 ? "is-in" : "is-out"}>{r.kind === "compra" ? "Compra" : r.kind === "merma" ? "Merma" : "Venta"}</b> {when(r.at)} · {r.ref}</span>
          <span>{r.delta > 0 ? "+" : ""}{units(r.delta)} → {units(r.after)}</span>
        </li>)}</ul>
      </>}
  </section>;
}

/** Barcodes of the product: the main one and the extras (other presentations or lots of the same product). */
function ProductCodes({ org, productId, canEdit }: { org: string; productId: string; canEdit: boolean }) {
  const [data, setData] = useState<Awaited<ReturnType<typeof getProductCodes>> | null>(null);
  const [version, setVersion] = useState(0);
  const [code, setCode] = useState("");
  const [msg, setMsg] = useState<FormResult>({ ok: false, message: "" });
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    getProductCodes(org, productId).then(d => { if (alive) setData(d); });
    return () => { alive = false; };
  }, [org, productId, version]);
  async function add() {
    if (busy || !code.trim()) return;
    setBusy(true);
    const r = await addProductCode(org, productId, code).catch(() => ({ ok: false, message: "Sin conexión." }));
    setBusy(false); setMsg(r);
    if (r.ok) { setCode(""); setVersion(v => v + 1); }
  }
  return <section className="fv-client-block">
    <h3>Códigos de barras</h3>
    {!data ? <div className="fv-skeleton" aria-label="Cargando códigos"><i /></div>
      : !data.ok ? <p role="alert" className="fv-error">{data.message}</p>
      : <ul className="fv-lines fv-ledger">
        {data.main ? <li><span><b>{data.main}</b> principal</span><span /></li> : <li><span className="fv-muted">Sin código principal</span><span /></li>}
        {data.extra.map(x => <li key={x.id}><span>{x.code}</span><span>{canEdit && <button className="fv-link" onClick={async () => { const r = await removeProductCode(org, x.id); setMsg(r); if (r.ok) setVersion(v => v + 1); }}>Quitar</button>}</span></li>)}
      </ul>}
    {canEdit && <div className="fv-fiado-form">
      <label className="fv-grow"><span>Agregar código (escanéalo con la pistola o escríbelo)</span>
        <input value={code} onChange={e => setCode(e.target.value)} onKeyDown={e => { if (e.key === "Enter") { e.preventDefault(); void add(); } }} placeholder="7751234567890" inputMode="numeric" /></label>
      <button className="fv-button secondary" disabled={busy || !code.trim()} onClick={add}>{busy ? "Guardando…" : "Agregar"}</button>
    </div>}
    {msg.message && <p className={msg.ok ? "fv-ok" : "fv-error"} role={msg.ok ? "status" : "alert"}>{msg.message}</p>}
    <p className="fv-caption">Todos los códigos venden este mismo producto con su precio. Con lector de códigos, escanea uno tras otro: cada Enter lo guarda.</p>
  </section>;
}
