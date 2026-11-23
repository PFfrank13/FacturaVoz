import { describe, expect, it } from "vitest";
import { kardexTotals, mergeKardex } from "../src/lib/erp/kardex";

describe("kardex", () => {
  it("merges purchases and sales newest first, with stock after each move", () => {
    const rows = mergeKardex(
      [{ created_at: "2026-11-23T06:51:00Z", quantity_delta: "12", stock_before: "20", stock_after: "32", receipt: [{ supplier_name: "Alicorp", document_ref: "F001-9" }] }],
      [{ created_at: "2026-11-23T07:10:00Z", quantity_delta: -2, stock_before: 32, stock_after: 30, invoice: { number: "B001-00000129" } },
       { created_at: "2026-11-22T10:00:00Z", quantity_delta: -1, stock_before: 21, stock_after: 20, invoice: null }],
    );
    expect(rows.map(r => r.kind)).toEqual(["venta", "compra", "venta"]);
    expect(rows[1].ref).toBe("Alicorp · F001-9");
    expect(rows[2].ref).toBe("Venta");
    expect(kardexTotals(rows)).toEqual({ entered: 12, left: 3 });
  });
});
