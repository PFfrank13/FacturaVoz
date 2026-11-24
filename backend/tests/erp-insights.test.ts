import { describe, expect, it } from "vitest";
import { aging, creditLevel, expectedPayDate, forecastCash, isReceivable, profitOf, reminderText, scoreClient, segmentClients, type Receivable } from "@/lib/erp/insights";

const rec = (o: Partial<Receivable>): Receivable => ({ id: "i", number: "F001-1", client: "Ana Pérez", client_id: null, phone: null, email: null, issue_date: "2026-11-01", due_date: "2026-11-10", currency: "PEN", total: 100, paid: 0, balance: 100, last_reminder: null, ...o });

describe("cobranza, crédito, clientes 360 y ganancia real (web = app)", () => {
  it("solo cuenta lo que de verdad se debe", () => {
    expect(isReceivable({ status: "sent", voided: false, fiscal_status: "accepted", doc_kind: "boleta", balance: 10 })).toBe(true);
    expect(isReceivable({ status: "sent", voided: true, fiscal_status: null, doc_kind: null, balance: 10 })).toBe(false);
    expect(isReceivable({ status: "sent", voided: false, fiscal_status: "rejected", doc_kind: null, balance: 10 })).toBe(false);
    expect(isReceivable({ status: "sent", voided: false, fiscal_status: null, doc_kind: "nota_credito", balance: 10 })).toBe(false);
  });

  it("agrupa por antigüedad", () => {
    const a = aging([rec({ due_date: "2026-11-30" }), rec({ due_date: "2026-11-20", balance: 50 }), rec({ due_date: "2026-09-01", balance: 30 })], "2026-11-24");
    expect(a).toMatchObject({ current: 100, d1_30: 50, d60: 30, overdue: 80, total: 180 });
  });

  it("puntúa al cliente y proyecta la caja", () => {
    expect(scoreClient(undefined).grade).toBe("?");
    expect(scoreClient({ key: "a", settled: 5, avg_days_to_pay: 3, avg_days_late: 0, max_days_late: 0, overdue_balance: 0 }).grade).toBe("A");
    expect(scoreClient({ key: "a", settled: 5, avg_days_to_pay: 40, avg_days_late: 25, max_days_late: 40, overdue_balance: 10 }).grade).toBe("D");
    expect(expectedPayDate({ due_date: "2026-11-01", issue_date: "2026-10-01" }, undefined, "2026-11-24")).toBe("2026-12-01");
    const f = forecastCash([rec({ due_date: "2026-11-26" })], new Map(), 10, "2026-11-24");
    expect(f.weeks[0]).toMatchObject({ inflow: 75, outflow: 70, cumulative: 5 });
    expect(f.warning).toMatch(/superarían/);
  });

  it("recordatorio amable con enlace de pago", () => {
    expect(reminderText(rec({}), "Bodega Lupe", "2026-11-24", "https://x/pagar/t")).toBe("Hola Ana, te saluda Bodega Lupe. Te recordamos el comprobante F001-1 por S/ 100.00 que venció el 10/11. Puedes pagarlo aquí: https://x/pagar/t ¡Gracias!");
  });

  it("niveles de crédito", () => {
    expect(creditLevel(null, 50)).toBe("none");
    expect(creditLevel(100, 50)).toBe("ok");
    expect(creditLevel(100, 85)).toBe("near");
    expect(creditLevel(100, 101)).toBe("over");
  });

  it("segmenta clientes como la app", () => {
    const s = segmentClients([
      { key: "a", name: "A", purchases: 10, total: 1000, last_purchase: "2026-11-20", avg_gap: 7, days_since: 4 },
      { key: "b", name: "B", purchases: 4, total: 200, last_purchase: "2026-09-01", avg_gap: 10, days_since: 84 },
      { key: "c", name: "C", purchases: 1, total: 20, last_purchase: "2026-11-10", avg_gap: null, days_since: 14 },
    ]);
    expect(s.map(i => i.segment)).toEqual(["vip", "atRisk", "newcomer"]);
    expect(s[1].at_risk_value).toBe(50);
  });

  it("ganancia: ventas sin IGV menos gastos sin IGV", () => {
    const p = profitOf({ sales: 1000, salesTax: 180, expenses: [{ total: 118, tax: 18 }], cashIn: 500, count: 3 });
    expect(p).toMatchObject({ profit: 900, expenses: 100, igv: 162, cashOut: 118, netCash: 382 });
  });
});
