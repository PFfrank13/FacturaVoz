import { describe, expect, it } from "vitest";
import { modules, visibleModules, type Access, type License, type Sector } from "@/lib/erp/access";
import { arrangeMenu, menuGroups } from "@/lib/erp/menu";

const owner: Access = { is_admin: true, role: "owner", can: { finance: true, sell: true, collect: true, clients: true, jobs: true, products_edit: true, team: true, settings: true, license: true, import: true } };
const lic = (features: Record<string, unknown>): License => ({ enforced: true, dev: false, stale: false, source: "hub", mode: "full", status: "activa", features });
const basico = lic({ voz: true, caja: true, stock: true, cobros: true, fiados: true, clientes: true, facturar: true, reportes: true, avisos_pago: true, cotizaciones: true, max_users: 2, max_branches: 1 });
const keys = [...new Set(modules.map(m => m.feature).filter((f): f is string => !!f))];
const todo = lic({ ...Object.fromEntries(keys.map(k => [k, true])), max_users: 20, max_branches: 5 });
const titles = (s: Sector) => (l: License) => arrangeMenu(visibleModules(l, owner, s)).map(g => g.title);

describe("menú de la web: cada módulo en su categoría, en orden", () => {
  it("todos los módulos tienen una sola categoría (ninguno queda suelto)", () => {
    const all = menuGroups.flatMap(g => g.ids);
    expect(new Set(all).size).toBe(all.length);
    for (const m of modules) expect(all, `sin categoría: ${m.id}`).toContain(m.id);
  });

  it("bodega Básico (tu licencia real)", () => {
    const menu = arrangeMenu(visibleModules(basico, owner, "bodega"));
    expect(menu.map(g => g.title)).toEqual(["Vender", "Mercadería", "Caja y cobros", "Clientes y promociones", "Mi negocio", "Control del dueño", "Configuración"]);
    expect(menu.find(g => g.title === "Vender")!.items.map(m => m.id)).toEqual(["vender", "comprobantes", "cotizaciones"]);
    expect(menu.find(g => g.title === "Control del dueño")!.items.map(m => m.id)).toEqual(["pin", "papelera"]);
  });

  it("bodega con todas las funciones (Empresa): todo lo del plan aparece una vez, en orden", () => {
    const visible = visibleModules(todo, owner, "bodega");
    const menu = arrangeMenu(visible);
    expect(menu.flatMap(g => g.items).length).toBe(visible.length);
    expect(menu.map(g => g.title)).toEqual(["Vender", "Mercadería", "Caja y cobros", "Clientes y promociones", "Mi negocio", "Control del dueño", "Configuración"]);
    const ids = menu.flatMap(g => g.items.map(m => m.id));
    for (const id of ["cuaderno", "tienda", "recurrentes", "sucursales", "conciliacion", "promociones", "puntos", "encuestas", "comisiones", "agente", "alertas", "bitacora", "api"]) expect(ids).toContain(id);
  });

  it("otros rubros también quedan ordenados por categoría", () => {
    for (const s of ["restaurante", "servicios_tecnicos", "salon", "consultorio", "taller", "mayorista", "educacion", "construccion"] as Sector[]) {
      const visible = visibleModules(todo, owner, s);
      expect(arrangeMenu(visible).flatMap(g => g.items).length, s).toBe(visible.length);
      expect(titles(s)(todo)[0], s).toBe("Vender");
    }
  });
});
