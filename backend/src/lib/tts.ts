import { createHash } from "node:crypto";

/**
 * Voz premium (ElevenLabs) — SOLO en el servidor.
 *   ELEVENLABS_API_KEY   obligatoria (Sensitive). Nunca va a la app, a registros ni al repositorio.
 *   ELEVENLABS_VOICE_ID  voz (por defecto erWYIIRQTXR88ZsA9w1X, no es secreta)
 *   ELEVENLABS_MODEL_ID  por defecto eleven_flash_v2_5: buen español y la mitad de créditos que multilingual.
 * Ahorro: (1) caché por hash de texto+voz+modelo (la misma frase nunca se paga dos veces, aunque la pidan mil empresas),
 *         (2) solo se sintetiza cuando el usuario lo pide, (3) textos cortos, (4) cuota diaria por empresa y tope global.
 */
export const DEFAULT_VOICE_ID = "erWYIIRQTXR88ZsA9w1X";
export const DEFAULT_MODEL_ID = "eleven_flash_v2_5";
export const MAX_TTS_CHARS = 900;

export function ttsConfig() {
  const key = (process.env.ELEVENLABS_API_KEY ?? "").trim();
  const voice = (process.env.ELEVENLABS_VOICE_ID ?? "").trim() || DEFAULT_VOICE_ID;
  const model = (process.env.ELEVENLABS_MODEL_ID ?? "").trim() || DEFAULT_MODEL_ID;
  const missing = [!key ? "ELEVENLABS_API_KEY" : null, !(process.env.ELEVENLABS_VOICE_ID ?? "").trim() ? "ELEVENLABS_VOICE_ID (se usa la voz por defecto)" : null].filter(Boolean) as string[];
  const globalCap = Math.max(0, Math.floor(Number(process.env.TTS_GLOBAL_DAILY_CHARS ?? "600")) || 0);
  return { key, voice, model, missing, globalCap };
}

/** Texto limpio para hablar: sin emojis ni símbolos raros, "S/" → "soles", espacios normales. */
export function speakable(raw: string): string {
  return raw
    .normalize("NFC")
    .replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/gu, "")
    .replace(/S\/\s?([\d.,]+)/g, "$1 soles")
    .replace(/US\$\s?([\d.,]+)/g, "$1 dólares")
    .replace(/[*_#`~<>|[\]{}]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_TTS_CHARS);
}

export const cacheKey = (text: string, voice: string, model: string) => createHash("sha256").update(`${model}|${voice}|${text}`).digest("hex");

/** Llama a ElevenLabs (Create speech). Devuelve MP3 o un motivo de fallo (nunca el detalle con la clave). */
export async function synthesize(text: string, cfg: { key: string; voice: string; model: string }, fetchImpl: typeof fetch = fetch): Promise<{ ok: true; audio: Uint8Array<ArrayBuffer> } | { ok: false; reason: "auth" | "limit" | "error" }> {
  let res: Response;
  try {
    res = await fetchImpl(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(cfg.voice)}?output_format=mp3_22050_32`, {
      method: "POST",
      headers: { "xi-api-key": cfg.key, "Content-Type": "application/json", Accept: "audio/mpeg" },
      body: JSON.stringify({ text, model_id: cfg.model, language_code: "es", voice_settings: { stability: 0.5, similarity_boost: 0.75 } }),
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    return { ok: false, reason: "error" };
  }
  if (res.status === 401 || res.status === 403) return { ok: false, reason: "auth" };
  if (res.status === 429 || res.status === 402) return { ok: false, reason: "limit" };
  if (!res.ok) return { ok: false, reason: "error" };
  const buf = new Uint8Array(await res.arrayBuffer());
  return buf.length > 100 ? { ok: true, audio: buf } : { ok: false, reason: "error" };
}
