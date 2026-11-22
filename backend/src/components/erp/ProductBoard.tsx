"use client";
import { useActionState, useEffect, useMemo, useRef, useState } from "react";
import { updateProduct, uploadProductPhoto, type FormResult } from "@/app/erp/actions";

export type ProductRow = {
  id: string; name: string; unit_price: number | string; unit: string; active: boolean;
  category: string | null; stock: number | string | null; reorder_point: number | string | null;
  image_path: string | null; photo_url: string | null;
};

const empty: FormResult = { ok: false, message: "" };
const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const initials = (name: string) => name.trim().split(/\s+/).slice(0, 2).map(w => w[0]?.toUpperCase() ?? "").join("");

/** Catalog administration: the same rows the mobile POS sells from. */
export default function ProductBoard({ org, rows, currency, canEdit }: { org: string; rows: ProductRow[]; currency: string; canEdit: boolean }) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<"todos" | "bajo" | "inactivos">("todos");
  const [openId, setOpenId] = useState<string | null>(null);
  const low = (p: ProductRow) => p.stock != null && p.reorder_point != null && Number(p.stock) <= Number(p.reorder_point);
  const visible = useMemo(() => rows.filter(p =>
    (filter === "todos" || (filter === "bajo" ? low(p) : !p.active)) &&
    `${p.name} ${p.category ?? ""}`.toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))), [rows, filter, query]);
  const open = rows.find(p => p.id === openId) ?? null;
  return <section className="fv-board">
    <div className="fv-board-tools">
      <label className="fv-search"><span>Buscar producto</span><input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Nombre o categoría…" /></label>
      <div className="fv-segment" role="group" aria-label="Filtrar productos">
        {(["todos", "bajo", "inactivos"] as const).map(f => <button key={f} aria-pressed={filter === f} onClick={() => setFilter(f)}>
          {f === "todos" ? `Todos · ${rows.length}` : f === "bajo" ? `Stock bajo · ${rows.filter(low).length}` : `Inactivos · ${rows.filter(p => !p.active).length}`}
        </button>)}
      </div>
    </div>
    <p className="fv-caption" aria-live="polite">{visible.length} productos</p>
    <div className="fv-products">
      {visible.map((p, i) => <button key={p.id} className={`fv-product${p.active ? "" : " is-off"}`} style={{ "--i": Math.min(i, 12) } as React.CSSProperties}
        onClick={() => setOpenId(p.id)} aria-label={`${p.name}, ${fmt(Number(p.unit_price), currency)}${canEdit ? ", editar" : ""}`}>
        <span className="fv-studio">
          {p.photo_url ? <img src={p.photo_url} alt="" loading="lazy" /> : <b aria-hidden="true">{initials(p.name)}</b>}
          {p.stock != null && <em className={low(p) ? "is-low" : ""}>Stock {Number(p.stock)}</em>}
        </span>
        <span className="fv-product-body">
          <small>{p.category || (p.unit === "ZZ" ? "Servicio" : "Producto")}</small>
          <strong>{p.name}</strong>
          <span className="fv-price">{fmt(Number(p.unit_price), currency)}</span>
        </span>
      </button>)}
    </div>
    {!visible.length && <div className="fv-empty"><h2>{query || filter !== "todos" ? "Sin coincidencias" : "Todavía no hay productos"}</h2><p>Los productos creados en el móvil o aquí aparecen al instante.</p></div>}
    {open && <ProductPanel key={open.id} org={org} product={open} currency={currency} canEdit={canEdit} onClose={() => setOpenId(null)} />}
  </section>;
}

function ProductPanel({ org, product, currency, canEdit, onClose }: { org: string; product: ProductRow; currency: string; canEdit: boolean; onClose: () => void }) {
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
  return <div className="fv-sheet-layer" onClick={onClose}>
    <div ref={panel} tabIndex={-1} className="fv-sheet" role="dialog" aria-modal="true" aria-labelledby="fv-sheet-title" onClick={e => e.stopPropagation()}>
      <header><div><small>{product.category || "Producto"}</small><h2 id="fv-sheet-title">{product.name}</h2></div>
        <button className="fv-icon-button" onClick={onClose} aria-label="Cerrar">✕</button></header>
      <div className="fv-studio is-large">{photo ? <img src={photo} alt={`Fotografía de ${product.name}`} /> : <b aria-hidden="true">{initials(product.name)}</b>}</div>
      {canEdit ? <>
        <form action={upload} className="fv-photo-form">
          <label className="fv-button secondary">Elegir foto<input type="file" name="photo" accept="image/jpeg,image/png,image/webp" hidden
            onChange={e => { const f = e.target.files?.[0]; setPreview(f ? URL.createObjectURL(f) : null); }} /></label>
          <button className="fv-button" disabled={uploading || !preview}>{uploading ? "Subiendo…" : "Subir foto"}</button>
          {photoState.message && <p role={photoState.ok ? "status" : "alert"} className={photoState.ok ? "fv-ok" : "fv-error"}>{photoState.message}</p>}
        </form>
        <form action={save} className="fv-form fv-sheet-form">
          <label>Nombre<input name="name" defaultValue={product.name} required maxLength={120} /></label>
          <div className="fv-two">
            <label>Precio (sin IGV)<input name="unit_price" type="number" min="0" max="10000000" step="0.01" defaultValue={Number(product.unit_price)} required /></label>
            <label>Stock mínimo<input name="reorder_point" type="number" min="0" step="1" defaultValue={product.reorder_point == null ? "" : Number(product.reorder_point)} /></label>
          </div>
          <label>Categoría<input name="category" defaultValue={product.category ?? ""} maxLength={60} /></label>
          <label className="fv-check"><input type="checkbox" name="active" defaultChecked={product.active} /> Activo en el punto de venta</label>
          <button className="fv-button" disabled={saving}>{saving ? "Guardando…" : "Guardar cambios"}</button>
          {state.message && <p role={state.ok ? "status" : "alert"} className={state.ok ? "fv-ok" : "fv-error"}>{state.message}</p>}
        </form>
      </> : <dl className="fv-details">
        <dt>Precio</dt><dd>{fmt(Number(product.unit_price), currency)}</dd>
        <dt>Existencias</dt><dd>{product.stock == null ? "No controla stock" : Number(product.stock)}</dd>
        <p className="fv-caption">Tu rol puede consultar el catálogo, pero no editarlo.</p>
      </dl>}
    </div>
  </div>;
}
