import { describe, expect, it } from "vitest";
import { attentionList, hourLabel, hourlyRhythm, monthChange, topProducts } from "../src/lib/erp/dashboard";

describe("inicio", () => {
  it("buckets sales by Lima hour and finds the busiest one", () => {
    const r = hourlyRhythm([
      { created_at: "2026-11-23T12:10:00Z", amt_total: 10 }, // 7 a. m. Lima
      { created_at: "2026-11-23T12:50:00Z", amt_total: "5.5" },
      { created_at: "2026-11-24T00:30:00Z", amt_total: 30 }, // 7:30 p. m.
      { created_at: "2026-11-23T08:00:00Z", amt_total: 1 }, // 3 a. m. → first bar
    ]);
    expect(r.rows).toHaveLength(18);
    expect(r.peak).toBe(19);
    expect(r.rows.find(x => x.hour === 7)).toMatchObject({ total: 15.5, count: 2 });
    expect(r.rows[0]).toMatchObject({ hour: 6, total: 1 });
    expect(hourLabel(19)).toBe("7 p. m.");
    expect(hourLabel(12)).toBe("12 m.");
  });

  it("ranks best sellers by revenue, merging the same description", () => {
    const top = topProducts([
      { description: "Leche fresca 1 L", quantity: 2, unit_price: 4.95 },
      { description: "leche fresca 1 l ", quantity: 1, unit_price: 4.95 },
      { description: "Arroz extra 1 kg", quantity: 3, unit_price: 5.2 },
    ]);
    expect(top.map(t => [t.name, t.units, t.revenue])).toEqual([["Arroz extra 1 kg", 3, 15.6], ["Leche fresca 1 L", 3, 14.85]]);
    expect(monthChange(120, 100)).toBe(20);
    expect(monthChange(50, 0)).toBeNull();
  });

  it("puts SUNAT and stock problems first and links each to its fix", () => {
    const list = attentionList({ base: "/erp/o", lowStock: [{ name: "Arroz" }], overdueFiado: { count: 2, amount: "S/ 80.00" }, sunatProblems: 1, till: "abierta", afterHours: true });
    expect(list.map(a => a.id)).toEqual(["sunat", "stock", "fiado", "caja"]);
    expect(list[1]).toMatchObject({ text: "Se está acabando Arroz.", href: "/erp/o/compras" });
    expect(attentionList({ base: "/erp/o", till: "abierta", afterHours: false })).toEqual([]);
  });
});
