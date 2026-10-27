import { describe, expect, it } from "vitest";
import { buildEmail, buildImportEmail, escapeHtml, isEmail, looksLikePdf, safeFilename, senderFor } from "../src/lib/email";

describe("email utils", () => {
  it("valida correos y rechaza inyección de cabeceras", () => {
    expect(isEmail("cliente@empresa.pe")).toBe(true);
    expect(isEmail("a@b")).toBe(false);
    expect(isEmail("a@b.com\nBcc: x@y.com")).toBe(false);
    expect(isEmail("a b@c.com")).toBe(false);
    expect(isEmail(42)).toBe(false);
  });
  it("detecta PDFs por firma", () => {
    expect(looksLikePdf(new TextEncoder().encode("%PDF-1.7 xxxx"))).toBe(true);
    expect(looksLikePdf(new TextEncoder().encode("<html>......"))).toBe(false);
  });
  it("escapa HTML y limpia nombres de archivo", () => {
    expect(escapeHtml(`<b>"x"&'`)).toBe("&lt;b&gt;&quot;x&quot;&amp;&#39;");
    expect(safeFilename("F001-00000001/../x")).toBe("F001-00000001_.._x.pdf");
    const m = buildEmail({ business: "<script>", client: "Ana", number: "F001-1", total: "PEN 10.00" });
    expect(m.html).not.toContain("<script>");
  });
  it("aviso de importación escapa y resume", () => {
    const ok = buildImportEmail({ business: "<b>X</b>", status: "done", imported: 1005, skipped: 995 });
    expect(ok.subject).toMatch(/importadas/);
    expect(ok.html).toContain("1005");
    expect(ok.html).not.toContain("<b>X</b>");
    expect(buildImportEmail({ business: "A", status: "failed", imported: 0, skipped: 0, error: "<x>" }).html).not.toContain("<x>");
  });
});

describe("remitente", () => {
  it("usa el nombre del negocio con la dirección verificada y bloquea inyección", () => {
    const from = "FacturaVoz <facturas@facturavoz.solvexsoftware.dev>";
    expect(senderFor("Ferretería Díaz", from)).toBe('"Ferretería Díaz vía FacturaVoz" <facturas@facturavoz.solvexsoftware.dev>');
    expect(senderFor('X"\r\nBcc: a@b.com <y>', from)).not.toMatch(/[\r\n]|Bcc: a@b.com </);
    expect(senderFor("", "facturas@facturavoz.solvexsoftware.dev")).toBe("FacturaVoz <facturas@facturavoz.solvexsoftware.dev>");
    expect(senderFor("Lupe", undefined)).toBe('"Lupe vía FacturaVoz" <onboarding@resend.dev>');
  });
});
