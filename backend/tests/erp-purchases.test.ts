import { describe, expect, it } from "vitest";
import { isPending, lineCents, purchaseCents, purchaseProblem, summarizePurchases, supplierSuggestions, toCents, type PurchaseRow } from "../src/lib/erp/purchases";

const id = "7007146f-d0d5-4c3c-b95f-d2c90d1e163f";
const row = (over: Partial<PurchaseRow> = {}): PurchaseRow => ({ id: "r1", supplier_name: "Alicorp", document_ref: null, payment_method: "pendiente", total_cents: 4560, created_at: "2026-11-23T06:00:00Z", items: [], paid: null, ...over });

describe("compras", () => {
  it("computes cents like the database, without float drift", () => {
    expect(toCents(2.675)).toBe(268);
    expect(lineCents({ quantity: 12, unit_cost: 3.8 })).toBe(4560);
    expect(purchaseCents([{ quantity: 1.5, unit_cost: 0.1 }, { quantity: 2, unit_cost: 1.05 }])).toBe(225);
  });

  it("explains what to fix before sending", () => {
    expect(purchaseProblem("", "", [{ product_id: id, quantity: 1, unit_cost: 1 }])).toContain("proveedor");
    expect(purchaseProblem("Alicorp", "", [{ product_id: id, quantity: 1, unit_cost: 1 }, { product_id: id, quantity: 2, unit_cost: 1 }])).toContain("dos veces");
    expect(purchaseProblem("Alicorp", "", [{ product_id: id, quantity: 1.234, unit_cost: 1 }])).toContain("2 decimales");
    expect(purchaseProblem("Alicorp", "", [{ product_id: id, quantity: 1, unit_cost: 0 }])).toContain("mayor que cero");
    expect(purchaseProblem("Alicorp", "F001-1", [{ product_id: id, quantity: 12, unit_cost: 3.8 }])).toBeNull();
  });

  it("separates what is still owed to suppliers", () => {
    const paid = row({ id: "r2", paid: { method: "yape", paid_cents: 1000, created_at: "2026-11-23" }, total_cents: 1000 });
    const old = row({ id: "r3", created_at: "2026-10-01T00:00:00Z", payment_method: "efectivo", total_cents: 500 });
    expect(isPending(paid)).toBe(false);
    expect(summarizePurchases([row(), paid, old], "2026-11")).toEqual({ month: 55.6, payable: 45.6, payableCount: 1 });
    expect(supplierSuggestions([row(), paid, row({ supplier_name: "Backus" })])).toEqual(["Alicorp", "Backus"]);
  });
});
