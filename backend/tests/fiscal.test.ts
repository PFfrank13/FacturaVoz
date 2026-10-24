import { describe, expect, it } from "vitest";
import { amountLegend, integerToWords } from "../src/lib/fiscal/words";
import { calc } from "../src/lib/fiscal/calc";
import { isValidRuc, validateClientDoc } from "../src/lib/fiscal/ids";
import { buildInvoicePayload, limaIso, validateFiscalInput, type BuildInput } from "../src/lib/fiscal/payload";
import { interpretSend } from "../src/lib/fiscal/lycet";

describe("importe en letras", () => {
  it.each([
    [0, "CERO"], [1, "UNO"], [15, "QUINCE"], [21, "VEINTIUNO"], [31, "TREINTA Y UNO"], [100, "CIEN"],
    [101, "CIENTO UNO"], [115, "CIENTO QUINCE"], [1000, "MIL"], [1001, "MIL UNO"], [2000, "DOS MIL"],
    [21000, "VEINTIÚN MIL"], [101000, "CIENTO UN MIL"], [1_000_000, "UN MILLÓN"],
    [2_500_000, "DOS MILLONES QUINIENTOS MIL"], [1_000_000_000, "MIL MILLONES"],
  ])("%i", (n, w) => expect(integerToWords(n)).toBe(w));

  it("leyenda SUNAT (ejemplo oficial de Lycet)", () => {
    expect(amountLegend(363.03, "PEN")).toBe("SON TRESCIENTOS SESENTA Y TRES CON 03/100 SOLES");
    expect(amountLegend(1250.5, "USD")).toBe("SON MIL DOSCIENTOS CINCUENTA CON 50/100 DÓLARES AMERICANOS");
  });
});

describe("cálculo por línea", () => {
  it("coincide con el ejemplo de Greenter (307.65 + 55.38 = 363.03)", () => {
    const c = calc([{ description: "x", quantity: 3, unit_price: 102.55 }], "gravado", 18);
    expect(c.base).toBe(307.65);
    expect(c.igv).toBe(55.38);
    expect(c.total).toBe(363.03);
  });
  it("el IGV total es la suma del IGV por línea", () => {
    const c = calc([
      { description: "a", quantity: 1, unit_price: 0.55 },
      { description: "b", quantity: 1, unit_price: 0.55 },
    ], "gravado", 18);
    expect(c.lines.map((l) => l.igv)).toEqual([0.1, 0.1]);
    expect(c.igv).toBe(0.2);
  });
  it("exonerado no lleva IGV", () => {
    expect(calc([{ description: "a", quantity: 2, unit_price: 10 }], "exonerado", 0).igv).toBe(0);
  });
});

describe("documentos", () => {
  it("RUC con dígito verificador", () => {
    expect(isValidRuc("20000000001")).toBe(true);
    expect(isValidRuc("20480072872")).toBe(true);
    expect(isValidRuc("20480072873")).toBe(false);
    expect(isValidRuc("12345678901")).toBe(false);
    expect(isValidRuc("2048007287")).toBe(false);
  });
  it("tipos de documento del cliente", () => {
    expect(validateClientDoc("1", "46466400")).toEqual({ ok: true, tipoDoc: "1", numDoc: "46466400" });
    expect(validateClientDoc("1", "1234").ok).toBe(false);
    expect(validateClientDoc("0", "")).toEqual({ ok: true, tipoDoc: "-", numDoc: "-" });
    expect(validateClientDoc("9", "1").ok).toBe(false);
  });
});

const issuer = {
  ruc: "20000000001", razonSocial: "EMPRESA PRUEBA SAC", ubigeo: "150101", departamento: "LIMA",
  provincia: "LIMA", distrito: "LIMA", direccion: "AV. EJEMPLO 123",
};
const base = (o: Partial<BuildInput> = {}): BuildInput => ({
  docType: "01", currency: "PEN", afectacion: "gravado", taxRate: 18, unit: "NIU", issuer,
  client: { tipoDoc: "6", numDoc: "20480072872", name: "CLIENTE SAC" },
  lines: [{ description: "Servicio", quantity: 2, unit_price: 100.5 }],
  now: new Date("2026-10-23T19:30:00Z"), ...o,
});

describe("payload", () => {
  it("hora de Lima", () => expect(limaIso(new Date("2026-10-23T19:30:00Z"))).toBe("2026-10-23T14:30:00-05:00"));

  it("factura gravada", () => {
    const { payload, totals, legend } = buildInvoicePayload(base());
    expect(totals).toEqual({ gravadas: 201, exoneradas: 0, inafectas: 0, igv: 36.18, total: 237.18 });
    expect(payload.mtoImpVenta).toBe(237.18);
    expect(payload.mtoOperExoneradas).toBeUndefined();
    expect(legend).toBe("SON DOSCIENTOS TREINTA Y SIETE CON 18/100 SOLES");
    expect((payload.details as Array<Record<string, unknown>>)[0]).toMatchObject({ tipAfeIgv: "10", igv: 36.18, mtoPrecioUnitario: 118.59 });
  });

  it("validaciones", () => {
    expect(validateFiscalInput(base())).toBeNull();
    expect(validateFiscalInput(base({ taxRate: 10 }))).toMatch(/18%/);
    expect(validateFiscalInput(base({ client: { tipoDoc: "1", numDoc: "46466400", name: "Juan" } }))).toMatch(/RUC/);
    expect(validateFiscalInput(base({ issuer: { ...issuer, ubigeo: "" } }))).toMatch(/ubigeo/);
    expect(validateFiscalInput(base({ docType: "03", client: { tipoDoc: "-", numDoc: "-", name: "x" }, lines: [{ description: "a", quantity: 1, unit_price: 700 }] }))).toMatch(/700/);
    expect(validateFiscalInput(base({ docType: "03", client: { tipoDoc: "-", numDoc: "-", name: "x" }, lines: [{ description: "a", quantity: 1, unit_price: 50 }] }))).toBeNull();
  });
});

describe("respuesta de SUNAT", () => {
  const ok = (code: string, notes: string[] = []) => ({
    xml: "<x/>", hash: "H",
    sunatResponse: { success: true, cdrZip: "ZIP", cdrResponse: { code, description: "La Factura ha sido aceptada", notes } },
  });
  it("aceptada", () => expect(interpretSend(ok("0")).status).toBe("accepted"));
  it("aceptada con observaciones (4xxx)", () => expect(interpretSend(ok("0", ["4252 obs"])).status).toBe("accepted"));
  it("rechazada por CDR", () => expect(interpretSend(ok("2335")).status).toBe("rejected"));
  it("rechazo por fault 2xxx/3xxx", () =>
    expect(interpretSend({ sunatResponse: { success: false, error: { code: "2335", message: "El documento electrónico ingresado ha sido alterado" } } }).status).toBe("rejected"));
  it("fallo de servicio/autenticación NO es rechazo (se puede reintentar)", () => {
    expect(interpretSend({ sunatResponse: { success: false, error: { code: "0111", message: "No tiene el perfil" } } }).status).toBe("error");
    expect(interpretSend({ sunatResponse: { success: false, error: { code: "HTTP", message: "timeout" } } }).status).toBe("error");
    expect(interpretSend(null).status).toBe("error");
  });
});
