import { describe, expect, it } from "vitest";
import { bestPrice, cartTotals, couponDiscount, couponProblemAt, priceCart, type PosPromo } from "@/lib/erp/pos";

const promo = (o: Partial<PosPromo>): PosPromo => ({ id: "p", name: "Promo", kind: "porcentaje", value: 10, product_ids: [], min_qty: null, starts_on: null, ends_on: null, active: true, ...o });

describe("promociones y cupones en la venta rápida web (igual que el móvil)", () => {
  it("elige el mejor precio: por mayor o promoción vigente", () => {
    expect(bestPrice("a", 10, 1, [], "2026-11-24", 8, 6)).toEqual({ price: 10, reason: "" });
    expect(bestPrice("a", 10, 6, [], "2026-11-24", 8, 6)).toEqual({ price: 8, reason: "Precio por mayor" });
    const lleva3 = promo({ name: "Lleva 3", kind: "volumen", value: 33.34, min_qty: 3, product_ids: ["a"] });
    expect(bestPrice("a", 3, 3, [lleva3], "2026-11-24").reason).toBe("Lleva 3");
    expect(bestPrice("b", 3, 3, [lleva3], "2026-11-24").reason).toBe("");
    expect(bestPrice("a", 3, 2, [lleva3], "2026-11-24").reason).toBe("");
    expect(bestPrice("a", 5, 1, [promo({ kind: "monto", value: 9 })], "2026-11-24").price).toBe(0);
  });

  it("respeta las fechas de la promoción", () => {
    const p = promo({ starts_on: "2026-12-01", ends_on: "2026-12-31" });
    expect(bestPrice("a", 10, 1, [p], "2026-11-24").reason).toBe("");
    expect(bestPrice("a", 10, 1, [p], "2026-12-15").price).toBe(9);
    expect(bestPrice("a", 10, 1, [{ ...p, active: false }], "2026-12-15").reason).toBe("");
  });

  it("reparte el cupón en los precios y nunca deja negativo", () => {
    expect(couponDiscount("porcentaje", 10, 50)).toBe(5);
    expect(couponDiscount("monto", 80, 50)).toBe(50);
    const r = priceCart([{ product_id: "a", name: "A", unit_price: 10, quantity: 2 }, { product_id: "b", name: "B", unit_price: 5, quantity: 1 }], [], "2026-11-24", {}, { code: "X", kind: "monto", value: 5 });
    expect(r.lines.map(l => l.unit_price)).toEqual([8, 4]);
    expect(r.couponSaving).toBe(5);
    expect(cartTotals(r.lines, 18)).toEqual({ subtotal: 20, tax: 3.6, total: 23.6 });
  });

  it("valida el cupón sin gastarlo", () => {
    expect(couponProblemAt(null, "2026-11-24")).toMatch(/no válido/);
    expect(couponProblemAt({ active: true, expires_on: "2026-11-23", max_uses: null, uses: 0 }, "2026-11-24")).toMatch(/venció/);
    expect(couponProblemAt({ active: true, expires_on: null, max_uses: 2, uses: 2 }, "2026-11-24")).toMatch(/todas las veces/);
    expect(couponProblemAt({ active: true, expires_on: "2026-11-24", max_uses: 3, uses: 1 }, "2026-11-24")).toBeNull();
  });
});
