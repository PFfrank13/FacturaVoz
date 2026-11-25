import { describe, expect, it } from "vitest";
import { visibleModules, type Access, type License } from "@/lib/erp/access";

// Funciones del plan Básico tal como las entrega Solvex Hub (effective_features).
const basico: License = { enforced: true, dev: false, stale: false, source: "hub", mode: "full", plan: "BASICO", status: "activa", features: {
  voz: true, caja: true, stock: true, cobros: true, fiados: true, clientes: true, facturar: true, reportes: true, avisos_pago: true, cotizaciones: true,
  agenda: false, tienda: false, precios: false, carta_qr: false, copiloto: false, trabajos: false, encuestas: false, antifraude: false, comisiones: false,
  api_publica: false, cuaderno_ia: false, multimoneda: false, recurrentes: false, conciliacion: false, fidelizacion: false, multisucursal: false,
  portal_cliente: false, copiloto_agente: false, max_users: 2, max_branches: 1,
} };
const owner: Access = { is_admin: true, role: "owner", can: { finance: true, sell: true, collect: true, clients: true, jobs: true, products_edit: true, team: true, settings: true, license: true, import: true } };

describe("el menú de la web solo muestra lo que el plan incluye", () => {
  it("dueño de bodega con plan Básico", () => {
    const ids = visibleModules(basico, owner, "bodega").map(m => m.id).sort();
    expect(ids).toEqual([
      "caja", "clientes", "clientes360", "cobranza", "cobros", "compras", "comprobantes", "configuracion", "cotizaciones", "credito", "equipo", "fiados", "avisos",
      "gastos", "importar", "impuestos", "inventario", "negocio", "papelera", "plan", "productos", "reponer", "reportes", "vencimientos", "vender",
    ].sort());
    for (const premium of ["agente", "escanear", "pin", "alertas", "bitacora", "promociones", "puntos", "tienda", "cuaderno", "recurrentes", "conciliacion", "encuestas", "comisiones", "api", "sucursales"])
      expect(ids).not.toContain(premium);
  });
});
