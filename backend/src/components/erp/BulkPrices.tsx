"use client";
import { useMemo, useState } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { applyBulkPrices } from "@/app/erp/actions";
import { newShelfPrice, priceModes, pricingProblem, withTax, type PriceMode } from "@/lib/erp/pricing";

export type PriceProduct = { id: string; name: string; category: string | null; unit_price: number; unit_cost: number | null };

/** «Cambiar precios» (by category, % or soles, rounded to 0.10 on the shelf price) and «Etiquetas» for the shelves. */
export default function BulkPrices({ org, products, currency, taxRate }: { org: string; products: PriceProduct[]; currency: string; taxRate: number }) {
  const [open, setOpen] = useState(false);
  return <>
    <button className="fv-button secondary" onClick={() => setOpen(true)}>Cambiar precios</button>
    <Link className="fv-button secondary" href={`/erp/${org}/productos/etiquetas`}>Imprimir etiquetas</Link>
    {open && <PriceSheet org={org} products={products} currency={currency} taxRate={taxRate} onClose={() => setOpen(false)} />}
  </>;
}

function PriceSheet({ org, products, currency, taxRate, onClose }: { org: string; products: PriceProduct[]; currency: string; taxRate: number; onClose: () => void }) {
  const router = useRouter();
  const fmt = (v: number) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(v);
  const categories = useMemo(() => [...new Set(products.map(p => p.category).filter((c): c is string => !!c))].sort((a, b) => a.localeCompare(b, "es")), [products]);
  const [category, setCategory] = useState(categories[0] ?? "");
  const [mode, setMode] = useState<PriceMode>("subir_pct");
  const [value, setValue] = useState("");
  const [state, setState] = useState<{ busy: boolean; ok: boolean; message: string }>({ busy: false, ok: false, message: "" });
  const v = Number(value.replace(",", "."));
  const problem = pricingProblem(mode, value ? v : null);
  const chosen = products.filter(p => !category || p.category === category);
  const preview = chosen.map(p => {
    const shelf = withTax(p.unit_price, taxRate);
    const next = problem ? shelf : newShelfPrice(shelf, mode, v);
    const costShelf = p.unit_cost == null ? null : withTax(p.unit_cost, taxRate);
    return { ...p, shelf, next, belowCost: costShelf != null && next < costShelf };
  });
  async function apply() {
    if (problem || state.busy || !chosen.length) return;
    setState({ busy: true, ok: false, message: "" });
    const r = await applyBulkPrices(org, { ids: chosen.map(p => p.id), mode, value: v }).catch(() => null);
    setState({ busy: false, ok: !!r?.ok, message: r?.message ?? "Sin conexión. Vuelve a intentarlo." });
    if (r?.ok) router.refresh();
  }
  const root = typeof document === "undefined" ? null : document.querySelector(".fv-workspace");
  const sheet = <div className="fv-sheet-layer" onClick={onClose}>
    <div className="fv-sheet fv-client-sheet fv-count" role="dialog" aria-modal="true" aria-labelledby="fv-prices-title" onClick={e => e.stopPropagation()}>
      <header><div><small>Productos</small><h2 id="fv-prices-title">Cambiar precios</h2></div><button className="fv-icon-button" onClick={onClose} aria-label="Cerrar">✕</button></header>
      <p className="fv-muted">Cambia de una vez los precios de venta al público (con IGV), redondeados a 10 céntimos. El móvil los usa al instante.</p>
      <div className="fv-fiado-form">
        <label><span>Categoría</span><select value={category} onChange={e => setCategory(e.target.value)}><option value="">Todos los productos</option>{categories.map(c => <option key={c} value={c}>{c}</option>)}</select></label>
        <label><span>Cambio</span><select value={mode} onChange={e => setMode(e.target.value as PriceMode)}>{Object.entries(priceModes).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>
        <label><span>{mode.endsWith("pct") ? "Porcentaje" : "Soles"}</span><input inputMode="decimal" value={value} onChange={e => setValue(e.target.value)} placeholder={mode.endsWith("pct") ? "5" : "0.50"} /></label>
      </div>
      <ul className="fv-count-list">{preview.slice(0, 300).map(p => <li key={p.id}>
        <span><b>{p.name}</b><small>{p.category ?? "Sin categoría"}{p.belowCost ? " · queda bajo el costo" : ""}</small></span>
        <small>{fmt(p.shelf)}</small>
        <em className={p.belowCost ? "is-out" : p.next !== p.shelf ? "is-in" : ""}>{fmt(p.next)}</em>
      </li>)}</ul>
      <div className="fv-count-foot">
        {value && problem && <p className="fv-error" role="alert">{problem}</p>}
        <button className="fv-button" disabled={!!problem || state.busy || !chosen.length} onClick={apply}>{state.busy ? "Aplicando…" : `Aplicar a ${chosen.length} ${chosen.length === 1 ? "producto" : "productos"}`}</button>
        {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
      </div>
    </div>
  </div>;
  return root ? createPortal(sheet, root) : sheet;
}
