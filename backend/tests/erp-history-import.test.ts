import { describe, expect, it } from "vitest";
import { decodeImportBytes, mergeParsed, parseDateIso, parseImportAmount, parseImportTable, parseImportText } from "@/lib/erp/history-import";

describe("importar comprobantes antiguos (web = app)", () => {
  it("lee el registro de ventas de SUNAT con serie y número separados", () => {
    const text = "Registro de ventas\n\nFecha de emisión;Serie;Número;Nro Doc Identidad;Razón social;Moneda;Importe total\n05/01/2026;F001;123;20123456789;Ferretería Sol SAC;PEN;1.234,50\n06/01/2026;B001;9;12345678;Juan Pérez;USD;99.90\n07/01/2026;B001;10;;Anulada;PEN;0\n";
    const p = parseImportText(text);
    expect(p.error).toBeUndefined();
    expect(p.rows).toHaveLength(2);
    expect(p.rejected).toBe(1);
    expect(p.rows[0]).toMatchObject({ client: "Ferretería Sol SAC", tax_id: "20123456789", number: "F001-123", date: "2026-01-05", currency: "PEN", amount: "1234.50" });
    expect(p.rows[1]).toMatchObject({ currency: "USD", amount: "99.90" });
    expect(p.columns["Número"]).toBe("Serie + Número");
  });

  it("entiende montos y fechas como la app", () => {
    expect(parseImportAmount("S/ 1,234.56")).toBe(1234.56);
    expect(parseImportAmount("1234,5")).toBe(1234.5);
    expect(parseImportAmount("1,234")).toBe(1234);
    expect(parseImportAmount("-5")).toBeNull();
    expect(parseDateIso("31/02/2026")).toBe("");
    expect(parseDateIso("2026-3-7")).toBe("2026-03-07");
  });

  it("acepta fechas de Excel como número y avisa si falta el importe", () => {
    const ok = parseImportTable([["Cliente", "Total", "Fecha"], ["Ana", "50", "46025"]]);
    expect(ok.rows[0].date).toBe("2026-01-03");
    expect(parseImportTable([["Cliente", "Nota"], ["Ana", "x"]]).error).toMatch(/importe/);
  });

  it("une varios archivos y decodifica Latin-1", () => {
    const a = parseImportText("cliente,total\nA,10\n"), b = parseImportText("cliente,total\nB,20\nC,x\n");
    const m = mergeParsed([a, b]);
    expect(m.rows.map(r => r.client)).toEqual(["A", "B"]);
    expect(m.rejected).toBe(1);
    const latin = new Uint8Array([0x4e, 0xfa, 0xf1, 0x65, 0x7a, 0xe9, 0xe1, 0xf3]);
    expect(decodeImportBytes(latin)).toBe("Núñezéáó");
  });
});
