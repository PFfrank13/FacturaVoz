import { describe, expect, it } from "vitest";
import { buildEmail, escapeHtml, isEmail, looksLikePdf, safeFilename } from "../src/lib/email";

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
});
