import Link from "next/link";
import { notFound } from "next/navigation";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed, featureLimit, can, hasFeature } from "@/lib/erp/access";
import DataTable from "@/components/erp/DataTable";
import CreateRecord from "@/components/erp/CreateRecord";
import PointOfSale from "@/components/erp/PointOfSale";
import Receiving from "@/components/erp/Receiving";
import NewInvoice from "@/components/NewInvoice";
import { money } from "@/lib/schemas";

export default async function ModulePage({ params, searchParams }: { params: Promise<{ org: string; module: string }>; searchParams: Promise<{ page?: string; from?: string; to?: string }> }) {
  const { org, module: id } = await params;
  const c = await workspaceContext(org);
  const m = modules.find(m => m.id === id);
  if (!m || !moduleAllowed(m, c.license, c.access, c.sector)) notFound();
  if (id === "compras") {
    const [products, receipts] = await Promise.all([
      c.db.from("products").select("id,name,stock").eq("org_id",org).eq("active",true).order("name").limit(500),
      c.db.from("retail_receipts").select("id,supplier_name,reference,total,currency,created_at").eq("org_id",org).order("created_at",{ascending:false}).limit(50),
    ]);
    return <><section className="fv-heading"><p className="fv-eyebrow">ABASTECIMIENTO</p><h1>Compras y recepción</h1><p>Recibe mercadería, conserva el documento y consulta sus efectos en inventario.</p><Link href={`/erp/${org}/inventario`}>Ver existencias</Link> · <Link href={`/erp/${org}/kardex`}>Ver movimientos</Link></section>
      {products.error || receipts.error ? <p role="alert">El servicio de recepción no está disponible. Actualiza para reintentar; no se registró una compra.</p> : <><Link href={`/erp/${org}/productos`}>Crear un producto para recibirlo</Link><Receiving key={`${org}:${c.user.id}`} org={org} products={products.data ?? []}/><h2>Últimas 50 recepciones confirmadas</h2><DataTable rows={receipts.data ?? []} fields={[["reference","Documento"],["supplier_name","Proveedor"],["total","Costo total"],["currency","Moneda"],["created_at","Recibida"]]}/></>}
    </>;
  }
  if (id === "vender") {
    const result = await c.db.from("products").select("id,name,unit_price").eq("org_id", org).eq("active", true).order("name").limit(500);
    return <><section className="fv-heading"><p className="fv-eyebrow">PUNTO DE VENTA</p><h1>Vender</h1><p>Elige productos, revisa tu carrito y registra el cobro.</p></section>
      {result.error ? <p role="alert">No pudimos cargar el catálogo. Pulsa Actualizar para reintentar.</p> : <PointOfSale key={`${org}:${c.user.id}`} org={org} userId={c.user.id}
        products={(result.data ?? []).map(p => ({ ...p, unit_price: Number(p.unit_price) }))}
        currency={c.organization.currency || "PEN"} taxRate={Number(c.organization.default_tax_rate ?? 18)}
        canCollect={can(c.access, "collect")} canEdit={can(c.access, "products_edit")} />}</>;
  }
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
  if (id === "configuracion") return <><section className="fv-heading"><p className="fv-eyebrow">EMPRESA</p><h1>Configuración</h1><p>Datos compartidos con FacturaVoz.</p></section><dl className="fv-details">{[["Razón social", c.organization.name], ["Documento", c.organization.tax_id], ["Dirección", c.organization.address], ["Moneda", c.organization.currency]].map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value || "Sin configurar"}</dd></div>)}</dl></>;
  if (id === "equipo") {
    const result = await c.db.rpc("team_members", { p_org: org });
    return <><section className="fv-heading"><p className="fv-eyebrow">PERSONAS</p><h1>Equipo</h1></section>{result.error ? <p role="alert">No se pudo cargar el equipo. Pulsa Actualizar para reintentar.</p> : <DataTable rows={result.data ?? []} fields={[["display_name", "Nombre"], ["email", "Correo"], ["role", "Rol"], ["staff_role", "Función"]]} />}</>;
  }
  const rawPage = Number((await searchParams).page ?? 1);
  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? Math.min(rawPage, 10000) : 1;
  let query = c.db.from(m.table!).select(m.columns!).eq("org_id", org);
  if (id === "agenda") query = query.eq("kind", "cita");
  if (id === "trabajos") query = query.neq("kind", "cita");
  const result = await query.order(m.order!, { ascending: ["name", "scheduled_at"].includes(m.order!) }).order("id").range((page - 1) * 50, page * 50);
  const rows = (result.data ?? []) as unknown as Record<string, unknown>[];
  return <><section className="fv-heading"><p className="fv-eyebrow">OPERACIÓN / {c.organization.name}</p><h1>{title}</h1><p>{id === "agenda" ? "Citas registradas, ordenadas por fecha." : "Información de tu empresa, compartida con la aplicación móvil."}</p></section>
    {(["clientes", "trabajos", "agenda"].includes(id) || (id === "productos" && can(c.access, "products_edit"))) && <CreateRecord org={org} moduleId={id} stockAllowed={hasFeature(c.license,'stock')} />}
    {id === "comprobantes" && <NewInvoice key={org} org={org} currency={c.organization.currency || "PEN"} defaultTaxRate={Number(c.organization.default_tax_rate ?? 18)} voiceAllowed={hasFeature(c.license, "voz")} />}
    {result.error ? <div className="fv-empty" role="alert"><h2>No pudimos cargar los registros</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div> : <><DataTable rows={rows.slice(0, 50)} fields={m.fields!} /><nav className="fv-pagination" aria-label="Paginación">{page > 1 && <Link className="fv-button secondary" href={`?page=${page - 1}`}>Anterior</Link>}<span>Página {page}</span>{rows.length > 50 && <Link className="fv-button secondary" href={`?page=${page + 1}`}>Siguiente</Link>}</nav></>}
  </>;
}
