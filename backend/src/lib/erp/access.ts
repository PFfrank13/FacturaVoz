/** Commercial decisions only consume the verified my_license RPC, never plan matrices. */
export type License = { enforced?: boolean; dev?: boolean; stale?: boolean; source?: string; mode?: string; plan?: string; status?: string; message?: string; features?: Record<string, unknown> };
export type Access = { is_admin?: boolean; role?: string; display_name?: string; can?: Record<string, boolean> };
export function licenseReady(l: License): boolean {
  return l.enforced === true && l.dev !== true && l.stale !== true && l.source === "hub" && (l.mode === "full" || l.mode === "warning");
}
export function hasFeature(l: License, key: string): boolean { return licenseReady(l) && l.features?.[key] === true; }
export function featureLimit(l: License, key: string): number {
  const value = l.features?.[key];
  return licenseReady(l) && typeof value === "number" && Number.isSafeInteger(value) && value >= -1 ? value : 0;
}
export function can(a: Access, permission: string): boolean { return a.can?.[permission] ?? a.is_admin === true; }

export const sectors = {
  bodega: { name: "Bodega / minimarket", title: "El ritmo de tu tienda", detail: "Ventas, productos y clientes para tu jornada.", priority: ["vender", "productos", "comprobantes", "cobros"] },
  restaurante: { name: "Restaurante", title: "Tu servicio, en orden", detail: "Consulta la operación comercial y los productos de tu carta.", priority: ["comprobantes", "productos", "cobros", "clientes"] },
  servicios_tecnicos: { name: "Servicios técnicos", title: "Cada trabajo tiene su siguiente paso", detail: "Órdenes, visitas y clientes con seguimiento.", priority: ["trabajos", "agenda", "clientes", "cotizaciones"] },
  salon: { name: "Salón / barbería", title: "Haz espacio para la próxima cita", detail: "Agenda, clientes y servicios de tu negocio.", priority: ["agenda", "clientes", "productos", "cobros"] },
  consultorio: { name: "Consultorio", title: "Una atención bien organizada", detail: "Agenda y gestión administrativa de pacientes, sin información clínica.", priority: ["agenda", "clientes", "cobros", "comprobantes"] },
  taller: { name: "Taller", title: "Del ingreso a la entrega", detail: "Trabajos, repuestos y cotizaciones bajo control.", priority: ["trabajos", "inventario", "cotizaciones", "clientes"] },
  mayorista: { name: "Mayorista", title: "Tu operación, a otra escala", detail: "Cotizaciones, inventario y cobros para tu distribución.", priority: ["cotizaciones", "inventario", "clientes", "cobros"] },
  educacion: { name: "Educación", title: "Tiempo para enseñar", detail: "Contactos, horarios y administración de pagos.", priority: ["agenda", "clientes", "cobros", "comprobantes"] },
  construccion: { name: "Construcción", title: "Cada trabajo avanza contigo", detail: "Trabajos, materiales y cotizaciones en un mismo lugar.", priority: ["trabajos", "cotizaciones", "inventario", "cobros"] },
} as const;
export type Sector = keyof typeof sectors;
export function sectorFor(value: string): Sector | null { return Object.hasOwn(sectors, value) ? value as Sector : null; }
export type Module = { id: string; title: string; feature?: string; permission?: string; sectors?: readonly Sector[]; table?: string; columns?: string; fields?: readonly [string, string][]; order?: string };
const jobSectors: Sector[] = ["servicios_tecnicos", "taller", "construccion"];
const appointmentSectors: Sector[] = ["servicios_tecnicos", "salon", "consultorio", "taller", "educacion"];
export const modules: readonly Module[] = [
  { id: "compras", title: "Compras y recepción", feature: "stock", permission: "finance", sectors: ["bodega", "mayorista"] },
  { id: "proveedores", title: "Proveedores", feature: "stock", permission: "finance", table: "retail_suppliers", columns: "id,name", fields: [["name","Proveedor"]], order: "name" },
  { id: "kardex", title: "Movimientos de inventario", feature: "stock", permission: "finance", table: "retail_stock_ledger", columns: "id,product_id,before_stock,after_stock,delta,created_at", fields: [["product_id","Producto"],["before_stock","Antes"],["after_stock","Después"],["delta","Movimiento"],["created_at","Fecha"]], order: "created_at" },
  { id: "vender", title: "Vender", feature: "facturar", permission: "sell", sectors: ["bodega", "mayorista"] },
  { id: "comprobantes", title: "Comprobantes", feature: "facturar", permission: "sell", table: "invoices", columns: "id,number,issue_date,status,currency", fields: [["number", "Número"], ["issue_date", "Fecha"], ["status", "Estado"], ["currency", "Moneda"]], order: "created_at" },
  { id: "clientes", title: "Clientes", feature: "clientes", permission: "clients", table: "clients", columns: "id,name,tax_id,email,phone", fields: [["name", "Nombre"], ["tax_id", "Documento"], ["email", "Correo"], ["phone", "Teléfono"]], order: "name" },
  { id: "productos", title: "Productos y servicios", feature: "facturar", permission: "sell", table: "products", columns: "id,name,unit_price,unit,active", fields: [["name", "Nombre"], ["unit_price", "Precio unitario"], ["unit", "Unidad"], ["active", "Activo"]], order: "name" },
  { id: "inventario", title: "Inventario", feature: "stock", permission: "products_edit", sectors: ["bodega", "restaurante", "taller", "mayorista", "construccion", "servicios_tecnicos", "salon"], table: "products", columns: "id,name,sku,stock,reorder_point", fields: [["name", "Producto"], ["sku", "SKU"], ["stock", "Existencias"], ["reorder_point", "Mínimo"]], order: "name" },
  { id: "trabajos", title: "Trabajos", feature: "trabajos", permission: "jobs", sectors: jobSectors, table: "jobs", columns: "id,title,status,scheduled_at,kind", fields: [["title", "Trabajo"], ["status", "Estado"], ["scheduled_at", "Programado"], ["kind", "Tipo"]], order: "created_at" },
  { id: "agenda", title: "Agenda", feature: "agenda", permission: "jobs", sectors: appointmentSectors, table: "jobs", columns: "id,title,status,scheduled_at,duration_min", fields: [["title", "Cita"], ["scheduled_at", "Programada"], ["duration_min", "Minutos"], ["status", "Estado"]], order: "scheduled_at" },
  { id: "cotizaciones", title: "Cotizaciones", feature: "cotizaciones", permission: "sell", table: "quotes", columns: "id,number,issue_date,status,currency", fields: [["number", "Número"], ["issue_date", "Fecha"], ["status", "Estado"], ["currency", "Moneda"]], order: "created_at" },
  { id: "cobros", title: "Cobros", feature: "cobros", permission: "collect", table: "payments", columns: "id,amount,paid_on,method,note", fields: [["amount", "Importe registrado"], ["paid_on", "Fecha"], ["method", "Medio"], ["note", "Nota"]], order: "paid_on" },
  { id: "equipo", title: "Equipo", permission: "team" },
  { id: "reportes", title: "Reportes", feature: "reportes", permission: "finance" },
  { id: "plan", title: "Mi plan", permission: "license" },
  { id: "configuracion", title: "Configuración", permission: "settings" },
];
export function moduleAllowed(m: Module, l: License, a: Access, sector: Sector | null): boolean {
  if (m.permission && !can(a, m.permission)) return false;
  if (m.id === "plan") return true;
  return licenseReady(l) && (!m.feature || hasFeature(l, m.feature)) && (!m.sectors || (sector !== null && m.sectors.includes(sector)));
}
export function visibleModules(l: License, a: Access, sector: Sector | null): Module[] {
  const visible = modules.filter(m => moduleAllowed(m, l, a, sector));
  const priority: readonly string[] = sector ? sectors[sector].priority : [];
  return [...visible].sort((a, b) => {
    const rank = (id: string) => priority.includes(id) ? priority.indexOf(id) : priority.length;
    return rank(a.id) - rank(b.id);
  });
}

