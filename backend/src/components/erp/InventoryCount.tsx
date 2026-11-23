"use client";
import { useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useRouter } from "next/navigation";
import { applyCount } from "@/app/erp/actions";
import { countLines, countSummary, parseCount } from "@/lib/erp/count";

export type CountProduct = { id: string; name: string; category: string | null; stock: number; unit: string; unit_cost: number | null };

/** «Contar inventario»: type what the shelf has; shortages become shrinkage with a reason, surpluses add stock. */
export default function InventoryCount({ org, products, currency }: { org: string; products: CountProduct[]; currency: string }) {
  const [open, setOpen] = useState(false);
  return <>
    <button className="fv-button secondary" onClick={() => setOpen(true)}>Contar inventario</button>
    {open && <CountSheet org={org} products={products} currency={currency} onClose={() => setOpen(false)} />}
  </>;
}

function CountSheet({ org, products, currency, onClose }: { org: string; products: CountProduct[]; currency: string; onClose: () => void }) {
  const router = useRouter();
  const fmt = (v: number) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(v);
  const requestId = useRef(crypto.randomUUID());
  const [q, setQ] = useState("");
  const [category, setCategory] = useState("");
  const [typed, setTyped] = useState<Record<string, string>>({});
  const [state, setState] = useState<{ busy: boolean; ok: boolean; message: string }>({ busy: false, ok: false, message: "" });
  const categories = useMemo(() => [...new Set(products.map(p => p.category).filter((c): c is string => !!c))].sort((a, b) => a.localeCompare(b, "es")), [products]);
  const visible = products.filter(p => (!category || p.category === category) && p.name.toLocaleLowerCase("es").includes(q.toLocaleLowerCase("es")));
  const items = products.flatMap(p => {
    const v = parseCount(typed[p.id] ?? "");
    return v == null || Number.isNaN(v) ? [] : [{ product_id: p.id, name: p.name, stock: p.stock, counted: v, unit_cost: p.unit_cost }];
  });
  const invalid = Object.values(typed).some(v => Number.isNaN(parseCount(v)));
  const lines = countLines(items);
  const sum = countSummary(lines);
  async function apply() {
    if (state.busy || !lines.length) return;
    setState({ busy: true, ok: false, message: "" });
    const r = await applyCount(org, { request_id: requestId.current, lines: lines.map(l => ({ product_id: l.product_id, expected: l.stock, counted: l.counted })) }).catch(() => null);
    setState({ busy: false, ok: !!r?.ok, message: r?.message ?? "Sin conexión. Vuelve a intentarlo: no se duplicará." });
    if (r?.ok) { requestId.current = crypto.randomUUID(); setTyped({}); router.refresh(); }
  }
  const root = typeof document === "undefined" ? null : document.querySelector(".fv-workspace");
  const sheet = <div className="fv-sheet-layer" onClick={onClose}>
    <div className="fv-sheet fv-client-sheet fv-count" role="dialog" aria-modal="true" aria-labelledby="fv-count-title" onClick={e => e.stopPropagation()}>
      <header><div><small>Inventario</small><h2 id="fv-count-title">Contar inventario</h2></div><button className="fv-icon-button" onClick={onClose} aria-label="Cerrar">✕</button></header>
      <p className="fv-muted">Escribe solo lo que cuentes. Lo que falte se registra como merma («Diferencia de conteo») y lo que sobre se suma al stock.</p>
      <div className="fv-board-tools">
        <label className="fv-search"><span>Buscar</span><input type="search" value={q} onChange={e => setQ(e.target.value)} placeholder="Producto…" /></label>
        {categories.length > 0 && <label className="fv-search fv-narrow"><span>Categoría</span><select value={category} onChange={e => setCategory(e.target.value)}><option value="">Todas</option>{categories.map(c => <option key={c} value={c}>{c}</option>)}</select></label>}
      </div>
      <ul className="fv-count-list">{visible.slice(0, 300).map(p => {
        const v = parseCount(typed[p.id] ?? "");
        const diff = v == null || Number.isNaN(v) ? null : Math.round((v - p.stock) * 100) / 100;
        return <li key={p.id}>
          <span><b>{p.name}</b><small>Sistema: {p.stock} {p.unit === "KGM" ? "kg" : "u."}</small></span>
          <input inputMode="decimal" aria-label={`Contado de ${p.name}`} value={typed[p.id] ?? ""} placeholder="—" onChange={e => setTyped(t => ({ ...t, [p.id]: e.target.value }))} className={v !== null && Number.isNaN(v) ? "is-invalid" : ""} />
          <em className={diff == null || diff === 0 ? "" : diff < 0 ? "is-out" : "is-in"}>{diff == null ? "" : diff === 0 ? "Cuadra" : diff > 0 ? `+${diff}` : diff}</em>
        </li>;
      })}</ul>
      <div className="fv-count-foot">
        <p>{lines.length ? <>Faltan <b>{sum.missing}</b> ({fmt(sum.missingValue)}) · sobran <b>{sum.extra}</b> ({fmt(sum.extraValue)}) en {sum.products} {sum.products === 1 ? "producto" : "productos"}</> : items.length ? "Todo lo contado cuadra." : "Aún no has contado nada."}</p>
        {invalid && <p className="fv-error" role="alert">Revisa las cantidades marcadas: solo números con hasta 2 decimales.</p>}
        <button className="fv-button" disabled={state.busy || !lines.length || invalid} onClick={apply}>{state.busy ? "Aplicando…" : "Aplicar conteo"}</button>
        {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
      </div>
    </div>
  </div>;
  return root ? createPortal(sheet, root) : sheet;
}
