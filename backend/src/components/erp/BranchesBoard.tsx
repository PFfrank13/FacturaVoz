"use client";
import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { transferStock } from "@/app/erp/actions";

export type Branch = { id: string; name: string; today: number; month: number; todayCount: number; low: number; current: boolean };
export type BranchProduct = { id: string; org_id: string; name: string; stock: number | null; unit: string };
export type TransferRow = { id: string; created_at: string; quantity: number; from: string; to: string; product: string; note: string | null };

const when = (iso: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));
const norm = (s: string) => s.trim().toLocaleLowerCase("es").normalize("NFD").replace(/\p{Diacritic}/gu, "");

/** All the owner's stores at a glance, and moving goods from this store to another one. */
export default function BranchesBoard({ org, branches, products, transfers, currency, canTransfer }: {
  org: string; branches: Branch[]; products: BranchProduct[]; transfers: TransferRow[]; currency: string; canTransfer: boolean;
}) {
  const fmt = (v: number) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(v);
  const total = branches.reduce((a, b) => ({ today: a.today + b.today, month: a.month + b.month }), { today: 0, month: 0 });
  return <section className="fv-board">
    <div className="fv-kpis">
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Hoy en todos tus locales</span><strong>{fmt(total.today)}</strong><small>{branches.length} {branches.length === 1 ? "local" : "locales"}</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Este mes</span><strong>{fmt(total.month)}</strong><small>suma de todos los locales</small></div>
      <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Productos bajo mínimo</span><strong>{branches.reduce((a, b) => a + b.low, 0)}</strong><small>en todos los locales</small></div>
    </div>
    <ul className="fv-branches">{branches.map(b => <li key={b.id} className={b.current ? "is-current" : ""}>
      <div><strong>{b.name}</strong><small>{b.current ? "Estás aquí" : <Link href={`/erp/${b.id}`}>Abrir este local</Link>}</small></div>
      <span>Hoy {fmt(b.today)} · {b.todayCount} {b.todayCount === 1 ? "venta" : "ventas"}</span>
      <span>Mes {fmt(b.month)}</span>
      <span className={b.low ? "is-out" : ""}>{b.low ? `${b.low} bajo mínimo` : "Stock en orden"}</span>
    </li>)}</ul>
    {canTransfer && branches.length > 1 && <TransferForm org={org} branches={branches.filter(b => !b.current)} products={products} />}
    {branches.length < 2 && <div className="fv-empty"><h2>Aún tienes un solo local</h2><p>Crea otro desde el móvil (Ajustes → Mis empresas) y aparecerá aquí con sus ventas y su stock.</p></div>}
    {transfers.length > 0 && <section className="fv-create fv-cash-card">
      <h3>Últimos traslados</h3>
      <ul className="fv-lines fv-ledger">{transfers.map(t => <li key={t.id}><span><b>{t.product}</b> {t.from} → {t.to} · {when(t.created_at)}{t.note ? ` · ${t.note}` : ""}</span><span>{t.quantity}</span></li>)}</ul>
    </section>}
  </section>;
}

function TransferForm({ org, branches, products }: { org: string; branches: Branch[]; products: BranchProduct[] }) {
  const router = useRouter();
  const requestId = useRef(crypto.randomUUID());
  const [to, setTo] = useState(branches[0]?.id ?? "");
  const [from, setFrom] = useState("");
  const [target, setTarget] = useState("");
  const [qty, setQty] = useState("");
  const [note, setNote] = useState("");
  const [state, setState] = useState<{ busy: boolean; ok: boolean; message: string }>({ busy: false, ok: false, message: "" });
  const mine = useMemo(() => products.filter(p => p.org_id === org && p.stock != null && p.stock > 0), [products, org]);
  const theirs = useMemo(() => products.filter(p => p.org_id === to), [products, to]);
  const pickFrom = (id: string) => {
    setFrom(id);
    const src = products.find(p => p.id === id);
    const match = src ? theirs.find(p => norm(p.name) === norm(src.name)) : undefined;
    setTarget(match?.id ?? "");
  };
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const quantity = Number(qty.replace(",", "."));
    if (!from || !target || !(quantity > 0)) return setState({ busy: false, ok: false, message: "Elige el producto de origen, el de destino y la cantidad." });
    setState({ busy: true, ok: false, message: "" });
    const r = await transferStock(org, { request_id: requestId.current, to_org: to, from_product: from, to_product: target, quantity, note }).catch(() => null);
    setState({ busy: false, ok: !!r?.ok, message: r?.message ?? "Sin conexión. Vuelve a intentarlo: no se duplicará." });
    if (r?.ok) { requestId.current = crypto.randomUUID(); setQty(""); setNote(""); router.refresh(); }
  }
  return <form className="fv-create fv-fiado-form" onSubmit={submit}>
    <h3 style={{ flexBasis: "100%" }}>Trasladar mercadería a otro local</h3>
    <label><span>Hacia</span><select value={to} onChange={e => { setTo(e.target.value); setTarget(""); }}>{branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}</select></label>
    <label className="fv-grow"><span>Producto de este local</span><select value={from} onChange={e => pickFrom(e.target.value)}>
      <option value="">Elige…</option>{mine.map(p => <option key={p.id} value={p.id}>{p.name} · stock {p.stock}</option>)}
    </select></label>
    <label className="fv-grow"><span>Producto en el destino</span><select value={target} onChange={e => setTarget(e.target.value)}>
      <option value="">Elige…</option>{theirs.map(p => <option key={p.id} value={p.id}>{p.name}{p.stock != null ? ` · stock ${p.stock}` : ""}</option>)}
    </select></label>
    <label><span>Cantidad</span><input inputMode="decimal" value={qty} onChange={e => setQty(e.target.value)} placeholder="0" /></label>
    <label className="fv-grow"><span>Nota</span><input maxLength={200} value={note} onChange={e => setNote(e.target.value)} placeholder="Opcional" /></label>
    <button className="fv-button" disabled={state.busy}>{state.busy ? "Trasladando…" : "Trasladar"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}
