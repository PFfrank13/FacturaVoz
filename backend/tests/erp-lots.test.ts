import { describe, expect, it } from "vitest";
import { activeLots, expiryBucket, lossProblem, suggestedPrice, summarizeLosses, summarizeLots, type LossRow, type LotStatus } from "@/lib/erp/lots";
import { lastSupplierByProduct, suggestOrder, type PurchaseRow } from "@/lib/erp/purchases";
import { attentionList } from "@/lib/erp/dashboard";
import { mergeKardex } from "@/lib/erp/kardex";

const lot = (o: Partial<LotStatus>): LotStatus => ({
  lot_id: "l", product_id: "p", product_name: "Yogurt", unit: "NIU", lot_code: null, expires_on: "2026-11-30",
  quantity: 10, remaining: 10, days_left: 10, unit_cost: 2, unit_price: 3, ...o,
});

describe("vencimientos", () => {
  it("clasifica por urgencia", () => {
    expect(expiryBucket(-1)).toBe("vencido");
    expect(expiryBucket(0)).toBe("semana");
    expect(expiryBucket(7)).toBe("semana");
    expect(expiryBucket(8)).toBe("mes");
    expect(expiryBucket(31)).toBe("ok");
  });

  it("solo cuenta lotes con stock y valora al costo", () => {
    const s = summarizeLots([
      lot({ lot_id: "a", days_left: -2, remaining: 3 }),
      lot({ lot_id: "b", days_left: 2, remaining: 4, unit_cost: null, unit_price: 5 }),
      lot({ lot_id: "c", days_left: 20, remaining: 0 }),
      lot({ lot_id: "d", days_left: 60, remaining: 9 }),
    ]);
    expect(s.vencido).toEqual({ count: 1, units: 3, value: 6 });
    expect(s.semana).toEqual({ count: 1, units: 4, value: 20 });
    expect(s.mes.count).toBe(0);
  });

  it("ordena lo más urgente primero", () => {
    expect(activeLots([lot({ lot_id: "x", days_left: 9 }), lot({ lot_id: "y", days_left: -1 })]).map(l => l.lot_id)).toEqual(["y", "x"]);
  });

  it("sugiere rebaja sin bajar del costo", () => {
    expect(suggestedPrice(10, 5, 2)).toBe(7);
    expect(suggestedPrice(10, 5, 6)).toBe(8.5);
    expect(suggestedPrice(10, 9.5, 2)).toBe(9.7);
    expect(suggestedPrice(10, 5, 15)).toBeNull();
    expect(suggestedPrice(10, 5, -1)).toBeNull();
    expect(suggestedPrice(10, 10, 2)).toBeNull();
  });
});

describe("mermas", () => {
  it("valida cantidad, stock y motivo", () => {
    expect(lossProblem(2, "vencido", "", null)).toMatch(/no controla stock/);
    expect(lossProblem(0, "vencido", "", 5)).toMatch(/mayor que cero/);
    expect(lossProblem(1.234, "vencido", "", 5)).toMatch(/2 decimales/);
    expect(lossProblem(6, "vencido", "", 5)).toMatch(/superar el stock/);
    expect(lossProblem(1, "perdido", "", 5)).toMatch(/motivo/);
    expect(lossProblem(1, "otro", "  ", 5)).toMatch(/Escribe el motivo/);
    expect(lossProblem(1.5, "robo", "", 5)).toBeNull();
  });

  it("resume en soles por motivo y como % de la venta", () => {
    const row = (o: Partial<LossRow>): LossRow => ({ id: "1", product_id: "p", quantity: 1, reason: "vencido", note: null, unit_cost: 2, created_at: "", product_name: "X", lot_code: null, expires_on: null, user_name: null, ...o });
    const s = summarizeLosses([row({ quantity: 3 }), row({ reason: "robo", quantity: 1, unit_cost: 10 }), row({ reason: "danado", unit_cost: null })], 800);
    expect(s.total).toBe(16);
    expect(s.reasons[0]).toMatchObject({ reason: "robo", value: 10 });
    expect(s.share).toBe(2);
    expect(s.uncosted).toBe(1);
    expect(summarizeLosses([], null).share).toBeNull();
  });

  it("aparece en el kardex como salida", () => {
    const k = mergeKardex([], [], 30, [{ created_at: "2026-11-23T10:00:00Z", quantity: "2", stock_before: "10", stock_after: "8", reason: "vencido", note: "lote A" }]);
    expect(k[0]).toMatchObject({ kind: "merma", delta: -2, after: 8, ref: "Vencido · lote A" });
  });
});

describe("pedido sugerido", () => {
  const purchases = [{ id: "r", supplier_name: "Backus", document_ref: null, payment_method: "pendiente", total_cents: 1, created_at: "", paid: null,
    items: [{ product_id: "cerveza", name: "Cerveza", quantity: 12, unit_cost_cents: 450, line_total_cents: 5400, stock_before: 0, stock_after: 12 }] }] as PurchaseRow[];

  it("repone lo que no alcanza para 5 días o está bajo su mínimo, con su último proveedor", () => {
    const s = suggestOrder([
      { product_id: "cerveza", name: "Cerveza", stock: 6, reorder_point: null, units: 90, per_day: 3 },
      { product_id: "arroz", name: "Arroz", stock: 4, reorder_point: 5, units: 0, per_day: 0 },
      { product_id: "sal", name: "Sal", stock: 50, reorder_point: 5, units: 30, per_day: 1 },
      { product_id: "servicio", name: "Delivery", stock: null, reorder_point: null, units: 9, per_day: 1 },
    ], lastSupplierByProduct(purchases));
    expect(s.map(x => x.product_id)).toEqual(["cerveza", "arroz"]);
    expect(s[0]).toMatchObject({ quantity: 36, cover_days: 2, supplier: "Backus", unit_cost: 4.5 });
    expect(s[1]).toMatchObject({ quantity: 2, supplier: "" });
  });
});

describe("inicio", () => {
  it("avisa de vencidos y de lo que vence esta semana", () => {
    const list = attentionList({ base: "/erp/o", expiry: { expired: 2, week: 1, weekValue: "S/ 12.00" } });
    expect(list[0]).toMatchObject({ id: "vencidos", tone: "bad", href: "/erp/o/inventario" });
    expect(list.find(a => a.id === "por-vencer")?.text).toMatch(/Un lote vence esta semana \(S\/ 12.00\)/);
  });
});
