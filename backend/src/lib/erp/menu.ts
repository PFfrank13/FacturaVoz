/** Left menu of the web ERP: the same colored categories, order and colors as the mobile app drawer. Pure, tested. */
export const menuGroups: readonly { title: string; color: string; ids: readonly string[] }[] = [
  { title: "Vender", color: "#0e8c74", ids: ["vender", "carta", "platos", "comprobantes", "cotizaciones", "cuaderno", "tienda", "recurrentes"] },
  { title: "Mercadería", color: "#2f6fdc", ids: ["productos", "inventario", "compras", "vencimientos", "reponer", "sucursales"] },
  { title: "Caja y cobros", color: "#c77417", ids: ["caja", "fiados", "cobranza", "cobros", "corte", "morosidad", "avisos", "credito", "gastos", "escanear", "conciliacion"] },
  { title: "Clientes y promociones", color: "#c2407e", ids: ["clientes", "clientes360", "promociones", "puntos", "encuestas"] },
  { title: "Servicios", color: "#0b8aa8", ids: ["trabajos", "agenda", "placas", "recordatorios", "paquetes", "historial", "margen_obra"] },
  { title: "Mi negocio", color: "#6a5ae0", ids: ["reportes", "negocio", "impuestos", "comisiones", "agente", "importar"] },
  { title: "Control del dueño", color: "#8a4b2f", ids: ["alertas", "bitacora", "pin", "papelera"] },
  { title: "Configuración", color: "#4f6480", ids: ["configuracion", "equipo", "plan", "api"] },
];

/** The visible modules arranged by category, in menu order; empty categories are left out. */
export function arrangeMenu<T extends { id: string }>(visible: readonly T[]): { title: string; color: string; items: T[] }[] {
  const byId = new Map(visible.map(v => [v.id, v] as const));
  return menuGroups.map(g => ({ title: g.title, color: g.color, items: g.ids.map(id => byId.get(id)).filter((v): v is T => !!v) })).filter(g => g.items.length > 0);
}
