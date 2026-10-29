import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { readXlsx } from "../src/lib/xlsx";
import { analyzeWorkbook, isoDate, normDoc, normKind, normState, num, rucValid } from "../src/lib/workbook-import";

const FIX = join(__dirname, "fixtures");

describe("importador de libro Excel (1500 comprobantes, sintético)", () => {
  const exp = JSON.parse(readFileSync(join(FIX, "migracion_1500_esperado.json"), "utf8"));
  const sheets = readXlsx(readFileSync(join(FIX, "migracion_1500_sintetico.xlsx")));
  const { preview, payload } = analyzeWorkbook(sheets);

  it("clasifica las hojas por sus columnas e ignora la leyenda", () => {
    const roles = Object.fromEntries(preview.sheets.map((s) => [s.name, s.role]));
    expect(roles).toEqual({ LEEME: "ignorada", Clientes: "clientes", Facturas: "comprobantes", Detalle_Facturas: "detalle", Catalogo: "catalogo" });
  });
  it("cuenta exactamente lo esperado", () => {
    expect(preview.counts.clients).toBe(250);
    expect(preview.counts.documents).toBe(1500);
    expect(preview.counts.facturas).toBe(1168);
    expect(preview.counts.boletas).toBe(274);
    expect(preview.counts.credit_notes).toBe(58);
    expect(preview.counts.lines).toBe(3738);
    expect(preview.counts.products).toBe(14);
    expect(preview.counts.voided).toBe(exp.voided);
    expect(preview.counts.skipped).toBe(0);
  });
  it("total neto = ventas no anuladas − notas de crédito, por moneda", () => {
    expect(preview.totals.net).toEqual(exp.net_total);
    expect(preview.totals.receivable).toEqual(exp.receivable);
    expect(preview.totals.collected).toEqual(exp.collected);
  });
  it("usa el nombre real del cliente, nunca el id", () => {
    for (const c of payload.clients) expect(c.name).not.toMatch(/^CLI-\d+$/);
    const sinNombre = payload.docs.filter((d) => d.client_name === "Cliente sin nombre");
    expect(sinNombre.length).toBe(0); // las filas sin nombre lo toman de la hoja Clientes
  });
  it("documentos inválidos quedan como 'sin documento' con aviso", () => {
    const bad = payload.clients.filter((c) => c.doc === null && c.doc_type === "0");
    expect(bad.length).toBeGreaterThanOrEqual(exp.invalid_docs);
    expect(preview.warnings.find((w) => w.code === "doc_invalido")?.count).toBeGreaterThanOrEqual(exp.invalid_docs);
  });
});

describe("normalizadores", () => {
  it("números en formatos peruanos y europeos", () => {
    expect(num("S/ 1,234.50")).toBe(1234.5);
    expect(num("1.234,50")).toBe(1234.5);
    expect(num("")).toBeNull();
  });
  it("fechas", () => {
    expect(isoDate(45658)).toBe("2025-01-01");
    expect(isoDate("31/12/2025")).toBe("2025-12-31");
    expect(isoDate("31/02/2025")).toBeNull();
  });
  it("tipos y estados", () => {
    expect(normKind("Nota de crédito", "")).toBe("nota_credito");
    expect(normKind("", "B001-1")).toBe("boleta");
    expect(normKind("Nota de débito", "")).toBeNull();
    expect(normState("ANULADA")).toBe("anulada");
    expect(normState("Pago parcial")).toBe("parcial");
    expect(normState("Vencida")).toBe("vencida");
  });
  it("documentos", () => {
    expect(rucValid("20100070970")).toBe(true);
    expect(rucValid("20100070971")).toBe(false);
    expect(normDoc("DNI", "TESTDNI0000")).toEqual({ type: null, doc: null, invalid: true });
    expect(normDoc("DNI", "12345678").doc).toBe("12345678");
  });
});
