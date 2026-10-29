import { authenticateBearer, corsHeaders, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { UUID } from "@/lib/publicbase";
import { createAdminClient } from "@/lib/supabase/admin";
import { cacheKey, speakable, synthesize, ttsConfig } from "@/lib/tts";

export const maxDuration = 25;
export const OPTIONS = preflight;

const BUCKET = "tts-cache";

/**
 * Voz premium del Copiloto. Body: { text, org_id }. Responde audio/mpeg, o JSON con { code, fallback: "device" }
 * para que la app use la voz del teléfono (nunca se queda muda).
 * Caché global por hash (texto+voz+modelo): la caché NO gasta cuota.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = await readJson(req, 6_000);
  const orgId = typeof body?.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
  const text = speakable(typeof body?.text === "string" ? body.text : "");
  if (!orgId || !text) return json({ error: "Texto no válido", fallback: "device" }, 400);

  const cfg = ttsConfig();
  if (!cfg.key) {
    // Se avisa QUÉ variable falta (nunca su valor). La app usa la voz del teléfono.
    return json({ code: "tts_not_configured", missing: cfg.missing, fallback: "device", message: `Falta ${cfg.missing.join(" y ")} en Vercel: se usa la voz del teléfono.` }, 503);
  }
  const hash = cacheKey(text, cfg.voice, cfg.model);
  const path = `${cfg.model}/${hash}.mp3`;
  const audioHeaders = (hit: boolean) => ({
    ...corsHeaders(req.headers.get("origin")),
    "Content-Type": "audio/mpeg",
    "Cache-Control": "private, max-age=86400",
    "X-TTS-Cache": hit ? "hit" : "miss",
  });

  const admin = process.env.SUPABASE_SERVICE_ROLE_KEY ? createAdminClient() : null;
  if (admin) {
    const { data } = await admin.storage.from(BUCKET).download(path);
    if (data) return new Response(new Uint8Array(await data.arrayBuffer()), { headers: audioHeaders(true) });
  }

  // Solo lo que NO está en caché cuenta para la cuota (por empresa y tope global del servidor).
  const { data: q, error: qErr } = await auth.supabase.rpc("consume_tts", { p_org: orgId, p_chars: text.length, p_global_cap: cfg.globalCap });
  if (qErr) return json({ code: "tts_quota_rpc", fallback: "device", message: "Falta la migración 20261116 en Supabase." }, 500);
  const quota = q as { ok?: boolean; reason?: string; used?: number; limit?: number };
  if (!quota?.ok) {
    return json({ code: quota?.reason ?? "limit", fallback: "device", usage: { used: quota?.used, limit: quota?.limit }, message: "Se acabó la voz premium de hoy: sigo con la voz del teléfono." }, 429);
  }

  const r = await synthesize(text, cfg);
  if (!r.ok) {
    if (r.reason === "auth") console.error("tts: ElevenLabs rechazó la clave (revisa ELEVENLABS_API_KEY en Vercel)");
    return json({ code: `tts_${r.reason}`, fallback: "device", message: "La voz premium no respondió: uso la voz del teléfono." }, 502);
  }
  if (admin) {
    await admin.storage.from(BUCKET).upload(path, r.audio, { contentType: "audio/mpeg", upsert: true }).catch(() => null);
  }
  return new Response(r.audio, { headers: { ...audioHeaders(false), "X-TTS-Used": String(quota.used ?? ""), "X-TTS-Limit": String(quota.limit ?? "") } });
}
