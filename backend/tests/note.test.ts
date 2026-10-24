import { describe, expect, it } from "vitest";
import { buildInvoicePayload, type BuildInput } from "../src/lib/fiscal/payload";
import { buildNotePayload, cleanReasonText, noteSeriesFor } from "../src/lib/fiscal/note";

const input: BuildInput = {
  docType: "01",
  currency: "PEN",
  afectacion: "gravado",
  taxRate: 18,
  unit: "NIU",
  issuer: { ruc: "20000000001", razonSocial: "DEMO SAC", ubigeo: "150101", departamento: "LIMA", provincia: "LIMA", distrito: "LIMA", direccion: "AV. DEMO 123" },
  client: { tipoDoc: "6", numDoc: "20100070970", name: "CLIENTE SA" },
  lines: [{ description: "Servicio", quantity: 3, unit_price: 102.55 }],
  now: new Date("2026-10-24T15:00:00Z"),
};

describe("nota de crédito", () => {
  const orig: Record<string, unknown> = { ...buildInvoicePayload(input).payload, serie: "F001", correlativo: "7" };

  it("series: F001 -> FC01, B002 -> BC02", () => {
    expect(noteSeriesFor("F001")).toBe("FC01");
    expect(noteSeriesFor("B002")).toBe("BC02");
  });

  it("copia importes y líneas del original y referencia su número exacto", () => {
    const { payload, totals } = buildNotePayload(orig, "01", "ANULACION DE LA OPERACION", new Date("2026-10-25T15:00:00Z"));
    expect(payload.tipoDoc).toBe("07");
    expect(payload.tipDocAfectado).toBe("01");
    expect(payload.numDocfectado).toBe("F001-7");
    expect(payload.codMotivo).toBe("01");
    expect(payload.mtoImpVenta).toBe(orig.mtoImpVenta);
    expect(payload.details).toEqual(orig.details);
    expect(payload.fechaEmision).toBe("2026-10-25T10:00:00-05:00");
    expect("formaPago" in payload).toBe(false);
    expect("tipoOperacion" in payload).toBe(false);
    expect(totals.total).toBe(363.03);
    expect(totals.igv).toBe(55.38);
  });

  it("rechaza tipos no admitidos", () => {
    expect(() => buildNotePayload({ ...orig, tipoDoc: "07" }, "01", "x")).toThrow();
  });

  it("limpia el texto del motivo", () => {
    expect(cleanReasonText("01", "<script>x</script>")).not.toMatch(/[<>]/);
    expect(cleanReasonText("06", "   ")).toBe("DEVOLUCION TOTAL");
    expect(cleanReasonText("01", "a".repeat(400)).length).toBe(250);
  });
});
