import { describe, expect, it } from "vitest";
import { matchesReceipt, receiptKind, receiptNumber, summarize, sunatState, voidHint, voidWindow, type ReceiptRow } from "../src/lib/erp/receipts";

const base: ReceiptRow = {
  id: "1", number: "V-0001", issue_date: "2026-11-20", status: "sent", currency: "PEN", doc_kind: "boleta",
  amt_total: "25.50", voided_at: null, client: { name: "Rosa Quispe", tax_id: "45871236" },
  fiscal: { doc_type: "03", series: "B001", correlative: 128, status: "accepted", sunat_code: "0", sunat_message: null, issued_at: "2026-11-20T15:00:00Z" },
};

describe("receipts", () => {
  it("derives kind, number and SUNAT state from the fiscal document", () => {
    expect(receiptKind(base)).toBe("boleta");
    expect(receiptNumber(base)).toBe("B001-00000128");
    expect(sunatState(base)).toBe("aceptado");
    expect(sunatState({ ...base, voided_at: "2026-11-21" })).toBe("anulado");
    expect(sunatState({ ...base, fiscal: null })).toBe("sin_envio");
    expect(receiptKind({ ...base, fiscal: null, doc_kind: null })).toBe("borrador");
  });

  it("boletas cancel in the daily summary and facturas by baja, up to 7 days", () => {
    expect(voidWindow(base, "2026-11-22")).toEqual({ kind: "resumen", until: "2026-11-27" });
    const factura = { ...base, fiscal: { ...base.fiscal!, doc_type: "01" } };
    expect(voidWindow(factura, "2026-11-27")).toEqual({ kind: "baja", until: "2026-11-27" });
    expect(voidWindow(factura, "2026-11-28").kind).toBe("nota_credito");
    expect(voidHint(voidWindow(factura, "2026-11-28"))).toContain("nota de crédito");
    expect(voidWindow({ ...base, fiscal: { ...base.fiscal!, status: "pending" } }, "2026-11-22").kind).toBe("none");
  });

  it("filters by text, kind and state, and totals exclude voided receipts and credit notes", () => {
    expect(matchesReceipt(base, { q: "quispe" })).toBe(true);
    expect(matchesReceipt(base, { q: "b001-00000128" })).toBe(true);
    expect(matchesReceipt(base, { kind: "factura" })).toBe(false);
    expect(matchesReceipt(base, { sunat: "rechazado" })).toBe(false);
    const s = summarize([base, { ...base, id: "2", voided_at: "x", amt_total: 100 }, { ...base, id: "3", fiscal: { ...base.fiscal!, status: "rejected" } }]);
    expect(s.total).toBeCloseTo(51);
    expect(s.accepted).toBe(1);
    expect(s.attention).toBe(1);
  });
});

describe("draft receipts", () => {
  it("explains the first problem in plain words, per line", async () => {
    const { draftProblem } = await import("../src/lib/schemas");
    const line = { description: "Gaseosa", quantity: 1, unit_price: 2.5 };
    expect(draftProblem({ client_name: "Cliente varios", tax_rate: 18, items: [line] })).toBeNull();
    expect(draftProblem({ client_name: "x", tax_rate: 18, items: [{ ...line, description: " " }] })).toBe("Escribe la descripción.");
    expect(draftProblem({ client_name: "x", tax_rate: 18, items: [line, { ...line, quantity: 0 }] })).toBe("La cantidad del artículo 2 debe ser mayor que cero.");
    expect(draftProblem({ client_name: "x", tax_rate: 120, items: [line] })).toContain("IGV");
  });
});
