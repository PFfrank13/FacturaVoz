import { describe, expect, it } from "vitest";
import { csvCell, purchasesRegister, salesRegister, toCsv } from "@/lib/erp/registers";

describe("registros para el contador", () => {
  it("arma el registro de ventas con signo negativo en notas de crédito", () => {
    const rows = salesRegister([
      { issue_date: "2026-11-02", doc_kind: "boleta", voided_at: null, currency: "PEN", amt_base: 10, amt_tax: 1.8, amt_total: 11.8, number: "B-1",
        client: { name: "Rosa", tax_id: "12345678", doc_type: 1 }, fiscal: { doc_type: "03", series: "B001", correlative: 15, status: "accepted", totals: { icbper: 0.5 } } },
      { issue_date: "2026-11-03", doc_kind: "nota_credito", voided_at: null, currency: "PEN", amt_base: 5, amt_tax: 0.9, amt_total: 5.9, number: "NC-1",
        client: null, fiscal: { doc_type: "07", series: "BC01", correlative: 1, status: "accepted", totals: null } },
    ]);
    expect(rows[1]).toEqual(["2026-11-02", "03", "B001", 15, "1", "12345678", "Rosa", "10.00", "1.80", "0.50", "11.80", "PEN", "Aceptado"]);
    expect(rows[2].slice(7, 11)).toEqual(["-5.00", "-0.90", "0.00", "-5.90"]);
  });
  it("arma el registro de compras", () => {
    expect(purchasesRegister([{ spent_on: "2026-11-05", supplier_name: "Alicorp", supplier_tax_id: "20100055237", doc_number: "F001-9", total: 118, tax: 18, currency: "PEN", category: "mercaderia" }])[1])
      .toEqual(["2026-11-05", "Alicorp", "20100055237", "F001-9", "100.00", "18.00", "118.00", "PEN", "mercaderia"]);
  });
  it("evita fórmulas en Excel y escapa comillas", () => {
    expect(csvCell("=HYPERLINK(1)")).toBe("'=HYPERLINK(1)");
    expect(csvCell("-5.00")).toBe("-5.00");
    expect(csvCell('Bodega "Rosa", SAC')).toBe('"Bodega ""Rosa"", SAC"');
    expect(toCsv([["a"]]).startsWith("﻿")).toBe(true);
  });
});
