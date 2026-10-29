import { describe, expect, it } from "vitest";
import { buildSystemPrompt } from "../src/lib/assistant";
import { RUBRO_COPILOT, isRubro, redactMoney, rubroPromptBlock } from "../src/lib/rubro-copilot";
import { cacheKey, DEFAULT_MODEL_ID, DEFAULT_VOICE_ID, speakable, synthesize, ttsConfig } from "../src/lib/tts";

describe("Copiloto por rubro (D)", () => {
  it("los 9 rubros tienen rol y vocabulario", () => {
    expect(Object.keys(RUBRO_COPILOT).length).toBe(9);
    expect(isRubro("otro")).toBe(false);
    expect(isRubro("taller")).toBe(true);
  });
  it("consultorio: nunca habla de diagnósticos (datos de salud)", () => {
    const b = rubroPromptBlock({ rubro: "consultorio", role: "owner", canMoney: true, plan: "PRO", features: null });
    expect(b).toMatch(/NUNCA hables de diagnósticos/);
    expect(b).toMatch(/paciente/);
  });
  it("rol sin dinero: se quitan los montos y se le dice que lo vea el dueño", () => {
    const snap = redactMoney({ today: "2026-10-29", sales_this_month: { total: 100 }, debtors: [{ client: "Ana" }], stock_alerts: [] });
    expect(snap.sales_this_month).toBeUndefined();
    expect(snap.debtors).toBeUndefined();
    expect(snap.stock_alerts).toEqual([]);
    expect(rubroPromptBlock({ rubro: "bodega", role: "cajero", canMoney: false, plan: "BASICO", features: null })).toMatch(/NO puede ver montos/);
  });
  it("plan: dice qué funciones no están y adónde ir", () => {
    const b = rubroPromptBlock({ rubro: "salon", role: "owner", canMoney: true, plan: "BASICO", features: { comisiones: false, agenda: true } });
    expect(b).toMatch(/NO incluidas en su plan: comisiones/);
  });
  it("sin datos o dato inexistente: la regla obliga a decir 'no lo tengo registrado'", () => {
    const p = buildSystemPrompt({}, "Mi Bodega", { block: rubroPromptBlock({ rubro: "bodega", role: "owner", canMoney: true, plan: "PRO", features: null }), rubroData: {} });
    expect(p).toMatch(/no lo tengo registrado/);
    expect(p).toMatch(/Nunca inventes cifras/);
    expect(p).not.toMatch(/<rubro_datos>\{/); // vacío: no se manda
  });
  it("los datos del rubro van como datos, no como instrucciones", () => {
    const p = buildSystemPrompt({ today: "2026-10-29" }, "Taller Juan", { block: "x", rubroData: { orders_open: { by_status: { listo: 2 } } } });
    expect(p).toMatch(/<rubro_datos>\{"orders_open"/);
  });
});

describe("Voz premium (ElevenLabs) solo en el servidor", () => {
  it("texto hablable: sin emojis y S/ en palabras", () => {
    expect(speakable("Vendiste S/ 1,250.50 hoy 🎉 **bien**")).toBe("Vendiste 1,250.50 soles hoy bien");
  });
  it("caché por texto+voz+modelo (misma frase = mismo archivo)", () => {
    expect(cacheKey("Hola", DEFAULT_VOICE_ID, DEFAULT_MODEL_ID)).toBe(cacheKey("Hola", DEFAULT_VOICE_ID, DEFAULT_MODEL_ID));
    expect(cacheKey("Hola", DEFAULT_VOICE_ID, DEFAULT_MODEL_ID)).not.toBe(cacheKey("Hola.", DEFAULT_VOICE_ID, DEFAULT_MODEL_ID));
  });
  it("sin clave: avisa qué variable falta y la app usa la voz del teléfono", () => {
    const prev = process.env.ELEVENLABS_API_KEY;
    delete process.env.ELEVENLABS_API_KEY;
    delete process.env.ELEVENLABS_VOICE_ID;
    const c = ttsConfig();
    expect(c.key).toBe("");
    expect(c.voice).toBe("erWYIIRQTXR88ZsA9w1X");
    expect(c.model).toBe("eleven_flash_v2_5");
    expect(c.missing[0]).toBe("ELEVENLABS_API_KEY");
    if (prev !== undefined) process.env.ELEVENLABS_API_KEY = prev;
  });
  it("la clave va en la cabecera xi-api-key, nunca en la URL", async () => {
    let seen = { url: "", key: "" };
    const fake = (async (url: string | URL | Request, init?: RequestInit) => {
      seen = { url: String(url), key: (init?.headers as Record<string, string>)["xi-api-key"] };
      return new Response(new Uint8Array(500), { status: 200 });
    }) as typeof fetch;
    const r = await synthesize("Hola", { key: "sk_prueba", voice: DEFAULT_VOICE_ID, model: DEFAULT_MODEL_ID }, fake);
    expect(r.ok).toBe(true);
    expect(seen.url).not.toContain("sk_prueba");
    expect(seen.url).toContain("/v1/text-to-speech/erWYIIRQTXR88ZsA9w1X");
    expect(seen.key).toBe("sk_prueba");
  });
  it("clave rechazada o sin créditos → motivo, sin romper", async () => {
    const f = (st: number) => (async () => new Response("{}", { status: st })) as unknown as typeof fetch;
    expect(await synthesize("x", { key: "k", voice: "v", model: "m" }, f(401))).toEqual({ ok: false, reason: "auth" });
    expect(await synthesize("x", { key: "k", voice: "v", model: "m" }, f(429))).toEqual({ ok: false, reason: "limit" });
  });
});
