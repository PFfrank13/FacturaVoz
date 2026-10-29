import { describe, expect, it } from "vitest";
import { DEFAULT_DNI_URL, fetchDoc, kindOf, maskUrl, normalizeDoc, providerUrl, rucValid, rucWarning } from "../src/lib/doclookup";

// J6: consultas DNI/RUC con APISPERU simulado (sin red, sin token real).
type Call = { url: string; headers: Record<string, string> };
function fake(status: number, body: unknown, calls: Call[] = []): typeof fetch {
  return (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), headers: (init?.headers ?? {}) as Record<string, string> });
    if (status === 0) throw new Error("ECONNREFUSED");
    return new Response(typeof body === "string" ? body : JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
  }) as typeof fetch;
}
const withToken = async <T>(token: string, fn: () => Promise<T>) => {
  const prev = process.env.DOC_API_TOKEN;
  process.env.DOC_API_TOKEN = token;
  delete process.env.DOC_API_DNI_URL;
  delete process.env.DOC_API_RUC_URL;
  try {
    return await fn();
  } finally {
    if (prev === undefined) delete process.env.DOC_API_TOKEN;
    else process.env.DOC_API_TOKEN = prev;
  }
};

describe("APISPERU: formato y token", () => {
  it("URL por defecto con el token en el parámetro token (no en cabecera)", () =>
    withToken("secreto-123", async () => {
      const calls: Call[] = [];
      const r = await fetchDoc("dni", "12345678", fake(200, { dni: "12345678", nombres: "Juan Carlos", apellidoPaterno: "Pérez", apellidoMaterno: "Rojas", codVerifica: 1 }, calls));
      expect(calls[0].url).toBe("https://dniruc.apisperu.com/api/v1/dni/12345678?token=secreto-123");
      expect(calls[0].headers.Authorization).toBeUndefined();
      expect(r.ok).toBe(true);
      if (r.ok) {
        expect(r.data.name).toBe("JUAN CARLOS PÉREZ ROJAS");
        expect(r.data.firstNames).toBe("JUAN CARLOS");
        expect(r.data.lastNames).toBe("PÉREZ ROJAS");
      }
    }));
  it("RUC activo y habido: razón social, nombre comercial, ubicación", () =>
    withToken("t", async () => {
      const r = await fetchDoc("ruc", "20100070970", fake(200, {
        ruc: "20100070970", razonSocial: "SUPERMERCADOS PERUANOS SOCIEDAD ANONIMA", nombreComercial: "-", estado: "ACTIVO", condicion: "HABIDO",
        direccion: "CAL. MORELLI NRO. 181", departamento: "LIMA", provincia: "LIMA", distrito: "SAN BORJA", ubigeo: "150130",
      }));
      expect(r.ok).toBe(true);
      if (r.ok) {
        expect(r.data.district).toBe("SAN BORJA");
        expect(r.data.ubigeo).toBe("150130");
        expect(r.data.tradeName).toBe("");
        expect(r.data.warning).toBe("");
      }
    }));
  it("RUC de baja o no habido: aviso antes de emitir", () => {
    expect(rucWarning("BAJA DE OFICIO", "HABIDO")).toMatch(/BAJA DE OFICIO/);
    expect(rucWarning("ACTIVO", "NO HABIDO")).toMatch(/NO HABIDO/);
    expect(rucWarning("ACTIVO", "HABIDO")).toBe("");
  });
  it("no encontrado (success:false)", () =>
    withToken("t", async () => {
      const r = await fetchDoc("dni", "87654321", fake(200, { success: false, message: "No se encontraron resultados." }));
      expect(r).toEqual({ ok: false, reason: "not_found" });
    }));
  it("límite del proveedor (429 o mensaje)", () =>
    withToken("t", async () => {
      expect(await fetchDoc("dni", "12345678", fake(429, {}))).toEqual({ ok: false, reason: "limit" });
      expect(await fetchDoc("dni", "12345678", fake(200, { success: false, message: "Límite de consultas excedido" }))).toEqual({ ok: false, reason: "limit" });
    }));
  it("proveedor caído o token rechazado", () =>
    withToken("t", async () => {
      expect(await fetchDoc("dni", "12345678", fake(0, {}))).toEqual({ ok: false, reason: "error" });
      expect(await fetchDoc("dni", "12345678", fake(500, {}))).toEqual({ ok: false, reason: "error" });
      expect(await fetchDoc("dni", "12345678", fake(401, {}))).toEqual({ ok: false, reason: "auth" });
    }));
  it("respuesta rara: HTML, lista vacía o de otro número → nunca datos inventados", () =>
    withToken("t", async () => {
      expect(await fetchDoc("dni", "12345678", fake(200, "<html>mantenimiento</html>"))).toEqual({ ok: false, reason: "error" });
      expect(await fetchDoc("dni", "12345678", fake(200, []))).toEqual({ ok: false, reason: "not_found" });
      expect(await fetchDoc("dni", "12345678", fake(200, { dni: "99999999", nombres: "OTRA", apellidoPaterno: "PERSONA" }))).toEqual({ ok: false, reason: "not_found" });
      expect(normalizeDoc("ruc", "20100070970", { ruc: "20100070970", razonSocial: "" })).toBeNull();
    }));
  it("sin token: no se llama al proveedor", () =>
    withToken("", async () => {
      const calls: Call[] = [];
      expect(await fetchDoc("dni", "12345678", fake(200, {}, calls))).toEqual({ ok: false, reason: "not_configured" });
      expect(calls.length).toBe(0);
    }));
  it("otro proveedor sin {token} en la plantilla: token en cabecera Bearer", () =>
    withToken("abc", async () => {
      process.env.DOC_API_DNI_URL = "https://api.ejemplo.pe/dni?numero={n}";
      const calls: Call[] = [];
      await fetchDoc("dni", "12345678", fake(200, { nombres: "A", apellidoPaterno: "B" }, calls));
      delete process.env.DOC_API_DNI_URL;
      expect(calls[0].url).toBe("https://api.ejemplo.pe/dni?numero=12345678");
      expect(calls[0].headers.Authorization).toBe("Bearer abc");
    }));
  it("el token nunca aparece en registros", () => {
    expect(maskUrl("https://dniruc.apisperu.com/api/v1/dni/12345678?token=eyJhbGciOi.secreto")).toBe("https://dniruc.apisperu.com/api/v1/dni/12345678?token=***");
    expect(DEFAULT_DNI_URL).toContain("{token}");
    expect(providerUrl("dni", "12345678", "")).toBeNull();
  });
  it("RUC inválido no se consulta (dígito verificador)", () => {
    expect(rucValid("20100070970")).toBe(true);
    expect(kindOf("20100070971")).toBeNull();
    expect(kindOf("12345678")).toBe("dni");
  });
});
