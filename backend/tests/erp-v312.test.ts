import { describe, expect, it } from "vitest";
import { nameSimilarity, noticeMatches, parsePaymentNotice } from "@/lib/erp/notices";
import { countText, countTotal } from "@/lib/erp/cash";

describe("avisos de Yape/Plin (web = app)", () => {
  it("lee el aviso de Yape con nombre, monto y código", () => {
    const p = parsePaymentNotice("¡Yape! JUAN PEREZ te envió un pago por S/ 25.50. El cód. de seguridad es: 123");
    expect(p).toMatchObject({ app: "yape", amount: 25.5, payer: "JUAN PEREZ", operation: "123" });
  });
  it("entiende Plin, bancos y montos con miles", () => {
    expect(parsePaymentNotice("Plin: Recibiste S/ 1,250.00 de Maria Lopez")?.amount).toBe(1250);
    expect(parsePaymentNotice("BCP: abono por transferencia de S/ 80")?.app).toBe("banco");
    expect(parsePaymentNotice("hola")).toBeNull();
  });
  it("sugiere el comprobante del mismo monto y nombre parecido", () => {
    expect(nameSimilarity("Juan P. Pere", "Juan Perez Soto")).toBeGreaterThan(0.6);
    const m = noticeMatches(50, [{ id: "a", balance: 50, client: "Rosa Diaz" }, { id: "b", balance: 50, client: "Juan Perez" }, { id: "c", balance: 40, client: "Juan Perez" }], "JUAN PEREZ");
    expect(m.map(x => x.id)).toEqual(["b", "a"]);
  });
});

describe("arqueo por billetes y monedas", () => {
  it("suma sin errores de decimales y arma el texto", () => {
    const q = { "200": 1, "50": 3, "0.1": 7, "0.2": 1, "1": 2 };
    expect(countTotal(q)).toBe(352.9);
    expect(countText(q)).toBe("200×1 · 50×3 · 1×2 · 0.20×1 · 0.10×7");
    expect(countTotal({})).toBe(0);
  });
});
