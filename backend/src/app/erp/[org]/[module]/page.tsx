import Link from "next/link";
import { notFound } from "next/navigation";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed, featureLimit, can, hasFeature, visibleModules } from "@/lib/erp/access";
import DataTable from "@/components/erp/DataTable";
import CreateRecord from "@/components/erp/CreateRecord";
import ProductBoard, { type ProductRow } from "@/components/erp/ProductBoard";
import { ExpiryOverview } from "@/components/erp/LotsAndLosses";
import type { LossRow, LotStatus } from "@/lib/erp/lots";
import LiveRefresh from "@/components/erp/LiveRefresh";
import ReceiptsBoard from "@/components/erp/ReceiptsBoard";
import type { ReceiptRow } from "@/lib/erp/receipts";
import ClientsBoard from "@/components/erp/ClientsBoard";
import CashBoard from "@/components/erp/CashBoard";
import ShiftPanel, { type ShiftRow } from "@/components/erp/ShiftPanel";
import BranchesBoard, { type Branch, type BranchProduct, type TransferRow } from "@/components/erp/BranchesBoard";
import PurchasesBoard, { type PurchaseProduct } from "@/components/erp/PurchasesBoard";
import PaymentsBoard from "@/components/erp/PaymentsBoard";
import LoyaltyBoard from "@/components/erp/LoyaltyBoard";
import type { Coupon, LoyaltyRow, Promotion } from "@/lib/erp/loyalty";
import { monthBounds, parseMonth, type PaymentRow } from "@/lib/erp/payments";
import { lastSupplierByProduct, suggestOrder, type PurchaseRow, type Velocity } from "@/lib/erp/purchases";
import { cashierBreakdown, methodLabel, type CashMove, type DayClosing } from "@/lib/erp/cash";
import type { DaySummary } from "@/lib/dayclose";
import { limaDate, parseRange } from "@/lib/erp/receipts";
import { mergeClients, type ClientActivity, type ClientBalance, type ClientRow } from "@/lib/erp/clients";
import { byMethod, dailySeries, grossMargin } from "@/lib/erp/reports";
import { topProducts } from "@/lib/erp/dashboard";

const liveProducts = ["products"] as const;
/** Next calendar day (sales_summary takes an exclusive end date). */
const addDay = (d: string) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + 1); return x.toISOString().slice(0, 10); };
const liveReceipts = ["invoices"] as const;
const liveClients = ["clients", "credit_ledger", "invoices"] as const;
const liveCash = ["cash_movements", "payments", "invoices", "credit_ledger", "cash_shifts"] as const;
const livePurchases = ["products"] as const;
const livePayments = ["payments"] as const;
const liveInventory = ["products", "product_lots", "stock_losses"] as const;
import NewInvoice from "@/components/NewInvoice";
import { money } from "@/lib/schemas";

export default async function ModulePage({ params, searchParams }: { params: Promise<{ org: string; module: string }>; searchParams: Promise<{ page?: string; from?: string; to?: string; dia?: string; desde?: string; hasta?: string; mes?: string }> }) {
  const { org, module: id } = await params;
  const c = await workspaceContext(org);
  const m = modules.find(m => m.id === id);
  if (!m || !moduleAllowed(m, c.license, c.access, c.sector)) notFound();
  const title = id === "clientes" && c.sector === "consultorio" ? "Pacientes" : id === "clientes" && c.sector === "educacion" ? "Alumnos y contactos" : m.title;
  if (id === "reportes") {
    const search = await searchParams;
    const today = limaDate(new Date());
    const from = search.from ?? `${today.slice(0, 7)}-01`;
    const to = search.to ?? today;
    const validDate = (v: string) => /^\d{4}-\d{2}-\d{2}$/.test(v) && Number.isFinite(Date.parse(v)) && new Date(v).toISOString().slice(0, 10) === v;
    const valid = validDate(from) && validDate(to) && from <= to && Date.parse(to) - Date.parse(from) <= 366 * 86400000;
    const cur = c.organization.currency || "PEN";
    const end = valid ? addDay(to) : today;
    const [summary, invs, items, pays, buys, losses] = valid ? await Promise.all([
      c.db.rpc("sales_summary", { p_org: org, p_from: from, p_to: end, p_currency: cur }),
      c.db.from("invoices").select("issue_date,amt_total").eq("org_id", org).gte("issue_date", from).lte("issue_date", to).neq("status", "draft").is("voided_at", null).eq("currency", cur).limit(5000),
      c.db.from("invoice_items").select("description,quantity,unit_price,product:products(unit_cost),invoice:invoices!inner(org_id,issue_date,status,voided_at)").eq("invoice.org_id", org).gte("invoice.issue_date", from).lte("invoice.issue_date", to).neq("invoice.status", "draft").is("invoice.voided_at", null).limit(8000),
      c.db.from("payments").select("method,amount").eq("org_id", org).gte("paid_on", from).lte("paid_on", to).limit(8000),
      c.db.from("retail_receipts").select("total_cents").eq("org_id", org).gte("created_at", `${from}T05:00:00Z`).lt("created_at", `${end}T05:00:00Z`).limit(2000),
      c.db.from("stock_losses").select("quantity,unit_cost").eq("org_id", org).gte("created_at", `${from}T05:00:00Z`).lt("created_at", `${end}T05:00:00Z`).limit(3000),
    ]) : [null, null, null, null, null, null];
    const sum = (summary?.data ?? null) as { sales_total?: number | string; sales_count?: number; credit_notes_total?: number | string; drafts_count?: number } | null;
    const total = Number(sum?.sales_total ?? 0), count = Number(sum?.sales_count ?? 0);
    const series = dailySeries((invs?.data ?? []) as { issue_date: string; amt_total: number }[], from, to);
    type RawItem = { description: string; quantity: number; unit_price: number; product: { unit_cost: number | null } | { unit_cost: number | null }[] | null };
    const itemRows = ((items?.data ?? []) as unknown as RawItem[]).map(i => ({ ...i, unit_cost: (Array.isArray(i.product) ? i.product[0]?.unit_cost : i.product?.unit_cost) ?? null }));
    const top = topProducts(itemRows, 10);
    const margin = grossMargin(itemRows);
    const methods = byMethod((pays?.data ?? []) as { method: string; amount: number }[]);
    const purchases = ((buys?.data ?? []) as { total_cents: number }[]).reduce((a, r) => a + Number(r.total_cents), 0) / 100;
    const shrink = ((losses?.data ?? []) as { quantity: number; unit_cost: number | null }[]).reduce((a, r) => a + Number(r.quantity) * Number(r.unit_cost ?? 0), 0);
    const fmt = (v: number) => money(v, cur);
    const short = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
    return <><section className="fv-heading"><p className="fv-eyebrow">CONTROL COMERCIAL / {c.organization.name}</p><h1>Reportes</h1><p>Ventas emitidas (sin anuladas ni borradores, menos notas de crédito), cobros, compras y merma del periodo.</p></section>
      <form className="fv-create fv-fiado-form"><label><span>Desde</span><input type="date" name="from" defaultValue={from} required /></label><label><span>Hasta (incluido)</span><input type="date" name="to" defaultValue={to} required /></label><button className="fv-button">Ver periodo</button></form>
      {!valid ? <div className="fv-empty" role="alert"><h2>Revisa las fechas</h2><p>Elige un intervalo válido de hasta 366 días.</p></div>
        : summary?.error || !sum ? <div className="fv-empty" role="alert"><h2>No pudimos cargar el reporte</h2><p>Pulsa Actualizar para reintentar.</p></div>
        : <section className="fv-board">
          <div className="fv-kpis fv-kpis-4">
            <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Ventas netas</span><strong>{fmt(total)}</strong><small>{count} {count === 1 ? "venta" : "ventas"}{Number(sum.credit_notes_total ?? 0) ? ` · notas de crédito ${fmt(Number(sum.credit_notes_total))}` : ""}</small></div>
            <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Ticket promedio</span><strong>{fmt(count ? total / count : 0)}</strong><small>{series.best ? `mejor día ${short(series.best.day)}: ${fmt(series.best.total)}` : "sin ventas en el periodo"}</small></div>
            <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Margen bruto estimado</span><strong>{margin.margin === null ? "—" : `${margin.margin} %`}</strong><small>{margin.margin === null ? "añade el costo de tus productos" : `${fmt(margin.profit)} · ${margin.coverage} % de la venta tiene costo`}</small></div>
            <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Compras y merma</span><strong>{fmt(purchases)}</strong><small>merma {fmt(shrink)}{total ? ` (${Math.round((shrink / total) * 1000) / 10} % de la venta)` : ""}</small></div>
          </div>
          <figure className="fv-rhythm fv-month-rhythm fv-create" aria-label="Ventas por día del periodo">
            <div className="fv-rhythm-bars" style={{ "--cols": series.days.length } as React.CSSProperties}>
              {series.days.map(d => <span key={d.day} className={series.best?.day === d.day ? "is-peak" : ""} style={{ "--h": d.height } as React.CSSProperties} title={`${short(d.day)}: ${fmt(d.total)} en ${d.count} ${d.count === 1 ? "venta" : "ventas"}`} />)}
            </div>
            <figcaption>{series.days.length} días · {short(from)} – {short(to)}</figcaption>
          </figure>
          <div className="fv-cash-grid">
            <section className="fv-create fv-cash-card"><h3>Lo que más se vendió</h3>
              {top.length ? <ol className="fv-top">{top.map(t => <li key={t.name}><span>{t.name}</span><small>{Number.isInteger(t.units) ? t.units : t.units.toFixed(2)} u.</small><strong>{fmt(t.revenue)}</strong></li>)}</ol> : <p className="fv-muted">Sin ventas en el periodo.</p>}
            </section>
            <section className="fv-create fv-cash-card"><h3>Cómo te pagaron</h3>
              {methods.length ? <ul className="fv-shares">{methods.map(m => <li key={m.method} style={{ "--share": `${m.share}%` } as React.CSSProperties}><span>{methodLabel[m.method] ?? m.method}</span><span>{fmt(m.value)} · {m.share} %</span><i aria-hidden="true" /></li>)}</ul> : <p className="fv-muted">Sin cobros registrados en el periodo.</p>}
            </section>
          </div>
        </section>}
    </>;
  }
  if (id === "plan") {
    const team = await c.db.rpc("team_members", { p_org: org });
    const used = Array.isArray(team.data) ? team.data.length : null;
    const maxUsers = featureLimit(c.license, "max_users");
    const maxBranches = featureLimit(c.license, "max_branches");
    const planName = ({ BASICO: "Básico", PRO: "Pro", EMPRESA: "Empresa" } as Record<string, string>)[c.license.plan ?? ""] ?? (c.license.plan || "Sin asignar");
    const statusText = c.license.status === "prueba" ? "En prueba gratis" : c.license.status === "activa" ? "Activo" : c.license.status || "Sin verificar";
    const included = visibleModules(c.license, c.access, c.sector).filter(x => !["plan", "configuracion"].includes(x.id));
    return <><section className="fv-heading"><p className="fv-eyebrow">SOLVEX HUB / {c.organization.name}</p><h1>Mi plan</h1><p>Una sola licencia para el móvil y la web. Los cambios de plan y los pagos se hacen en Solvex Hub.</p></section>
      <section className="fv-board">
        <div className="fv-kpis">
          <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Plan</span><strong>{planName}</strong><small>{statusText}</small></div>
          <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Usuarios</span><strong>{used ?? "—"}{maxUsers === -1 ? "" : ` de ${maxUsers}`}</strong><small>{maxUsers === -1 ? "sin límite" : "incluidos en tu plan"}</small></div>
          <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Locales</span><strong>{maxBranches === -1 ? "Sin límite" : maxBranches}</strong><small>empresas o sucursales</small></div>
        </div>
        {c.license.message && <p className="fv-hint">{c.license.message}</p>}
        <section className="fv-create fv-cash-card"><h3>Lo que tienes en la web con tu rol</h3>
          <ul className="fv-shortcuts">{included.map(x => <li key={x.id}><Link href={`/erp/${org}/${x.id}`}>{x.title}</Link></li>)}</ul>
        </section>
      </section></>;
  }
  if (id === "configuracion") {
    const extra = await c.db.from("organizations").select("trade_name,ubigeo,district,province,department,series_factura,series_boleta").eq("id", org).maybeSingle();
    const e = (extra.data ?? {}) as Record<string, string | null>;
    const rows: [string, string | null | undefined][] = [
      ["Razón social", c.organization.name], ["Nombre comercial", e.trade_name], ["RUC", c.organization.tax_id], ["Dirección fiscal", c.organization.address],
      ["Distrito / provincia", [e.district, e.province, e.department].filter(Boolean).join(" · ")], ["Ubigeo", e.ubigeo],
      ["Moneda", c.organization.currency], ["IGV por defecto", c.organization.default_tax_rate != null ? `${c.organization.default_tax_rate} %` : null],
      ["Serie de facturas", e.series_factura], ["Serie de boletas", e.series_boleta],
    ];
    const missing = rows.filter(([, v]) => !v).map(([k]) => k);
    return <><section className="fv-heading"><p className="fv-eyebrow">EMPRESA / {c.organization.name}</p><h1>Configuración</h1><p>Los datos que salen en tus comprobantes. Se editan en el móvil (Ajustes → Negocio) y aquí se ven al instante.</p></section>
      {missing.length > 0 && <p className="fv-hint" role="status">Te falta completar: {missing.join(", ")}. Sin ellos SUNAT puede rechazar tus comprobantes.</p>}
      <dl className="fv-details">{rows.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value || "Sin configurar"}</dd></div>)}</dl></>;
  }
  if (id === "equipo") {
    const result = await c.db.rpc("team_members", { p_org: org });
    const roleLabel: Record<string, string> = { owner: "Dueño", admin: "Administrador", cajero: "Cajero", finanzas: "Finanzas", tecnico: "Técnico", vendedor: "Vendedor" };
    type Member = { display_name: string | null; email: string | null; role: string; staff_role: string | null };
    const members = (result.data ?? []) as Member[];
    return <><section className="fv-heading"><p className="fv-eyebrow">PERSONAS / {c.organization.name}</p><h1>Equipo</h1><p>Quién entra a tu empresa y qué puede hacer. Las invitaciones y los cambios de rol se hacen en el móvil (Ajustes → Equipo).</p></section>
      {result.error ? <div className="fv-empty" role="alert"><h2>No se pudo cargar el equipo</h2><p>Pulsa Actualizar para reintentar.</p></div>
        : <ul className="fv-branches">{members.map((mb, i) => {
          const role = mb.role === "owner" || mb.role === "admin" ? mb.role : mb.staff_role ?? "cajero";
          return <li key={i}><div><strong>{mb.display_name || mb.email || "Sin nombre"}</strong><small>{mb.email ?? ""}</small></div><span>{roleLabel[role] ?? role}</span><span /><span /></li>;
        })}</ul>}
    </>;
  }
  if (id === "comprobantes") {
    // Same receipts the mobile app issues, with their SUNAT documents (RLS: company members).
    const search = await searchParams;
    const range = parseRange(search.desde, search.hasta);
    let query = c.db.from("invoices")
      .select("id,number,issue_date,status,currency,doc_kind,amt_total,voided_at,client:clients(name,tax_id),fiscal:fiscal_documents(doc_type,series,correlative,status,sunat_code,sunat_message,issued_at)")
      .eq("org_id", org);
    if (range) query = query.gte("issue_date", range.from).lte("issue_date", range.to);
    const result = await query.order("issue_date", { ascending: false }).order("created_at", { ascending: false }).limit(300);
    const receipts: ReceiptRow[] = ((result.data ?? []) as unknown as (Omit<ReceiptRow, "client" | "fiscal"> & { client: unknown; fiscal: unknown })[]).map(r => ({
      ...r,
      client: (Array.isArray(r.client) ? r.client[0] : r.client) as ReceiptRow["client"] ?? null,
      fiscal: (Array.isArray(r.fiscal) ? r.fiscal[0] : r.fiscal) as ReceiptRow["fiscal"] ?? null,
    }));
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">FACTURACIÓN / {c.organization.name}</p><LiveRefresh org={org} tables={liveReceipts} /></div><h1>Comprobantes</h1><p>Boletas, facturas y notas emitidas en el móvil o aquí, con su estado en SUNAT, XML, CDR y versión imprimible.</p></section>
      <NewInvoice key={org} org={org} currency={c.organization.currency || "PEN"} defaultTaxRate={Number(c.organization.default_tax_rate ?? 18)} voiceAllowed={hasFeature(c.license, "voz")} />
      {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los comprobantes</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <ReceiptsBoard org={org} rows={receipts} currency={c.organization.currency || "PEN"} range={range} capped={receipts.length >= 300} />}
    </>;
  }
  if (id === "compras") {
    // The mobile «Compras y recepción»: retail_receive moves stock, cost, kardex, expense and till together.
    if (!c.access.is_admin) return <><section className="fv-heading"><p className="fv-eyebrow">COMPRAS / {c.organization.name}</p><h1>Compras</h1></section><div className="fv-empty"><h2>Solo el dueño o un administrador</h2><p>Las compras mueven el stock, el costo y la caja; pídele acceso al dueño.</p></div></>;
    const [receipts, products, velocity] = await Promise.all([
      c.db.from("retail_receipts").select("id,supplier_name,document_ref,payment_method,total_cents,created_at,items:retail_receipt_items(product_id,quantity,unit_cost_cents,line_total_cents,stock_before,stock_after,product:products(name)),paid:retail_purchase_settlements(method,paid_cents,created_at)")
        .eq("org_id", org).gt("total_cents", 0).order("created_at", { ascending: false }).limit(200),
      c.db.from("products").select("id,name,unit,unit_cost,stock").eq("org_id", org).eq("active", true).in("unit", ["NIU", "KGM"]).order("name").limit(1000),
      c.db.rpc("product_velocity", { p_org: org, p_days: 30 }),
    ]);
    type Raw = Omit<PurchaseRow, "items" | "paid" | "total_cents"> & { total_cents: number | string; items: (Omit<PurchaseRow["items"][number], "name"> & { product: { name: string } | { name: string }[] | null })[]; paid: PurchaseRow["paid"] | NonNullable<PurchaseRow["paid"]>[] };
    const rows: PurchaseRow[] = ((receipts.data ?? []) as unknown as Raw[]).map(r => ({
      ...r, total_cents: Number(r.total_cents),
      items: (r.items ?? []).map(({ product, ...i }) => ({ ...i, name: (Array.isArray(product) ? product[0]?.name : product?.name) ?? "Producto", quantity: Number(i.quantity), unit_cost_cents: Number(i.unit_cost_cents), line_total_cents: Number(i.line_total_cents), stock_before: Number(i.stock_before), stock_after: Number(i.stock_after) })),
      paid: (Array.isArray(r.paid) ? r.paid[0] : r.paid) ?? null,
    }));
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">COMPRAS / {c.organization.name}</p><LiveRefresh org={org} tables={livePurchases} /></div><h1>Compras a proveedores</h1><p>Registra lo que te llega: el stock, el costo y la caja se actualizan juntos, igual que en el móvil. Lleva lo que debes a cada proveedor.</p></section>
      {receipts.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar las compras</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <PurchasesBoard org={org} rows={rows} products={((products.data ?? []) as PurchaseProduct[]).map(p => ({ ...p, unit_cost: p.unit_cost === null ? null : Number(p.unit_cost), stock: p.stock === null ? null : Number(p.stock) }))} currency={c.organization.currency || "PEN"} month={limaDate(new Date()).slice(0, 7)}
            suggestions={suggestOrder(((velocity.data ?? []) as Velocity[]).filter(v => ((products.data ?? []) as PurchaseProduct[]).some(p => p.id === v.product_id)), lastSupplierByProduct(rows))} />}
    </>;
  }
  if (id === "puntos" || id === "promociones") {
    // The mobile «Puntos y fidelización» and «Precios y promociones», on the same tables (RLS + Hub feature guards).
    const points = id === "puntos";
    const [settings, balances, promos, coupons] = await Promise.all([
      points ? c.db.from("org_settings").select("loyalty_rate").eq("org_id", org).maybeSingle() : Promise.resolve({ data: null, error: null }),
      points ? c.db.rpc("loyalty_balances", { p_org: org }) : Promise.resolve({ data: [], error: null }),
      points ? Promise.resolve({ data: [], error: null }) : c.db.from("promotions").select("id,name,kind,value,min_qty,starts_on,ends_on,active,product_ids").eq("org_id", org).order("created_at", { ascending: false }).limit(200),
      c.db.from("coupons").select("id,code,kind,value,max_uses,uses,expires_on,active").eq("org_id", org).order("created_at", { ascending: false }).limit(200),
    ]);
    const failed = balances.error || promos.error || coupons.error;
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{points ? "FIDELIZACIÓN" : "PRECIOS"} / {c.organization.name}</p><LiveRefresh org={org} tables={livePayments} /></div><h1>{title}</h1>
      <p>{points ? "Cada cobro a un cliente identificado le suma puntos; aquí ves quién tiene más y registras sus canjes." : "Descuentos y cupones que el punto de venta del móvil aplica solo en sus fechas."}</p></section>
      {failed ? <div className="fv-empty" role="alert"><h2>No pudimos cargar esta sección</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <LoyaltyBoard org={org} view={points ? "puntos" : "promociones"} currency={c.organization.currency || "PEN"} today={limaDate(new Date())}
            rate={settings.data ? Number((settings.data as { loyalty_rate: number | string }).loyalty_rate) || null : null}
            balances={((balances.data ?? []) as LoyaltyRow[]).map(b => ({ ...b, points: Number(b.points) }))}
            promotions={((promos.data ?? []) as Promotion[]).map(p => ({ ...p, value: Number(p.value), min_qty: p.min_qty == null ? null : Number(p.min_qty) }))}
            coupons={((coupons.data ?? []) as Coupon[]).map(x => ({ ...x, value: Number(x.value), uses: Number(x.uses ?? 0), max_uses: x.max_uses == null ? null : Number(x.max_uses) }))}
            canEditPromos={can(c.access, "products_edit")} canSetRate={can(c.access, "settings")} canRedeem={can(c.access, "collect")} />}
    </>;
  }
  if (id === "sucursales") {
    // Each store is its own company (stock, receipts, till). The owner sees all of them and moves goods between them.
    const memberships = await c.db.from("organization_members").select("org_id,role,organization:organizations(id,name)").eq("user_id", c.user.id).in("role", ["owner", "admin"]).limit(20);
    type M = { org_id: string; organization: { id: string; name: string } | { id: string; name: string }[] | null };
    const orgs = ((memberships.data ?? []) as unknown as M[]).map(m => { const o = Array.isArray(m.organization) ? m.organization[0] : m.organization; return { id: m.org_id, name: o?.name ?? "Local" }; });
    const today = limaDate(new Date());
    const monthStart = `${today.slice(0, 7)}-01`;
    const next = new Date(`${today}T12:00:00Z`); next.setUTCDate(next.getUTCDate() + 1);
    const tomorrow = next.toISOString().slice(0, 10); // sales_summary takes an exclusive end date
    const cur = c.organization.currency || "PEN";
    const ids = orgs.map(o => o.id);
    const [stats, prods, transfers] = await Promise.all([
      Promise.all(orgs.map(o => Promise.all([
        c.db.rpc("sales_summary", { p_org: o.id, p_from: today, p_to: tomorrow, p_currency: cur }),
        c.db.rpc("sales_summary", { p_org: o.id, p_from: monthStart, p_to: tomorrow, p_currency: cur }),
      ]))),
      c.db.from("products").select("id,org_id,name,stock,unit,reorder_point").in("org_id", ids).eq("active", true).neq("unit", "ZZ").order("name").limit(3000),
      c.db.from("stock_transfers").select("id,created_at,quantity,note,from_org,to_org,from_product").or(`from_org.eq.${org},to_org.eq.${org}`).order("created_at", { ascending: false }).limit(30),
    ]);
    const productRows = (prods.data ?? []) as (BranchProduct & { reorder_point: number | null })[];
    const names = new Map(orgs.map(o => [o.id, o.name] as const));
    const productNames = new Map(productRows.map(p => [p.id, p.name] as const));
    const branches: Branch[] = orgs.map((o, i) => {
      const [d, m] = stats[i];
      const sd = (d.data ?? {}) as { sales_total?: number | string; sales_count?: number };
      const sm = (m.data ?? {}) as { sales_total?: number | string };
      return { id: o.id, name: o.name, today: Number(sd.sales_total ?? 0), todayCount: Number(sd.sales_count ?? 0), month: Number(sm.sales_total ?? 0), current: o.id === org,
        low: productRows.filter(p => p.org_id === o.id && p.stock != null && p.reorder_point != null && Number(p.stock) <= Number(p.reorder_point)).length };
    });
    const rows: TransferRow[] = ((transfers.data ?? []) as { id: string; created_at: string; quantity: number | string; note: string | null; from_org: string; to_org: string; from_product: string }[])
      .map(t => ({ id: t.id, created_at: t.created_at, quantity: Number(t.quantity), note: t.note, from: names.get(t.from_org) ?? "Otro local", to: names.get(t.to_org) ?? "Otro local", product: productNames.get(t.from_product) ?? "Producto" }));
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">SUCURSALES / {c.organization.name}</p><LiveRefresh org={org} tables={liveProducts} /></div><h1>{title}</h1>
      <p>Tus locales en una sola vista: ventas de hoy y del mes, stock bajo y traslados de mercadería entre ellos.</p></section>
      {memberships.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar tus locales</h2><p>Pulsa Actualizar para reintentar.</p></div>
        : <BranchesBoard org={org} branches={branches} currency={cur} canTransfer={c.access.is_admin === true}
            products={productRows.map(p => ({ id: p.id, org_id: p.org_id, name: p.name, unit: p.unit, stock: p.stock == null ? null : Number(p.stock) }))} transfers={rows} />}
    </>;
  }
  if (id === "cobros") {
    // Every payment recorded against a receipt, here or on the mobile app (RLS: company members).
    const today = limaDate(new Date());
    const month = parseMonth((await searchParams).mes, today);
    const { from, to } = monthBounds(month);
    const result = await c.db.from("payments")
      .select("id,amount,paid_on,method,note,created_at,invoice:invoices(id,number,currency,amt_total,client:clients(name,tax_id),fiscal:fiscal_documents(series,correlative))")
      .eq("org_id", org).gte("paid_on", from).lte("paid_on", to)
      .order("paid_on", { ascending: false }).order("created_at", { ascending: false }).limit(500);
    const one = <T,>(v: T | T[] | null | undefined): T | null => (Array.isArray(v) ? v[0] : v) ?? null;
    type Raw = Omit<PaymentRow, "invoice" | "amount"> & { amount: number | string; invoice: unknown };
    type RawInvoice = Omit<NonNullable<PaymentRow["invoice"]>, "client" | "fiscal" | "amt_total"> & { amt_total: number | string | null; client: unknown; fiscal: unknown };
    const rows: PaymentRow[] = ((result.data ?? []) as unknown as Raw[]).map(p => {
      const inv = one(p.invoice as RawInvoice | RawInvoice[] | null);
      return { ...p, amount: Number(p.amount), invoice: inv ? { ...inv, amt_total: inv.amt_total === null ? null : Number(inv.amt_total), client: one(inv.client as NonNullable<PaymentRow["invoice"]>["client"]), fiscal: one(inv.fiscal as NonNullable<PaymentRow["invoice"]>["fiscal"]) } : null };
    });
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">COBROS / {c.organization.name}</p><LiveRefresh org={org} tables={livePayments} /></div><h1>Cobros</h1><p>Todo lo que te pagaron por tus comprobantes, mes a mes y por medio de pago. Los cobros del móvil aparecen aquí al instante.</p></section>
      {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los cobros</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <PaymentsBoard rows={rows} currency={c.organization.currency || "PEN"} month={month} today={today} capped={rows.length >= 500} />}
    </>;
  }
  if (id === "caja") {
    // The mobile «Caja y cierre del día»: the database computes the summary with the viewer's rights.
    const today = limaDate(new Date());
    const asked = (await searchParams).dia ?? "";
    const day = /^\d{4}-\d{2}-\d{2}$/.test(asked) && asked <= today && Number.isFinite(Date.parse(asked)) ? asked : today;
    const finance = can(c.access, "finance");
    const [summary, moves, closing, dayPayments, members, shiftRes, mineRes] = await Promise.all([
      c.db.rpc("day_summary", { p_org: org, p_day: day }),
      c.db.from("cash_movements").select("id,kind,amount,method,note,created_at,user_id").eq("org_id", org).eq("day", day).order("created_at"),
      c.db.from("day_closings").select("counted_cash,expected_cash,difference,note,created_at").eq("org_id", org).eq("day", day).maybeSingle(),
      finance ? c.db.from("payments").select("user_id,method,amount").eq("org_id", org).eq("paid_on", day).limit(3000) : Promise.resolve({ data: [] }),
      finance ? c.db.from("organization_members").select("user_id,display_name").eq("org_id", org) : Promise.resolve({ data: [] }),
      finance ? c.db.rpc("shift_report", { p_org: org, p_from: day, p_to: day }) : Promise.resolve({ data: null, error: null }),
      c.db.from("cash_shifts").select("opened_at,opening_float").eq("org_id", org).eq("user_id", c.user.id).is("closed_at", null).maybeSingle(),
    ]);
    const num = (v: unknown) => (v == null ? null : Number(v));
    const shifts: ShiftRow[] | null = finance && !shiftRes.error ? ((shiftRes.data ?? []) as Record<string, unknown>[]).map(r => ({
      id: String(r.id), name: String(r.name ?? "Sin nombre"), opened_at: String(r.opened_at), closed_at: (r.closed_at as string | null) ?? null,
      opening_float: Number(r.opening_float), cash_sales: Number(r.cash_sales), digital_sales: Number(r.digital_sales), cash_in: Number(r.cash_in), cash_out: Number(r.cash_out),
      expected_cash: Number(r.expected_cash), counted_cash: num(r.counted_cash), difference: num(r.difference), note: (r.note as string | null) ?? null,
    })) : null;
    const mine = mineRes.data ? { opened_at: String((mineRes.data as { opened_at: string }).opened_at), opening_float: Number((mineRes.data as { opening_float: number }).opening_float) } : null;
    const cashMoves = ((moves.data ?? []) as CashMove[]).map(m => ({ ...m, amount: Number(m.amount) }));
    const cashiers = finance ? cashierBreakdown((dayPayments.data ?? []) as { user_id: string; method: string; amount: number }[], cashMoves,
      new Map(((members.data ?? []) as { user_id: string; display_name: string | null }[]).map(m => [m.user_id, m.display_name] as const))) : [];
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">CAJA / {c.organization.name}</p><LiveRefresh org={org} tables={liveCash} /></div><h1>Caja y cierre del día</h1><p>Apertura, retiros, cobros por medio de pago y arqueo ciego. Es la misma caja que lleva el móvil.</p></section>
      {summary.error || !summary.data ? <div className="fv-empty" role="alert"><h2>No pudimos cargar la caja</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <CashBoard org={org} day={day} today={today} summary={summary.data as DaySummary}
            moves={cashMoves} cashiers={cashiers}
            closing={(closing.data ?? null) as DayClosing | null} showExpected={finance} />}
      {!summary.error && summary.data && !mineRes.error && <ShiftPanel org={org} mine={mine} shifts={shifts} currency={c.organization.currency || "PEN"} isToday={day === today} />}
    </>;
  }
  if (id === "clientes") {
    // Same customers as the mobile app, joined with their fiado balance and purchase history.
    const [list, balances, activity] = await Promise.all([
      c.db.from("clients").select("id,name,tax_id,doc_type,email,phone,address,district,notes,credit_limit,created_at").eq("org_id", org).order("name").order("id").limit(1000),
      c.db.rpc("credit_balances", { p_org: org }),
      c.db.rpc("client_activity", { p_org: org }),
    ]);
    const clients = mergeClients((list.data ?? []) as ClientRow[], (balances.data ?? []) as ClientBalance[], (activity.data ?? []) as ClientActivity[], limaDate(new Date()));
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">CLIENTES / {c.organization.name}</p><LiveRefresh org={org} tables={liveClients} /></div><h1>{title}</h1><p>Con el DNI o RUC se completan solos. Ve lo que compran, cuánto deben de fiado y registra sus abonos: todo se ve igual en el móvil.</p></section>
      {list.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los clientes</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <ClientsBoard org={org} clients={clients} currency={c.organization.currency || "PEN"} canFiado={hasFeature(c.license, "fiados") && can(c.access, "collect")} />}
    </>;
  }
  if (id === "productos" || id === "inventario") {
    // One catalog, shared with the mobile POS: same rows, photos and permissions.
    const result = await c.db.from("products").select("id,name,unit_price,unit,active,category,stock,reorder_point,unit_cost,image_path,icbper")
      .eq("org_id", org).order("name", { ascending: true }).order("id").limit(500);
    const rows = (result.data ?? []) as Omit<ProductRow, "photo_url">[];
    const paths = rows.map(r => r.image_path).filter((p): p is string => !!p);
    const signed = paths.length ? await c.db.storage.from("org-media").createSignedUrls(paths, 3600) : { data: [] };
    const urls = new Map((signed.data ?? []).map(s => [s.path, s.signedUrl] as const));
    const products: ProductRow[] = rows.map(r => ({ ...r, photo_url: r.image_path ? urls.get(r.image_path) ?? null : null }));
    // Expiry dates and shrinkage live in Inventario (stock feature); the catalog view stays as it was.
    const inventory = id === "inventario";
    const today = limaDate(new Date());
    const monthStart = `${today.slice(0, 7)}-01`;
    const [lotRes, lossRes, members, sales] = inventory ? await Promise.all([
      c.db.rpc("lot_status", { p_org: org }),
      c.db.from("stock_losses").select("id,product_id,quantity,reason,note,unit_cost,created_at,user_id,product:products(name),lot:product_lots(lot_code,expires_on)")
        .eq("org_id", org).gte("created_at", `${monthStart}T05:00:00Z`).order("created_at", { ascending: false }).limit(300),
      c.db.from("organization_members").select("user_id,display_name").eq("org_id", org),
      can(c.access, "finance") ? c.db.rpc("sales_summary", { p_org: org, p_from: monthStart, p_to: addDay(today), p_currency: c.organization.currency || "PEN" }) : Promise.resolve({ data: null }),
    ]) : [{ data: [] }, { data: [] }, { data: [] }, { data: null }];
    const lots = ((lotRes.data ?? []) as LotStatus[]).map(l => ({ ...l, quantity: Number(l.quantity), remaining: Number(l.remaining), days_left: Number(l.days_left), unit_cost: l.unit_cost == null ? null : Number(l.unit_cost), unit_price: l.unit_price == null ? null : Number(l.unit_price) }));
    const names = new Map(((members.data ?? []) as { user_id: string; display_name: string | null }[]).map(m => [m.user_id, m.display_name] as const));
    const first = <T,>(v: T | T[] | null | undefined): T | null => (Array.isArray(v) ? v[0] : v) ?? null;
    type RawLoss = Omit<LossRow, "product_name" | "lot_code" | "expires_on" | "user_name" | "quantity" | "unit_cost"> & { quantity: number | string; unit_cost: number | string | null; user_id: string; product: unknown; lot: unknown };
    const losses: LossRow[] = ((lossRes.data ?? []) as unknown as RawLoss[]).map(r => {
      const lot = first(r.lot as { lot_code: string | null; expires_on: string } | null);
      return { id: r.id, product_id: r.product_id, quantity: Number(r.quantity), reason: r.reason, note: r.note, unit_cost: r.unit_cost == null ? null : Number(r.unit_cost), created_at: r.created_at,
        product_name: first(r.product as { name: string } | null)?.name ?? "Producto", lot_code: lot?.lot_code ?? null, expires_on: lot?.expires_on ?? null, user_name: names.get(r.user_id) ?? null };
    });
    const salesTotal = sales.data ? Number((sales.data as { sales_total?: number | string }).sales_total ?? 0) : null;
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{inventory ? "EXISTENCIAS" : "CATÁLOGO"} / {c.organization.name}</p><LiveRefresh org={org} tables={inventory ? liveInventory : liveProducts} /></div><h1>{title}</h1><p>{inventory ? "Stock, fechas de vencimiento y mermas con su motivo. Es el mismo inventario que vende el móvil." : "El mismo catálogo que vende el móvil. Lo que cambies aquí aparece allá al instante, y al revés."}</p></section>
      {can(c.access, "products_edit") && id === "productos" && <CreateRecord org={org} moduleId={id} />}
      {inventory && !lotRes.error && <ExpiryOverview org={org} lots={lots} losses={losses} currency={c.organization.currency || "PEN"} salesTotal={salesTotal} canEdit={can(c.access, "products_edit")} />}
      {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los productos</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <ProductBoard org={org} rows={products} currency={c.organization.currency || "PEN"} canEdit={can(c.access, "products_edit")} canKardex={c.access.is_admin === true} canLots={inventory} />}
    </>;
  }
  const rawPage = Number((await searchParams).page ?? 1);
  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? Math.min(rawPage, 10000) : 1;
  let query = c.db.from(m.table!).select(m.columns!).eq("org_id", org);
  if (id === "agenda") query = query.eq("kind", "cita");
  if (id === "trabajos") query = query.neq("kind", "cita");
  const result = await query.order(m.order!, { ascending: ["name", "scheduled_at"].includes(m.order!) }).order("id").range((page - 1) * 50, page * 50);
  const rows = (result.data ?? []) as unknown as Record<string, unknown>[];
  return <><section className="fv-heading"><p className="fv-eyebrow">OPERACIÓN / {c.organization.name}</p><h1>{title}</h1><p>{id === "agenda" ? "Citas registradas, ordenadas por fecha." : id === "cotizaciones" ? "Tus cotizaciones con su estado. Se crean y se convierten en venta desde el móvil." : "Trabajos de tu empresa con su estado, los mismos del móvil."}</p></section>
    {(["trabajos", "agenda"].includes(id) || (id === "productos" && can(c.access, "products_edit"))) && <CreateRecord org={org} moduleId={id} />}
    {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los registros</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div> : <><DataTable rows={rows.slice(0, 50)} fields={m.fields!} /><nav className="fv-pagination" aria-label="Paginación">{page > 1 && <Link className="fv-button secondary" href={`?page=${page - 1}`}>Anterior</Link>}<span>Página {page}</span>{rows.length > 50 && <Link className="fv-button secondary" href={`?page=${page + 1}`}>Siguiente</Link>}</nav></>}
  </>;
}
