import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { buildSystemPrompt, sanitizeAssistant } from "@/lib/assistant";
import { chatJson, cleanText, GroqError, sniffAudio, transcribe } from "@/lib/groq";
import { UUID } from "@/lib/publicbase";

export const maxDuration = 45;
export const OPTIONS = preflight;

const MAX_AUDIO = 4_000_000;

/**
 * Copiloto: audio (multipart "audio") o texto (JSON {"text"}) + org_id.
 * Responde {transcript, reply} donde reply.intent dice qué hacer en la app.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const key = process.env.GROQ_API_KEY;
  if (!key) return json({ error: "Servicio de IA no configurado en el servidor", code: "no_key" }, 503);
  const { supabase } = auth;

  let audio: Uint8Array | null = null;
  let text = "";
  let orgId: string | null = null;
  const ctype = req.headers.get("content-type") ?? "";
  if (ctype.startsWith("multipart/form-data")) {
    if (Number(req.headers.get("content-length") ?? "0") > MAX_AUDIO + 100_000) return json({ error: "Audio demasiado grande" }, 413);
    try {
      const form = await req.formData();
      const f = form.get("audio");
      if (f instanceof File && f.size > 0 && f.size <= MAX_AUDIO) audio = new Uint8Array(await f.arrayBuffer());
      const o = form.get("org_id");
      orgId = typeof o === "string" && UUID.test(o) ? o : null;
    } catch {
      return json({ error: "Solicitud no válida" }, 400);
    }
    if (!audio) return json({ error: "Audio no válido" }, 400);
  } else {
    const body = await readJson(req, 10_000);
    if (!body) return json({ error: "Solicitud no válida" }, 400);
    text = typeof body.text === "string" ? cleanText(body.text, 1000) : "";
    orgId = typeof body.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
    if (!text) return json({ error: "Escribe o dicta una pregunta" }, 400);
  }
  if (!orgId) return json({ error: "Elige una empresa" }, 400);

  const kind = audio ? sniffAudio(audio) : null;
  if (audio && !kind) return json({ error: "Formato de audio no válido" }, 400);

  const { data: allowed, error: qErr } = await supabase.rpc("consume_api_quota", { p_per_minute: 5, p_per_day: 100 });
  if (qErr) return json({ error: "Falta ejecutar la migración de cuotas en Supabase", code: "quota_rpc" }, 500);
  if (allowed !== true) return json({ error: "Demasiadas consultas seguidas. Espera un minuto." }, 429);

  // Resumen del negocio (RLS: solo si el usuario es miembro de esa empresa)
  const { data: snapshot, error: snapErr } = await supabase.rpc("business_snapshot", { p_org: orgId });
  if (snapErr) {
    const missing = snapErr.code === "PGRST202" || snapErr.code === "42883";
    return json({ error: missing ? "Falta ejecutar la migración 20261101_negocio_pro.sql" : "Sin acceso a esa empresa", code: snapErr.code }, missing ? 500 : 403);
  }
  const { data: org } = await supabase.from("organizations").select("name, trade_name").eq("id", orgId).maybeSingle();

  try {
    if (audio && kind) {
      text = await transcribe(key, audio, kind);
      if (!text) return json({ error: "No se oyó nada. Habla más cerca del micrófono.", code: "empty" }, 422);
    }
    const raw = await chatJson(key, buildSystemPrompt(snapshot, String(org?.trade_name || org?.name || "")), `<pedido>\n${text}\n</pedido>`, 1800);
    return json({ transcript: text, reply: sanitizeAssistant(raw) });
  } catch (e) {
    if (e instanceof GroqError && e.status === 429) return json({ error: "Servicio ocupado, inténtalo en un minuto", transcript: text }, 503);
    console.error("assistant: failed", e instanceof GroqError ? e.code : e instanceof Error ? e.name : "unknown");
    return json({ error: "No pude procesar tu pedido. Inténtalo de nuevo.", code: e instanceof GroqError ? e.code : "assistant", transcript: text }, 502);
  }
}
