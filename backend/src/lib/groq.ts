/**
 * Cliente mínimo de Groq (plan gratuito). La clave vive SOLO en el servidor (GROQ_API_KEY).
 * Groq retira modelos con frecuencia: cada llamada prueba una lista y salta al siguiente si el actual
 * ya no existe (404) o no admite algún parámetro (400).
 */
export const GROQ = "https://api.groq.com/openai/v1";

const uniq = (list: (string | undefined)[]) => list.filter((m, i, a): m is string => !!m && a.indexOf(m) === i);

/** Modelos de texto (mismo orden que /api/parse). */
export const textModels = () =>
  uniq([process.env.LLM_MODEL, "openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"]);

/** Modelos con visión (lectura de fotos). Vigente según console.groq.com/docs/vision (oct. 2026): qwen/qwen3.8-27b. */
export const visionModels = () =>
  uniq([process.env.VISION_MODEL, "qwen/qwen3.8-27b", "meta-llama/llama-4-scout-17b-16e-instruct"]);

/** Algunos modelos (Qwen) anteponen su razonamiento en <think>…</think>: se descarta antes de leer el JSON. */
export function extractJson(content: string): Record<string, unknown> | null {
  const text = content.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  const tryParse = (t: string) => {
    try {
      const v = JSON.parse(t);
      return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
    } catch {
      return null;
    }
  };
  const direct = tryParse(text);
  if (direct) return direct;
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(text);
  if (fenced) {
    const v = tryParse(fenced[1].trim());
    if (v) return v;
  }
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  return start >= 0 && end > start ? tryParse(text.slice(start, end + 1)) : null;
}

export class GroqError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
  }
}

/** Tipo real del audio por firma binaria (no se confía en el Content-Type del cliente). */
export function sniffAudio(b: Uint8Array): { type: string; ext: string } | null {
  const ascii = (from: number, s: string) => [...s].every((c, i) => b[from + i] === c.charCodeAt(0));
  if (b.length < 12) return null;
  if (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) return { type: "audio/webm", ext: "webm" };
  if (ascii(4, "ftyp")) return { type: "audio/mp4", ext: "m4a" };
  if (ascii(0, "OggS")) return { type: "audio/ogg", ext: "ogg" };
  if (ascii(0, "RIFF") && ascii(8, "WAVE")) return { type: "audio/wav", ext: "wav" };
  if (ascii(0, "ID3") || (b[0] === 0xff && (b[1] & 0xe0) === 0xe0)) return { type: "audio/mpeg", ext: "mp3" };
  return null;
}

/** Tipo real de la imagen por firma binaria. */
export function sniffImage(b: Uint8Array): "image/jpeg" | "image/png" | "image/webp" | null {
  if (b.length < 12) return null;
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  const ascii = (from: number, s: string) => [...s].every((c, i) => b[from + i] === c.charCodeAt(0));
  if (ascii(0, "RIFF") && ascii(8, "WEBP")) return "image/webp";
  return null;
}

/** Quita caracteres de control y recorta. */
export const cleanText = (s: string, max: number) =>
  s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "").trim().slice(0, max);

export async function transcribe(key: string, bytes: Uint8Array, kind: { type: string; ext: string }): Promise<string> {
  const stt = new FormData();
  stt.append("file", new Blob([bytes as BlobPart], { type: kind.type }), `audio.${kind.ext}`);
  stt.append("model", "whisper-large-v3-turbo");
  stt.append("language", "es");
  stt.append("temperature", "0");
  stt.append("response_format", "json");
  const res = await fetch(`${GROQ}/audio/transcriptions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}` },
    body: stt,
    signal: AbortSignal.timeout(20_000),
  });
  if (!res.ok) throw new GroqError(res.status, `stt_${res.status}`);
  return cleanText(String(((await res.json()) as { text?: string }).text ?? ""), 5000);
}

type Msg = { role: "system" | "user"; content: string | unknown[] };

async function chat(key: string, models: string[], messages: Msg[], maxTokens: number, timeoutMs: number): Promise<Record<string, unknown>> {
  let res: Response | null = null;
  for (const model of models) {
    res = await fetch(`${GROQ}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(timeoutMs),
      body: JSON.stringify({
        model,
        temperature: 0,
        max_completion_tokens: maxTokens,
        ...(model.startsWith("openai/") ? { reasoning_effort: "low" } : {}),
        response_format: { type: "json_object" },
        messages,
      }),
    });
    if (res.status !== 404 && res.status !== 400) break;
    console.error("groq: model unavailable", model, res.status);
  }
  if (!res) throw new GroqError(502, "llm_none");
  if (!res.ok) throw new GroqError(res.status, `llm_${res.status}`);
  const body = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const parsed = extractJson(body.choices?.[0]?.message?.content ?? "{}");
  if (!parsed) throw new GroqError(502, "llm_json");
  return parsed;
}

export function chatJson(key: string, system: string, user: string, maxTokens = 1500) {
  return chat(key, textModels(), [{ role: "system", content: system }, { role: "user", content: user }], maxTokens, 25_000);
}

export function visionJson(key: string, system: string, prompt: string, dataUrl: string, maxTokens = 2000) {
  return chat(
    key,
    visionModels(),
    [
      { role: "system", content: system },
      { role: "user", content: [{ type: "text", text: prompt }, { type: "image_url", image_url: { url: dataUrl } }] },
    ],
    maxTokens,
    40_000,
  );
}

/** Convierte "1.234,50", "S/ 1,234.50" o 1234.5 en número; NaN si no se puede. */
export function toNum(v: unknown): number {
  if (typeof v === "number") return v;
  if (typeof v !== "string") return NaN;
  let s = v.replace(/[^\d.,-]/g, "");
  if (!s) return NaN;
  const lastComma = s.lastIndexOf(",");
  const lastDot = s.lastIndexOf(".");
  if (lastComma > lastDot) {
    // coma decimal ("1.234,50") salvo que parezca separador de miles ("1,234")
    s = /,\d{3}$/.test(s) && lastDot === -1 ? s.replace(/,/g, "") : s.replace(/\./g, "").replace(",", ".");
  } else {
    s = s.replace(/,/g, "");
  }
  return Number(s);
}

export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
