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

import { cashierBreakdown } from "@/lib/erp/cash";
describe("cuadre por cajero", () => {
  it("separa efectivo y digital por persona y calcula lo que debe tener cada cajón", () => {
    const rows = cashierBreakdown(
      [{ user_id: "a", method: "efectivo", amount: 30 }, { user_id: "a", method: "yape", amount: 12.5 }, { user_id: "b", method: "efectivo", amount: "8.40" }],
      [{ id: "1", kind: "apertura", amount: 50, method: "efectivo", note: null, created_at: "", user_id: "a" },
       { id: "2", kind: "egreso", amount: 10, method: "efectivo", note: "pasajes", created_at: "", user_id: "a" },
       { id: "3", kind: "ingreso", amount: 5, method: "yape", note: null, created_at: "", user_id: "b" }],
      new Map([["a", "Rosa"], ["b", null]]));
    expect(rows[0]).toMatchObject({ name: "Rosa", cashSales: 30, digital: 12.5, opening: 50, cashOut: 10, expected: 70, count: 2 });
    expect(rows[1]).toMatchObject({ name: "Sin nombre", cashSales: 8.4, cashIn: 0, expected: 8.4 });
  });
});

import { serviceSummary } from "@/lib/erp/cash";
describe("agente y recargas", () => {
  it("se suma aparte de las ventas", () => {
    const base = { id: "x", method: "efectivo", created_at: "" };
    expect(serviceSummary([
      { ...base, kind: "ingreso", amount: 200, note: "Agente: depósito de cliente" },
      { ...base, kind: "egreso", amount: 50, note: "Agente: retiro de cliente" },
      { ...base, kind: "ingreso", amount: 10, note: "Recarga / servicio" },
      { ...base, kind: "egreso", amount: 30, note: "Pasajes" },
    ])).toEqual({ count: 3, inflow: 210, outflow: 50, net: 160 });
  });
});
