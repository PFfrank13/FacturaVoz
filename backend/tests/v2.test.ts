import { createHmac, generateKeyPairSync, sign } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt, sanitizeAssistant } from "../src/lib/assistant";
import { buildDayCloseEmail } from "../src/lib/dayclose";
import { kindOf, normalizeDoc, rucValid } from "../src/lib/doclookup";
import { normalizeFx } from "../src/lib/fx";
import { sanitizeNotebook } from "../src/lib/notebook";
import { encodeQr, qrSvg } from "../src/lib/qr";
import { effectiveMode, verifyToken, verifyWebhook } from "../src/lib/solvex";
import { estimateTaxes } from "../src/lib/taxes";
import { nextAttempt, safeWebhookUrl, signWebhook } from "../src/lib/webhooks";

// Token con el MISMO formato que firma Solvex Hub (src/lib/jws.js): cabecera.contenido.firma, EdDSA, typ slx-license+jwt.
const kp = generateKeyPairSync("ed25519");
const rawPub = Buffer.from((kp.publicKey.export({ format: "jwk" }) as { x: string }).x, "base64url").toString("base64");
const b64u = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
function hubToken(payload: Record<string, unknown>, header: Record<string, unknown> = { alg: "EdDSA", typ: "slx-license+jwt", kid: "slx-test" }) {
  const input = `${b64u(header)}.${b64u(payload)}`;
  return `${input}.${sign(null, Buffer.from(input), kp.privateKey).toString("base64url")}`;
}
const now = Math.floor(Date.now() / 1000);
const base = { iss: "solvex-hub", aud: "ins_aaaaaaaaaaaaaaaaaaaa", iat: now, nbf: now - 60, exp: now + 3600, tenant: "6f1c2a3b-0000-4000-8000-000000000001", mode: "full", plan: "PRO" };

describe("Solvex Hub: tokens Ed25519", () => {
  it("acepta un token válido para esta instancia", () => {
    const p = verifyToken(hubToken(base), [rawPub], { audience: base.aud });
    expect(p.plan).toBe("PRO");
  });
  it("rechaza otra audiencia, firma alterada, alg none, vencido y emisor falso", () => {
    expect(() => verifyToken(hubToken(base), [rawPub], { audience: "ins_otro" })).toThrow();
    const t = hubToken(base);
    expect(() => verifyToken(t.slice(0, -3) + (t.endsWith("A") ? "BBB" : "AAA"), [rawPub])).toThrow();
    expect(() => verifyToken(hubToken(base, { alg: "none", typ: "slx-license+jwt" }), [rawPub])).toThrow();
    expect(() => verifyToken(hubToken({ ...base, exp: now - 600 }), [rawPub])).toThrow();
    expect(() => verifyToken(hubToken({ ...base, iss: "otro" }), [rawPub])).toThrow();
    const other = generateKeyPairSync("ed25519");
    const otherRaw = Buffer.from((other.publicKey.export({ format: "jwk" }) as { x: string }).x, "base64url").toString("base64");
    expect(() => verifyToken(hubToken(base), [otherRaw])).toThrow();
  });
  it("corta sin conexión cuando el corte anunciado ya pasó", () => {
    expect(effectiveMode({ ...base, mode: "warning", auto_cut: true, cut_at: new Date(Date.now() - 1000).toISOString() } as never)).toBe("restricted");
    expect(effectiveMode({ ...base, mode: "warning", auto_cut: true, cut_at: new Date(Date.now() + 864e5).toISOString() } as never)).toBe("warning");
    expect(effectiveMode(null)).toBe("blocked");
  });
  it("webhook: HMAC del cuerpo crudo + anti-reproducción de 5 minutos", () => {
    const body = '{"id":"evt_1","type":"ping"}';
    const ts = String(now);
    const sig = "v1=" + createHmac("sha256", "s3cr3t").update(`${ts}.${body}`).digest("hex");
    expect(verifyWebhook({ secret: "s3cr3t", timestamp: ts, signature: sig, rawBody: body })).toBe(true);
    expect(verifyWebhook({ secret: "s3cr3t", timestamp: ts, signature: sig, rawBody: body + " " })).toBe(false);
    expect(verifyWebhook({ secret: "otro", timestamp: ts, signature: sig, rawBody: body })).toBe(false);
    expect(verifyWebhook({ secret: "s3cr3t", timestamp: String(now - 400), signature: sig, rawBody: body })).toBe(false);
  });
});

describe("QR SUNAT (nivel Q)", () => {
  it("codifica el contenido del Anexo 6 en una versión pequeña", () => {
    const q = encodeQr("20100070970|01|F001|00000023|18.00|118.00|2026-10-28|6|20480072872|");
    expect(q.version).toBe(6);
    expect(q.size).toBe(41);
    expect(qrSvg("x")).toContain("<svg");
  });
});

describe("DNI/RUC", () => {
  it("valida el dígito verificador del RUC", () => {
    expect(rucValid("20100070970")).toBe(true);
    expect(rucValid("20100070971")).toBe(false);
    expect(kindOf("12345678")).toBe("dni");
    expect(kindOf("20100070970")).toBe("ruc");
    expect(kindOf("123")).toBeNull();
  });
  it("normaliza respuestas de distintos proveedores", () => {
    const a = normalizeDoc("dni", "12345678", { first_name: "Juan", first_last_name: "Pérez", second_last_name: "Rojas" });
    expect(a?.name).toBe("JUAN PÉREZ ROJAS");
    const b = normalizeDoc("ruc", "20100070970", { data: { razonSocial: "Gloria S.A.", direccion: "Av. X 123", estado: "activo", condicion: "habido" } });
    expect(b).toMatchObject({ name: "GLORIA S.A.", address: "Av. X 123", status: "ACTIVO", condition: "HABIDO" });
    expect(normalizeDoc("ruc", "20100070970", { message: "no encontrado" })).toBeNull();
  });
});

describe("Impuestos (estimado)", () => {
  it("NRUS: cuota por categoría y alerta de tope", () => {
    expect(estimateTaxes({ regime: "nrus", monthSalesBase: 4000, monthSalesTax: 0, monthPurchasesTax: 0, yearSalesBase: 30000 }).total).toBe(20);
    const e = estimateTaxes({ regime: "nrus", monthSalesBase: 9000, monthSalesTax: 0, monthPurchasesTax: 0, yearSalesBase: 90000 });
    expect(e.total).toBe(50);
    expect(e.warnings.length).toBeGreaterThan(0);
  });
  it("RMT: IGV menos crédito fiscal + 1 % de renta", () => {
    const e = estimateTaxes({ regime: "rmt", monthSalesBase: 10000, monthSalesTax: 1800, monthPurchasesTax: 500, yearSalesBase: 80000 });
    expect(e.igv).toBe(1300);
    expect(e.renta).toBe(100);
    expect(e.total).toBe(1400);
  });
  it("saldo a favor de IGV no da impuesto negativo", () => {
    const e = estimateTaxes({ regime: "rer", monthSalesBase: 1000, monthSalesTax: 180, monthPurchasesTax: 400, yearSalesBase: 1000 });
    expect(e.igv).toBe(0);
    expect(e.renta).toBe(15);
  });
});

describe("Copiloto 2.0", () => {
  it("acciones por voz validadas", () => {
    const v = sanitizeAssistant({ intent: "void", answer: "Anularé", action: { type: "void", client_name: "Juan", doc_kind: "boleta" } });
    expect(v.action).toEqual({ type: "void", client_name: "Juan", doc_kind: "boleta" });
    const s = sanitizeAssistant({ intent: "show", answer: "Ventas de ayer", action: { screen: "nada", range: "yesterday" } });
    expect(s.action).toEqual({ type: "show", screen: "sales", range: "yesterday" });
    const f = sanitizeAssistant({ intent: "fiado", answer: "ok", action: { client_name: "Rosa", kind: "cargo", amount: "30", description: "arroz" } });
    expect(f.action).toMatchObject({ type: "fiado", client_name: "Rosa", amount: 30 });
    expect(sanitizeAssistant({ intent: "fiado", answer: "ok", action: { client_name: "", amount: 0 } }).intent).toBe("unknown");
    expect(sanitizeAssistant({ intent: "summary", answer: "x".repeat(1000), speak: "y".repeat(800) }).speak.length).toBe(520);
  });
  it("el prompt incluye impuestos y las nuevas intenciones", () => {
    const p = buildSystemPrompt({ taxes: { igv: 10 } }, "Bodega");
    expect(p).toContain('"void"');
    expect(p).toContain("confírmalo con tu contador");
  });
});

describe("Cuaderno → venta", () => {
  it("modera la confianza de la letra a mano y limpia ítems", () => {
    const n = sanitizeNotebook({ client_name: "Doña Rosa", client_doc: "1234", handwritten: true, confidence: 0.95, items: [{ description: "Arroz", quantity: "3", unit_price: "4,50" }, { description: "" }] });
    expect(n.confidence).toBe(0.75);
    expect(n.client_doc).toBe("");
    expect(n.items).toEqual([{ description: "Arroz", quantity: 3, unit_price: 4.5 }]);
  });
});

describe("Webhooks salientes y tipo de cambio", () => {
  it("firma, reintentos y URLs seguras", () => {
    expect(signWebhook("k", 1, "{}")).toBe("v1=" + createHmac("sha256", "k").update("1.{}").digest("hex"));
    expect(Date.parse(nextAttempt(0, 0))).toBe(60_000);
    expect(safeWebhookUrl("https://mi-tienda.com/hook")).toBe(true);
    expect(safeWebhookUrl("http://mi-tienda.com/hook")).toBe(false);
    expect(safeWebhookUrl("https://127.0.0.1/x")).toBe(false);
    expect(safeWebhookUrl("https://192.168.1.5/x")).toBe(false);
  });
  it("normaliza el tipo de cambio", () => {
    expect(normalizeFx({ buy_price: "3.745", sell_price: "3.752" })).toEqual({ buy: 3.745, sell: 3.752 });
    expect(normalizeFx([{ compra: 3.7, venta: 3.71 }])).toEqual({ buy: 3.7, sell: 3.71 });
    expect(normalizeFx({})).toBeNull();
  });
});

describe("Cierre del día", () => {
  it("arma el correo con diferencia de caja", () => {
    const m = buildDayCloseEmail({ business: "Bodega <Pepe>", counted: 90, closedBy: "Lucía", summary: { day: "2026-10-28", currency: "PEN", sales: { sales_total: 120, sales_count: 3 }, payments_by_method: { efectivo: 100 }, expected_cash: 100 } });
    expect(m.subject).toContain("28/10/2026");
    expect(m.html).toContain("Bodega &lt;Pepe&gt;");
    expect(m.html).toContain("Diferencia");
  });
});
