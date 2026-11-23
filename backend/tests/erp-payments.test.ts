import { describe, expect, it } from "vitest";
import { groupByDay, matchesPayment, monthBounds, parseMonth, paymentReceipt, shiftMonth, summarizePayments, type PaymentRow } from "../src/lib/erp/payments";

const pay = (id: string, amount: number, paid_on: string, method: string, extra: Partial<PaymentRow> = {}): PaymentRow => ({
  id, amount, paid_on, method, note: null, created_at: `${paid_on}T15:00:00Z`,
  invoice: { id: `i-${id}`, number: `N-${id}`, currency: "PEN", amt_total: amount, client: { name: "Rosa Quispe", tax_id: "45678912" }, fiscal: { series: "B001", correlative: 7 } },
  ...extra,
});

describe("cobros", () => {
  it("reads the month from the URL and never goes to the future", () => {
    expect(parseMonth("2026-10", "2026-11-23")).toBe("2026-10");
    expect(parseMonth("2026-12", "2026-11-23")).toBe("2026-11");
    expect(parseMonth("2026-13", "2026-11-23")).toBe("2026-11");
    expect(parseMonth(undefined, "2026-11-23")).toBe("2026-11");
  });

  it("moves between months and knows their length", () => {
    expect(shiftMonth("2026-01", -1)).toBe("2025-12");
    expect(shiftMonth("2026-12", 1)).toBe("2027-01");
    expect(monthBounds("2028-02")).toEqual({ from: "2028-02-01", to: "2028-02-29", days: 29 });
  });

  it("sums to the cent, by method, and keeps other currencies apart", () => {
    const rows = [
      pay("a", 10.1, "2026-11-02", "efectivo"),
      pay("b", 20.2, "2026-11-02", "yape"),
      pay("c", 30, "2026-11-20", "yape"),
      pay("d", 99, "2026-11-21", "tarjeta", { invoice: { id: "x", number: "F-1", currency: "USD", amt_total: 99, client: null, fiscal: null } }),
    ];
    const s = summarizePayments(rows, "PEN", "2026-11", "2026-11-23");
    expect(s.total).toBe(60.3);
    expect(s.count).toBe(3);
    expect(s.average).toBe(20.1);
    expect(s.other).toBe(1);
    expect(s.methods.map(m => [m.label, m.total, m.share])).toEqual([["Yape", 50.2, 83], ["Efectivo", 10.1, 17]]);
    expect(s.digitalShare).toBe(83);
    expect(s.days).toHaveLength(30);
    expect(s.days[1]).toMatchObject({ day: 2, total: 30.3, count: 2 });
    expect(s.best).toBe(2);
    expect(s.days[23].future).toBe(true);
    expect(s.days[22].future).toBe(false);
  });

  it("is empty but well formed without payments", () => {
    const s = summarizePayments([], "PEN", "2026-10", "2026-11-23");
    expect(s).toMatchObject({ total: 0, count: 0, average: 0, digitalShare: 0, best: null, methods: [] });
    expect(s.days.every(d => !d.future)).toBe(true);
  });

  it("finds payments by receipt, client, document or note and filters by method", () => {
    const p = pay("a", 10, "2026-11-02", "plin", { note: "Abono pedido" });
    expect(paymentReceipt(p)).toBe("B001-00000007");
    expect(matchesPayment(p, { q: "b001-0000" })).toBe(true);
    expect(matchesPayment(p, { q: "rosa" })).toBe(true);
    expect(matchesPayment(p, { q: "456789" })).toBe(true);
    expect(matchesPayment(p, { q: "pedido" })).toBe(true);
    expect(matchesPayment(p, { method: "yape" })).toBe(false);
    expect(matchesPayment(p, { q: "otro cliente" })).toBe(false);
  });

  it("groups by day, newest first, with subtotals", () => {
    const g = groupByDay([pay("a", 1.1, "2026-11-01", "efectivo"), pay("b", 2.2, "2026-11-03", "yape"), pay("c", 3.3, "2026-11-03", "plin")]);
    expect(g.map(x => [x.day, x.total, x.items.length])).toEqual([["2026-11-03", 5.5, 2], ["2026-11-01", 1.1, 1]]);
  });
});
