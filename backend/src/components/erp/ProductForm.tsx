"use client";
import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { createProduct, type FormResult } from "@/app/erp/actions";
import { ean13Check } from "@/lib/erp/pos";
import CameraScan from "./CameraScan";

const idle: FormResult = { ok: false, message: "" };
const num = (v: string) => { const n = Number(v.replace(",", ".")); return Number.isFinite(n) && v.trim() !== "" ? n : null; };

/** Internal EAN-13 for products without a barcode (prefix 29, never used by scale labels of this app). */
function internalCode(): string {
  const body = `29${Math.floor(Math.random() * 1e10).toString().padStart(10, "0")}`;
  return body + ean13Check(body);
}

/** «Nuevo producto»: a complete product sheet like an ERP, in the order a shopkeeper fills it in. */
export default function NewProductForm({ org, taxRate, categories }: { org: string; taxRate: number; categories: string[] }) {
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState(async (p: FormResult, f: FormData) => { const r = await createProduct(org, p, f); if (r.ok) { reset(); router.refresh(); } return r; }, idle);
  const router = useRouter();
  const [unit, setUnit] = useState<"NIU" | "KGM" | "ZZ">("NIU");
  const [price, setPrice] = useState("");
  const [cost, setCost] = useState("");
  const [barcode, setBarcode] = useState("");
  const [track, setTrack] = useState(true);
  const [preview, setPreview] = useState<string | null>(null);
  const [n, setN] = useState(0);
  function reset() { setPrice(""); setCost(""); setBarcode(""); setPreview(null); setN(x => x + 1); }
  const g = num(price), c = num(cost);
  const netPrice = g == null ? null : Math.round((g / (1 + taxRate / 100)) * 100) / 100;
  const margin = netPrice && c != null && netPrice > 0 ? (netPrice - c) / netPrice : null;
  const priceFor = (m: number) => c == null ? null : Math.round((c / (1 - m)) * (1 + taxRate / 100) * 10) / 10;
  if (!open) return <button className="fv-button" onClick={() => setOpen(true)}>+ Nuevo producto</button>;
  return <form action={action} className="fv-create fv-form fv-product-sheet" key={n}>
    <header><h3>Nuevo producto</h3><button type="button" className="fv-icon-button" onClick={() => setOpen(false)} aria-label="Cerrar">✕</button></header>
    <fieldset><legend>1 · Qué es</legend>
      <div className="fv-two"><label>Nombre<input name="name" required maxLength={200} placeholder="Ej.: Inca Kola 500 ml" /></label>
        <label>Categoría<input name="category" list="fv-cats" maxLength={60} placeholder="Ej.: Bebidas" /><datalist id="fv-cats">{categories.map(x => <option key={x} value={x} />)}</datalist></label></div>
      <div className="fv-segment" role="group" aria-label="Tipo">{([["NIU", "Por unidad"], ["KGM", "Por kilo (balanza)"], ["ZZ", "Servicio"]] as const).map(([k, l]) => <button type="button" key={k} aria-pressed={unit === k} onClick={() => { setUnit(k); if (k === "ZZ") setTrack(false); }}>{l}</button>)}</div>
      <input type="hidden" name="unit" value={unit} />
    </fieldset>
    {unit !== "ZZ" && <fieldset><legend>2 · Código</legend>
      <div className="fv-two"><label>Código de barras<span className="fv-input-row"><input name="barcode" value={barcode} onChange={e => setBarcode(e.target.value.replace(/[^0-9A-Za-z-]/g, ""))} maxLength={40} placeholder="Escanéalo con la pistola" />
        <CameraScan onCode={code => setBarcode(code)} label="Leer código con la cámara" /></span>
        <button type="button" className="fv-link" onClick={() => setBarcode(internalCode())}>No tiene código: generar uno interno</button></label>
        <label>Código interno / SKU (opcional)<input name="sku" maxLength={40} /></label></div>
      {unit === "KGM" && <p className="fv-caption">Para la balanza: usa como código el PLU de 5 dígitos que programaste en la balanza (ej. 00012).</p>}
    </fieldset>}
    <fieldset><legend>{unit === "ZZ" ? "2" : "3"} · Precio y costo</legend>
      <div className="fv-three"><label>Precio de venta {taxRate > 0 ? "(con IGV)" : ""}<input name="price_gross" inputMode="decimal" required value={price} onChange={e => setPrice(e.target.value)} placeholder="0.00" /></label>
        <label>Costo de compra (sin IGV)<input name="unit_cost" inputMode="decimal" value={cost} onChange={e => setCost(e.target.value)} placeholder="opcional" /></label>
        <div className="fv-margin-box">{netPrice != null && taxRate > 0 && <small>Sin IGV: {netPrice.toFixed(2)} · IGV {(g! - netPrice).toFixed(2)}</small>}
          {margin != null && <b className={margin < 0.15 ? "fv-neg" : margin < 0.3 ? "fv-warn" : "fv-up"}>{margin < 0 ? "Vendes a pérdida" : `Margen ${Math.round(margin * 100)} %`}</b>}</div></div>
      {c != null && <div className="fv-chips">{[0.2, 0.3, 0.4].map(m => <button type="button" key={m} className="fv-chip" onClick={() => setPrice(priceFor(m)!.toFixed(2))}>Precio para ganar {m * 100} %: {priceFor(m)!.toFixed(2)}</button>)}</div>}
      <div className="fv-two"><label>Precio por mayor {taxRate > 0 ? "(con IGV)" : ""}<input name="wholesale_gross" inputMode="decimal" placeholder="opcional" /></label><label>Desde cuántas unidades<input name="wholesale_min" inputMode="decimal" placeholder="Ej.: 6" /></label></div>
      {unit === "NIU" && <label className="fv-check"><input type="checkbox" name="icbper" /> Es bolsa plástica (impuesto a la bolsa S/ 0.50 dentro del precio)</label>}
    </fieldset>
    {unit !== "ZZ" && <fieldset><legend>4 · Stock</legend>
      <label className="fv-check"><input type="checkbox" name="track" checked={track} onChange={e => setTrack(e.target.checked)} /> Controlar stock (se descuenta al vender y te avisa cuando se acaba)</label>
      {track && <div className="fv-two"><label>Stock inicial<input name="stock" inputMode="decimal" placeholder="0" /></label><label>Stock mínimo (avisarme cuando queden)<input name="reorder_point" inputMode="decimal" placeholder="Ej.: 5" /></label></div>}
    </fieldset>}
    <fieldset><legend>{unit === "ZZ" ? "3" : "5"} · Foto y tienda</legend>
      <div className="fv-logo-row"><span className="fv-logo-box">{/* eslint-disable-next-line @next/next/no-img-element */}{preview ? <img src={preview} alt="Foto del producto" /> : <b>Sin foto</b>}</span>
        <label className="fv-button secondary fv-file">Elegir foto<input type="file" name="photo" hidden accept="image/jpeg,image/png,image/webp" onChange={e => { const f = e.target.files?.[0]; setPreview(f ? URL.createObjectURL(f) : null); }} /></label></div>
      <label>Descripción para la tienda en línea (opcional)<textarea name="description" rows={2} maxLength={400} /></label>
      <label className="fv-check"><input type="checkbox" name="in_store" defaultChecked /> Mostrar en mi tienda en línea</label>
      <label className="fv-check"><input type="checkbox" name="featured" /> Destacarlo</label>
    </fieldset>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Crear producto"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}
