import type React from "react";
import Link from "next/link";
import type { workspaceContext } from "@/lib/erp/context";
import { money } from "@/lib/schemas";
import { limaDate } from "@/lib/erp/receipts";
import { can } from "@/lib/erp/access";
import LiveRefresh from "@/components/erp/LiveRefresh";
import { ExpiryOverview } from "@/components/erp/LotsAndLosses";
import type { LossRow, LotStatus } from "@/lib/erp/lots";
import { suggestOrder, type Velocity } from "@/lib/erp/purchases";

type Ctx = Awaited<ReturnType<typeof workspaceContext>>;
const tone = (t: string) => ({ "--tone": t }) as React.CSSProperties;
const heading = (eyebrow: string, title: string, text: string, org: string, live?: readonly string[]) =>
  <section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{eyebrow}</p>{live && <LiveRefresh org={org} tables={live} />}</div><h1>{title}</h1><p>{text}</p></section>;
const failed = (what: string) => <div className="fv-empty" role="alert"><h2>No pudimos cargar {what}</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>;
const n = (v: unknown) => (v == null || v === "" ? 0 : Number(v) || 0);
const liveInventory = ["products", "product_lots", "stock_losses"] as const;

/** «Reposición inteligente» and «Vencimientos y mermas» as their own modules, like in the mobile menu. */
export async function renderExtra5(id: string, c: Ctx, org: string, title: string, search: { dias?: string }) {
  const cur = c.organization.currency || "PEN";
  const fmt = (v: number) => money(v, cur);
  const name = c.organization.name;
  const today = limaDate(new Date());

  if (id === "reponer") {
    const days = [7, 14, 30].includes(Number(search.dias)) ? Number(search.dias) : 14;
    const [vel, prods, buys] = await Promise.all([
      c.db.rpc("product_velocity", { p_org: org, p_days: 30 }),
      c.db.from("products").select("id,name,stock,unit_cost,category,unit").eq("org_id", org).eq("active", true).not("stock", "is", null).limit(3000),
      c.db.from("retail_receipts").select("supplier_name,created_at,items:retail_receipt_items(product_id,unit_cost_cents)").eq("org_id", org).gt("total_cents", 0).order("created_at", { ascending: false }).limit(200),
    ]);
    if (vel.error) return <>{heading(`MERCADERÍA / ${name}`, title, "", org)}{failed("las ventas de tus productos")}</>;
    const last = new Map<string, { supplier: string; unit_cost: number | null }>();
    for (const r of (buys.data ?? []) as { supplier_name: string; items: { product_id: string; unit_cost_cents: number | string }[] | null }[])
      for (const it of r.items ?? []) if (!last.has(it.product_id)) last.set(it.product_id, { supplier: r.supplier_name, unit_cost: n(it.unit_cost_cents) / 100 });
    type P = { id: string; name: string; stock: number | string; unit_cost: number | string | null; category: string | null; unit: string };
    const products = new Map(((prods.data ?? []) as P[]).map(p => [p.id, p] as const));
    const velocity = ((vel.data ?? []) as Velocity[]).filter(v => products.has(v.product_id));
    const list = suggestOrder(velocity, last, days).map(s => ({ ...s, unit_cost: s.unit_cost ?? (products.get(s.product_id)?.unit_cost == null ? null : n(products.get(s.product_id)!.unit_cost)), category: products.get(s.product_id)?.category ?? "" }));
    const sold = new Set(velocity.filter(v => n(v.units) > 0).map(v => v.product_id));
    const stuck = [...products.values()].filter(p => n(p.stock) > 0 && !sold.has(p.id)).map(p => ({ ...p, value: n(p.stock) * n(p.unit_cost) })).sort((a, b) => b.value - a.value);
    const bySupplier = new Map<string, typeof list>();
    for (const s of list) bySupplier.set(s.supplier || "Sin proveedor registrado", [...(bySupplier.get(s.supplier || "Sin proveedor registrado") ?? []), s]);
    const cost = list.reduce((a, s) => a + s.quantity * (s.unit_cost ?? 0), 0);
    const out = list.filter(s => s.stock <= 0).length;
    return <>{heading(`MERCADERÍA / ${name}`, title, `Según lo que vendiste en los últimos 30 días: qué se te va a acabar y cuánto pedir para cubrir ${days === 7 ? "una semana" : days === 14 ? "dos semanas" : "un mes"}.`, org, liveInventory)}
      <div className="fv-kpis fv-kpis-4">
        <div style={tone("#ff8aa8")}><span>Por pedir</span><strong>{list.length}</strong><small>{out} ya agotados</small></div>
        <div style={tone("#3ee6b0")}><span>Costo estimado del pedido</span><strong>{fmt(cost)}</strong><small>con el último costo de compra</small></div>
        <div style={tone("#ffb35c")}><span>Plata parada</span><strong>{fmt(stuck.reduce((a, s) => a + s.value, 0))}</strong><small>{stuck.length} productos sin ventas en 30 días</small></div>
        <div style={tone("#6fb7ff")}><span>Proveedores</span><strong>{[...bySupplier.keys()].filter(k => k !== "Sin proveedor registrado").length}</strong><small>a los que les toca pedido</small></div>
      </div>
      <nav className="fv-chips" aria-label="Cobertura">{[7, 14, 30].map(d => <Link key={d} className="fv-chip" aria-pressed={days === d} href={`/erp/${org}/reponer?dias=${d}`}>Cubrir {d === 7 ? "1 semana" : d === 14 ? "2 semanas" : "1 mes"}</Link>)}</nav>
      {!list.length ? <div className="fv-empty"><h2>No se te acaba nada pronto</h2><p>Con lo que vendes, tu stock alcanza. Fija el stock mínimo de cada producto en Productos para que te avise antes.</p></div>
        : [...bySupplier.entries()].map(([sup, rows]) => {
          const text = `Hola${sup !== "Sin proveedor registrado" ? ` ${sup}` : ""}, soy de ${name}. Quisiera pedir:\n${rows.map(r => `• ${r.quantity} × ${r.name}`).join("\n")}\nGracias.`;
          return <section key={sup} className="fv-create fv-cash-card" style={{ marginBottom: 12 }}>
            <header className="fv-report-head"><h3>{sup}</h3><span className="fv-actions"><a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/?text=${encodeURIComponent(text)}`}>Enviar pedido por WhatsApp</a>
              {can(c.access, "products_edit") && <Link className="fv-button secondary" href={`/erp/${org}/compras`}>Registrar la compra</Link>}</span></header>
            <div className="fv-table-scroll"><table><thead><tr><th>Producto</th><th>Queda</th><th>Vendes al día</th><th>Alcanza</th><th>Pedir</th><th>Costo aprox.</th></tr></thead><tbody>
              {rows.map(r => <tr key={r.product_id}><td><strong>{r.name}</strong>{r.category ? <><br /><small className="fv-muted">{r.category}</small></> : null}</td><td>{r.stock}</td><td>{r.per_day}</td>
                <td>{r.stock <= 0 ? <span className="fv-pill is-bad">Agotado</span> : r.cover_days == null ? "—" : <span className={`fv-pill ${r.cover_days < 3 ? "is-bad" : "is-wait"}`}>{r.cover_days} días</span>}</td>
                <td><b>{r.quantity}</b></td><td>{r.unit_cost == null ? "—" : fmt(r.quantity * r.unit_cost)}</td></tr>)}
            </tbody></table></div>
          </section>;
        })}
      {stuck.length > 0 && <section className="fv-create fv-cash-card"><h3>No se vendieron en 30 días</h3><p className="fv-caption">Tienen stock pero nadie los compró. No compres más hasta que roten: ponles una promoción o muévelos de lugar.</p>
        <ul className="fv-lines">{stuck.slice(0, 30).map(s => <li key={s.id}><span>{s.name}</span><span>{n(s.stock)} en stock{s.value ? ` · ${fmt(s.value)}` : ""}</span></li>)}</ul></section>}
    </>;
  }

  if (id === "vencimientos") {
    const monthStart = `${today.slice(0, 7)}-01`;
    const next = new Date(`${today}T12:00:00Z`); next.setUTCDate(next.getUTCDate() + 1);
    const [lotRes, lossRes, members, sales] = await Promise.all([
      c.db.rpc("lot_status", { p_org: org }),
      c.db.from("stock_losses").select("id,product_id,quantity,reason,note,unit_cost,created_at,user_id,product:products(name),lot:product_lots(lot_code,expires_on)")
        .eq("org_id", org).gte("created_at", `${monthStart}T05:00:00Z`).order("created_at", { ascending: false }).limit(300),
      c.db.from("organization_members").select("user_id,display_name").eq("org_id", org),
      can(c.access, "finance") ? c.db.rpc("sales_summary", { p_org: org, p_from: monthStart, p_to: next.toISOString().slice(0, 10), p_currency: cur }) : Promise.resolve({ data: null }),
    ]);
    if (lotRes.error) return <>{heading(`MERCADERÍA / ${name}`, title, "", org)}{failed("los vencimientos")}</>;
    const lots = ((lotRes.data ?? []) as LotStatus[]).map(l => ({ ...l, quantity: n(l.quantity), remaining: n(l.remaining), days_left: n(l.days_left), unit_cost: l.unit_cost == null ? null : n(l.unit_cost), unit_price: l.unit_price == null ? null : n(l.unit_price) }));
    const names = new Map(((members.data ?? []) as { user_id: string; display_name: string | null }[]).map(m => [m.user_id, m.display_name] as const));
    const first = <T,>(v: T | T[] | null | undefined): T | null => (Array.isArray(v) ? v[0] : v) ?? null;
    type RawLoss = { id: string; product_id: string; quantity: number | string; reason: string; note: string | null; unit_cost: number | string | null; created_at: string; user_id: string; product: unknown; lot: unknown };
    const losses: LossRow[] = ((lossRes.data ?? []) as unknown as RawLoss[]).map(r => {
      const lot = first(r.lot as { lot_code: string | null; expires_on: string } | null);
      return { id: r.id, product_id: r.product_id, quantity: n(r.quantity), reason: r.reason, note: r.note, unit_cost: r.unit_cost == null ? null : n(r.unit_cost), created_at: r.created_at,
        product_name: first(r.product as { name: string } | null)?.name ?? "Producto", lot_code: lot?.lot_code ?? null, expires_on: lot?.expires_on ?? null, user_name: names.get(r.user_id) ?? null } as LossRow;
    });
    const salesTotal = sales.data ? n((sales.data as { sales_total?: number | string }).sales_total) : null;
    return <>{heading(`MERCADERÍA / ${name}`, title, "Lo que vence pronto, lo vencido y cada merma con su motivo (vencido, roto, robo, consumo). Así sabes cuánto pierdes y lo frenas a tiempo.", org, liveInventory)}
      <ExpiryOverview org={org} lots={lots} losses={losses} currency={cur} salesTotal={salesTotal} canEdit={can(c.access, "products_edit")} />
      <p className="fv-caption">Registra las fechas de vencimiento al recibir mercadería en <Link className="fv-link" href={`/erp/${org}/compras`}>Compras</Link> o en la ficha de cada producto (Inventario).</p>
    </>;
  }

  return null;
}
