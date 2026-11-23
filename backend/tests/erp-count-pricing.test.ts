import { describe, expect, it } from "vitest";
import { countLines, countSummary, parseCount } from "@/lib/erp/count";
import { newShelfPrice, pricingProblem, withTax, withoutTax } from "@/lib/erp/pricing";

describe("conteo de inventario", () => {
  it("solo cuenta lo escrito y ordena primero lo que falta", () => {
    const lines = countLines([
      { product_id: "a", name: "Arroz", stock: 10, counted: 8, unit_cost: 3.8 },
      { product_id: "b", name: "Azúcar", stock: 5, counted: 5, unit_cost: 3 },
      { product_id: "c", name: "Aceite", stock: 2, counted: 4, unit_cost: 7 },
    ]);
    expect(lines.map(l => l.product_id)).toEqual(["a", "c"]);
    expect(lines[0]).toMatchObject({ diff: -2, value: -7.6 });
    expect(countSummary(lines)).toEqual({ products: 2, missing: 2, extra: 2, missingValue: 7.6, extraValue: 14, net: 6.4 });
  });
  it("lee lo que escribe la persona", () => {
    expect(parseCount("")).toBeNull();
    expect(parseCount("3,5")).toBe(3.5);
    expect(parseCount("abc")).toBeNaN();
  });
});

describe("precios masivos", () => {
  it("cambia el precio al público y redondea a 10 céntimos", () => {
    expect(newShelfPrice(2.5, "subir_pct", 10)).toBe(2.8);
    expect(newShelfPrice(2.5, "bajar_monto", 0.2)).toBe(2.3);
    expect(newShelfPrice(0.2, "bajar_monto", 1)).toBe(0.1);
  });
  it("guarda la base sin IGV que reproduce el precio de la etiqueta", () => {
    for (const shelf of [1, 1.5, 2.8, 3.5, 9.9, 12.3]) expect(withTax(withoutTax(shelf, 18), 18)).toBe(shelf);
  });
  it("valida el cambio", () => {
    expect(pricingProblem("subir_pct", 95)).toMatch(/90 %/);
    expect(pricingProblem("otro", 5)).toMatch(/Elige/);
    expect(pricingProblem("subir_monto", 0.5)).toBeNull();
  });
});
