import { describe, expect, it } from "vitest";
import { fingerprint, nextRun, parseBankTable, parseCsv, suggestMatches } from "@/lib/erp/bank";

describe("conciliación bancaria web", () => {
  it("lee un extracto CSV con abono y cargo", () => {
    const csv = "Banco X\nFecha;Descripción;Abono;Cargo;N° Operación\n05/11/2026;TRANSF JUAN PEREZ F001-123;1.180,00;;778899\n06/11/2026;PAGO LUZ;;95,50;112233\n";
    const lines = parseBankTable(parseCsv(csv));
    expect(lines).toEqual([
      { date: "2026-11-05", description: "TRANSF JUAN PEREZ F001-123", amount: 1180, reference: "778899" },
      { date: "2026-11-06", description: "PAGO LUZ", amount: -95.5, reference: "112233" },
    ]);
  });

  it("sugiere la factura por monto, nombre y número", () => {
    const [line] = parseBankTable(parseCsv("fecha,detalle,monto\n2026-11-05,Abono Juan Perez Lopez F001-123,1180.00\n"));
    const s = suggestMatches([line], [
      { invoiceId: "x", number: "F001-999", client: "Otra Empresa", balance: 1180, issueDate: "2026-11-01" },
      { invoiceId: "y", number: "F001-123", client: "Juan Perez Lopez", balance: 1180, issueDate: "2026-11-01" },
    ]);
    expect(s).toHaveLength(1);
    expect(s[0].invoice.invoiceId).toBe("y");
    expect(s[0].why).toContain("nombre del cliente");
  });

  it("el mismo movimiento da siempre la misma huella (no se carga dos veces)", () => {
    const l = { date: "2026-11-05", description: "Ábono", amount: 10, reference: "1" };
    expect(fingerprint(l)).toBe(fingerprint({ ...l }));
    expect(fingerprint(l)).not.toBe(fingerprint({ ...l, amount: 11 }));
  });

  it("próxima fecha de una factura recurrente", () => {
    expect(nextRun(5, "2026-11-03")).toBe("2026-11-05");
    expect(nextRun(5, "2026-11-24")).toBe("2026-12-05");
    expect(nextRun(31, "2026-11-24")).toBe("2026-11-30");
    expect(nextRun(10, "2026-12-20")).toBe("2027-01-10");
  });
});
