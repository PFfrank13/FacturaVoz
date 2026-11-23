import { describe, expect, it } from "vitest";
import { buildInvoicePayload, validateFiscalInput, type BuildInput } from "@/lib/fiscal/payload";
import { calc } from "@/lib/fiscal/calc";

type Doc = { icbper?: number; mtoImpVenta: number; valorVenta: number; mtoIGV: number; totalImpuestos: number; details: Record<string, unknown>[] };

const base: BuildInput = {
  docType: "03", currency: "PEN", afectacion: "gravado", taxRate: 18, unit: "NIU",
  issuer: { ruc: "20123456789", razonSocial: "Bodega Rosa", ubigeo: "150101", departamento: "LIMA", provincia: "LIMA", distrito: "LIMA", direccion: "Av. Uno 123" },
  client: { tipoDoc: "-", numDoc: "-", name: "Clientes varios" },
  lines: [
    { description: "Gaseosa 500 ml", quantity: 1, unit_price: 2.54 },
    { description: "Bolsa plástica", quantity: 2, unit_price: 0.51, icbper: true },
  ],
  now: new Date("2026-11-23T15:00:00Z"),
};

describe("ICBPER (bolsas plásticas)", () => {
  it("separa S/ 0.50 por bolsa sin cambiar el total cobrado", () => {
    const total = calc(base.lines, "gravado", 18).total;
    const { payload, totals } = buildInvoicePayload(base);
    const p = payload as unknown as Doc;
    expect((totals as { icbper?: number }).icbper).toBe(1);
    expect(p.icbper).toBe(1);
    expect(p.mtoImpVenta).toBe(total);
    expect(Math.round((p.valorVenta + p.mtoIGV + (p.icbper ?? 0)) * 100) / 100).toBe(total);
    expect(p.totalImpuestos).toBe(Math.round((p.mtoIGV + 1) * 100) / 100);
    const bag = p.details[1];
    expect(bag).toMatchObject({ factorIcbper: 0.5, icbper: 1, mtoValorVenta: 0.17, igv: 0.03 });
    expect(p.details[0].icbper).toBeUndefined();
  });

  it("rechaza una bolsa cuyo precio no alcanza el impuesto o vendida en fracciones", () => {
    expect(validateFiscalInput({ ...base, lines: [{ description: "Bolsa", quantity: 1, unit_price: 0.42, icbper: true }] })).toMatch(/S\/ 0.50 por bolsa/);
    expect(validateFiscalInput({ ...base, lines: [{ description: "Bolsa", quantity: 1.5, unit_price: 1, icbper: true }] })).toMatch(/unidad entera/);
    expect(validateFiscalInput(base)).toBeNull();
  });

  it("sin bolsas el comprobante queda igual que antes", () => {
    const { payload } = buildInvoicePayload({ ...base, lines: [base.lines[0]] });
    const p = payload as unknown as Doc;
    expect(p.icbper).toBeUndefined();
    expect(p.totalImpuestos).toBe(p.mtoIGV);
  });
});
