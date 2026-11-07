import { describe, it, expect } from "vitest";
import { hasFeature, featureLimit, moduleAllowed, modules, sectors, visibleModules, type License, type Sector } from "../src/lib/erp/access";
const active: License = { enforced: true, source: "hub", mode: "full", features: { stock: true, facturar: true, clientes: true, cobros: true, agenda: true, trabajos: true, cotizaciones: true, max_users: 5 } };
describe("ERP: Hub remains authoritative for historical companies", () => {
  for (const sector of Object.keys(sectors) as Sector[]) {
    it(`${sector}: false and missing flags stay hidden for every role and plan`, () => {
      for (const plan of ["BASICO", "PRO", "EMPRESA"]) {
        for (const role of ["owner", "admin", "finanzas", "cajero", "vendedor", "tecnico"]) {
          const access = { role, is_admin: role === "owner" || role === "admin", can: { products_edit: true } };
          for (const features of [{ stock: false }, {}]) {
            const l = { ...active, plan, features };
            expect(visibleModules(l, access, sector).some(m => m.id === "inventario")).toBe(false);
            expect(hasFeature(l, "stock")).toBe(false);
          }
        }
      }
    });
    it(`${sector}: commercial navigation preserves authorization and hides historical verticals`, () => {
      const access = { is_admin: true };
      const ids = visibleModules(active, access, sector).map(m => m.id);
      for (const entry of modules) expect(ids.includes(entry.id)).toBe(!["trabajos", "agenda"].includes(entry.id) && moduleAllowed(entry, active, access, sector));
      expect(ids).toContain("vender");
      expect(ids).toContain("inventario");
    });
  }
  it("closed modes, stale cache, dev and absent verification cannot grant rights", () => {
    for (const patch of [{ mode: "blocked" }, { mode: "restricted" }, { stale: true }, { dev: true }, { enforced: false }, { source: "local" }]) {
      expect(hasFeature({ ...active, ...patch }, "stock")).toBe(false);
      expect(featureLimit({ ...active, ...patch }, "max_users")).toBe(0);
    }
    expect(hasFeature({ ...active, mode: "warning" }, "stock")).toBe(true);
  });
  it("numeric limits never unlock boolean features", () => {
    for (const value of [-1, 0, 1, 4, "true", "false", null]) expect(hasFeature({ ...active, features: { stock: value } }, "stock")).toBe(false);
    for (const value of [-2, 1.5, "5", true, null, Infinity]) expect(featureLimit({ ...active, features: { max_users: value } }, "max_users")).toBe(0);
    expect(featureLimit({ ...active, features: { max_users: -1 } }, "max_users")).toBe(-1);
    expect(featureLimit(active, "max_users")).toBe(5);
  });
  it("explicit permission denial prevails even for an administrator", () => {
    expect(visibleModules(active, { is_admin: true, can: { products_edit: false } }, "bodega").some(m => m.id === "inventario")).toBe(false);
  });
  it("clinic and education do not advertise unsupported work modules", () => {
    for (const sector of ["consultorio", "educacion"] as Sector[]) expect(visibleModules(active, { is_admin: true }, sector).some(m => m.id === "trabajos")).toBe(false);
  });
});
