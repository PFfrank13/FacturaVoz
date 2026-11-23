import Link from "next/link";
import { notFound } from "next/navigation";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed, featureLimit, can, hasFeature } from "@/lib/erp/access";
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
import PurchasesBoard, { type PurchaseProduct } from "@/components/erp/PurchasesBoard";
import PaymentsBoard from "@/components/erp/PaymentsBoard";
import LoyaltyBoard from "@/components/erp/LoyaltyBoard";
import type { Coupon, LoyaltyRow, Promotion } from "@/lib/erp/loyalty";
import { monthBounds, parseMonth, type PaymentRow } from "@/lib/erp/payments";
import { lastSupplierByProduct, suggestOrder, type PurchaseRow, type Velocity } from "@/lib/erp/purchases";
import { cashierBreakdown, type CashMove, type DayClosing } from "@/lib/erp/cash";
import type { DaySummary } from "@/lib/dayclose";
import { limaDate, parseRange } from "@/lib/erp/receipts";
import { mergeClients, type ClientActivity, type ClientBalance, type ClientRow } from "@/lib/erp/clients";

const liveProducts = ["products"] as const;
const liveReceipts = ["invoices"] as const;
const liveClients = ["clients", "credit_ledger", "invoices"] as const;
const liveCash = ["cash_movements", "payments", "invoices", "credit_ledger"] as const;
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
    const today = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
    const from = search.from ?? `${today.slice(0, 7)}-01`;
    const to = search.to ?? today;
    const validDate = (v: string) => /^\d{4}-\d{2}-\d{2}$/.test(v) && Number.isFinite(Date.parse(v)) && new Date(v).toISOString().slice(0, 10) === v;
    const valid = validDate(from) && validDate(to) && from <= to && Date.parse(to) - Date.parse(from) <= 366 * 86400000;
    const result = valid ? await c.db.rpc("sales_summary", { p_org: org, p_from: from, p_to: new Date(Date.parse(to) + 86400000).toISOString().slice(0, 10), p_currency: c.organization.currency || "PEN" }) : null;
    return <><section className="fv-heading"><p className="fv-eyebrow">CONTROL COMERCIAL</p><h1>Reportes de ventas</h1><p>Ventas emitidas, sin anuladas ni rechazadas, menos notas de crédito. Una moneda por consulta.</p></section>
      <form className="fv-form"><label>Desde<input type="date" name="from" defaultValue={from} required /></label><label>Hasta (incluido)<input type="date" name="to" defaultValue={to} required /></label><button className="fv-button">Consultar periodo</button></form>
      {!valid ? <p role="alert">Elige un intervalo válido de hasta 366 días.</p> : result?.error || !result?.data ? <p role="alert">No pudimos cargar el reporte. Pulsa Actualizar para reintentar.</p> : <dl className="fv-details"><dt>Ventas netas · {c.organization.currency || "PEN"}</dt><dd>{money(Number(result.data.sales_total), c.organization.currency || "PEN")}</dd><dt>Operaciones emitidas</dt><dd>{result.data.sales_count}</dd><dt>Notas de crédito</dt><dd>{money(Number(result.data.credit_notes_total), c.organization.currency || "PEN")}</dd><dt>Borradores (no incluidos en ventas)</dt><dd>{result.data.drafts_count}</dd></dl>}
    </>;
  }
  if (id === "plan") return <><section className="fv-heading"><p className="fv-eyebrow">SOLVEX HUB</p><h1>Mi plan</h1><p>Una sola licencia para móvil y web.</p></section><dl className="fv-details"><dt>Plan</dt><dd>{c.license.plan || "Sin asignar"}</dd><dt>Estado</dt><dd>{c.license.status || "Sin verificar"}</dd><dt>Usuarios</dt><dd>{featureLimit(c.license, "max_users") === -1 ? "Sin límite" : featureLimit(c.license, "max_users")}</dd><dt>Sucursales</dt><dd>{featureLimit(c.license, "max_branches") === -1 ? "Sin límite" : featureLimit(c.license, "max_branches")}</dd></dl><p>{c.license.message}</p></>;
  if (id === "configuracion") return <><section className="fv-heading"><p className="fv-eyebrow">EMPRESA</p><h1>Configuración</h1><p>Datos compartidos con FacturaVoz Mobile.</p></section><dl className="fv-details">{[["Razón social", c.organization.name], ["Documento", c.organization.tax_id], ["Dirección", c.organization.address], ["Moneda", c.organization.currency]].map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value || "Sin configurar"}</dd></div>)}</dl></>;
  if (id === "equipo") {
    const result = await c.db.rpc("team_members", { p_org: org });
    return <><section className="fv-heading"><p className="fv-eyebrow">PERSONAS</p><h1>Equipo</h1></section>{result.error ? <p role="alert">No se pudo cargar el equipo. Pulsa Actualizar para reintentar.</p> : <DataTable rows={result.data ?? []} fields={[["display_name", "Nombre"], ["email", "Correo"], ["role", "Rol"], ["staff_role", "Función"]]} />}</>;
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
      points ? Promise.resolve({ data: [], error: null }) : c.db.from("coupons").select("id,code,kind,value,max_uses,uses,expires_on,active").eq("org_id", org).order("created_at", { ascending: false }).limit(200),
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
    const [summary, moves, closing, dayPayments, members] = await Promise.all([
      c.db.rpc("day_summary", { p_org: org, p_day: day }),
      c.db.from("cash_movements").select("id,kind,amount,method,note,created_at,user_id").eq("org_id", org).eq("day", day).order("created_at"),
      c.db.from("day_closings").select("counted_cash,expected_cash,difference,note,created_at").eq("org_id", org).eq("day", day).maybeSingle(),
      finance ? c.db.from("payments").select("user_id,method,amount").eq("org_id", org).eq("paid_on", day).limit(3000) : Promise.resolve({ data: [] }),
      finance ? c.db.from("organization_members").select("user_id,display_name").eq("org_id", org) : Promise.resolve({ data: [] }),
    ]);
    const cashMoves = ((moves.data ?? []) as CashMove[]).map(m => ({ ...m, amount: Number(m.amount) }));
    const cashiers = finance ? cashierBreakdown((dayPayments.data ?? []) as { user_id: string; method: string; amount: number }[], cashMoves,
      new Map(((members.data ?? []) as { user_id: string; display_name: string | null }[]).map(m => [m.user_id, m.display_name] as const))) : [];
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">CAJA / {c.organization.name}</p><LiveRefresh org={org} tables={liveCash} /></div><h1>Caja y cierre del día</h1><p>Apertura, retiros, cobros por medio de pago y arqueo ciego. Es la misma caja que lleva el móvil.</p></section>
      {summary.error || !summary.data ? <div className="fv-empty" role="alert"><h2>No pudimos cargar la caja</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <CashBoard org={org} day={day} today={today} summary={summary.data as DaySummary}
            moves={cashMoves} cashiers={cashiers}
            closing={(closing.data ?? null) as DayClosing | null} showExpected={finance} />}
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
    const result = await c.db.from("products").select("id,name,unit_price,unit,active,category,stock,reorder_point,unit_cost,image_path")
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
      can(c.access, "finance") ? c.db.rpc("sales_summary", { p_org: org, p_from: monthStart, p_to: today, p_currency: c.organization.currency || "PEN" }) : Promise.resolve({ data: null }),
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
  return <><section className="fv-heading"><p className="fv-eyebrow">OPERACIÓN / {c.organization.name}</p><h1>{title}</h1><p>{id === "agenda" ? "Citas registradas, ordenadas por fecha." : "Información de tu empresa, compartida con la aplicación móvil."}</p></section>
    {(["trabajos", "agenda"].includes(id) || (id === "productos" && can(c.access, "products_edit"))) && <CreateRecord org={org} moduleId={id} />}
    {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los registros</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div> : <><DataTable rows={rows.slice(0, 50)} fields={m.fields!} /><nav className="fv-pagination" aria-label="Paginación">{page > 1 && <Link className="fv-button secondary" href={`?page=${page - 1}`}>Anterior</Link>}<span>Página {page}</span>{rows.length > 50 && <Link className="fv-button secondary" href={`?page=${page + 1}`}>Siguiente</Link>}</nav></>}
  </>;
}
