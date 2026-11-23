import { describe, expect, it } from "vitest";
import { cashBreakdown, cashDifference, methodShares, parseAmount } from "../src/lib/erp/cash";

const summary = { day: "2026-11-23", currency: "PEN", cash_opening: 50, cash_sales: 100, cash_in: 0, cash_out: 20, expected_cash: 142.4, payments_by_method: { efectivo: 100, yape: 60, plin: 0 } };

describe("caja", () => {
  it("rebuilds the expected cash, including fiado payments in cash", () => {
    const lines = cashBreakdown(summary);
    expect(lines.find(l => l.label.startsWith("Abonos"))?.value).toBeCloseTo(12.4);
    expect(lines.find(l => l.label.startsWith("Retiros"))?.sign).toBe(-1);
    expect(lines.some(l => l.label.startsWith("Otros ingresos"))).toBe(false);
  });

  it("orders payment methods by amount and skips empty ones", () => {
    expect(methodShares(summary)).toEqual([
      { method: "efectivo", label: "Efectivo", total: 100, share: 63 },
      { method: "yape", label: "Yape", total: 60, share: 38 },
    ]);
  });

  it("compares counted cash to the cent", () => {
    expect(cashDifference(62.4, 62.41)).toEqual({ kind: "cuadra", amount: 0 });
    expect(cashDifference(62.4, 60)).toEqual({ kind: "falta", amount: 2.4 });
    expect(cashDifference(62.4, 70)).toEqual({ kind: "sobra", amount: 7.6 });
  });

  it("reads amounts the way people type them", () => {
    expect(parseAmount("S/ 1,250.50")).toBe(1250.5);
    expect(parseAmount("80,5")).toBe(80.5);
    expect(parseAmount("12.345")).toBeNull();
    expect(parseAmount("-5")).toBeNull();
  });
});
