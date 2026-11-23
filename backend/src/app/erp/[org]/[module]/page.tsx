import Link from "next/link";
import { notFound } from "next/navigation";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed, featureLimit, can, hasFeature } from "@/lib/erp/access";
import DataTable from "@/components/erp/DataTable";
import CreateRecord from "@/components/erp/CreateRecord";
import ProductBoard, { type ProductRow } from "@/components/erp/ProductBoard";
import LiveRefresh from "@/components/erp/LiveRefresh";
import ReceiptsBoard from "@/components/erp/ReceiptsBoard";
import type { ReceiptRow } from "@/lib/erp/receipts";
import ClientsBoard from "@/components/erp/ClientsBoard";
import CashBoard from "@/components/erp/CashBoard";
import type { CashMove, DayClosing } from "@/lib/erp/cash";
import type { DaySummary } from "@/lib/dayclose";
import { limaDate } from "@/lib/erp/receipts";
import { mergeClients, type ClientActivity, type ClientBalance, type ClientRow } from "@/lib/erp/clients";

const liveProducts = ["products"] as const;
const liveReceipts = ["invoices"] as const;
const liveClients = ["clients", "credit_ledger", "invoices"] as const;
const liveCash = ["cash_movements", "payments", "invoices", "credit_ledger"] as const;
import NewInvoice from "@/components/NewInvoice";
import { money } from "@/lib/schemas";

export default async function ModulePage({ params, searchParams }: { params: Promise<{ org: string; module: string }>; searchParams: Promise<{ page?: string; from?: string; to?: string; dia?: string }> }) {
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
    const result = await c.db.from("invoices")
      .select("id,number,issue_date,status,currency,doc_kind,amt_total,voided_at,client:clients(name,tax_id),fiscal:fiscal_documents(doc_type,series,correlative,status,sunat_code,sunat_message,issued_at)")
      .eq("org_id", org).order("issue_date", { ascending: false }).order("created_at", { ascending: false }).limit(300);
    const receipts: ReceiptRow[] = ((result.data ?? []) as unknown as (Omit<ReceiptRow, "client" | "fiscal"> & { client: unknown; fiscal: unknown })[]).map(r => ({
      ...r,
      client: (Array.isArray(r.client) ? r.client[0] : r.client) as ReceiptRow["client"] ?? null,
      fiscal: (Array.isArray(r.fiscal) ? r.fiscal[0] : r.fiscal) as ReceiptRow["fiscal"] ?? null,
    }));
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">FACTURACIÓN / {c.organization.name}</p><LiveRefresh org={org} tables={liveReceipts} /></div><h1>Comprobantes</h1><p>Boletas, facturas y notas emitidas en el móvil o aquí, con su estado en SUNAT, XML, CDR y versión imprimible.</p></section>
      <NewInvoice key={org} org={org} currency={c.organization.currency || "PEN"} defaultTaxRate={Number(c.organization.default_tax_rate ?? 18)} voiceAllowed={hasFeature(c.license, "voz")} />
      {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los comprobantes</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <ReceiptsBoard org={org} rows={receipts} currency={c.organization.currency || "PEN"} />}
    </>;
  }
  if (id === "caja") {
    // The mobile «Caja y cierre del día»: the database computes the summary with the viewer's rights.
    const today = limaDate(new Date());
    const asked = (await searchParams).dia ?? "";
    const day = /^\d{4}-\d{2}-\d{2}$/.test(asked) && asked <= today && Number.isFinite(Date.parse(asked)) ? asked : today;
    const [summary, moves, closing] = await Promise.all([
      c.db.rpc("day_summary", { p_org: org, p_day: day }),
      c.db.from("cash_movements").select("id,kind,amount,method,note,created_at").eq("org_id", org).eq("day", day).order("created_at"),
      c.db.from("day_closings").select("counted_cash,expected_cash,difference,note,created_at").eq("org_id", org).eq("day", day).maybeSingle(),
    ]);
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">CAJA / {c.organization.name}</p><LiveRefresh org={org} tables={liveCash} /></div><h1>Caja y cierre del día</h1><p>Apertura, retiros, cobros por medio de pago y arqueo ciego. Es la misma caja que lleva el móvil.</p></section>
      {summary.error || !summary.data ? <div className="fv-empty" role="alert"><h2>No pudimos cargar la caja</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <CashBoard org={org} day={day} today={today} summary={summary.data as DaySummary}
            moves={((moves.data ?? []) as CashMove[]).map(m => ({ ...m, amount: Number(m.amount) }))}
            closing={(closing.data ?? null) as DayClosing | null} showExpected={can(c.access, "finance")} />}
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
    return <><section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{id === "inventario" ? "EXISTENCIAS" : "CATÁLOGO"} / {c.organization.name}</p><LiveRefresh org={org} tables={liveProducts} /></div><h1>{title}</h1><p>El mismo catálogo que vende el móvil. Lo que cambies aquí aparece allá al instante, y al revés.</p></section>
      {can(c.access, "products_edit") && id === "productos" && <CreateRecord org={org} moduleId={id} />}
      {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los productos</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>
        : <ProductBoard org={org} rows={products} currency={c.organization.currency || "PEN"} canEdit={can(c.access, "products_edit")} />}
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
