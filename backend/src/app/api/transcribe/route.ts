import { authenticateBearer, jsonWith, preflight } from "@/lib/api-auth";
import { GroqError, sniffAudio, transcribe } from "@/lib/groq";
import { isOrgId } from "@/lib/solvex";
import { licenseAllows } from "@/lib/license-check";

export const maxDuration = 30;
export const OPTIONS = preflight;
const MAX = 2_000_000;

/** Voz → texto (buscador universal por voz). multipart: "audio". */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const key = process.env.GROQ_API_KEY;
  if (!key) return json({ error: "Servicio de voz no configurado", code: "no_key" }, 503);
  if (Number(req.headers.get("content-length") ?? "0") > MAX + 50_000) return json({ error: "Audio demasiado largo" }, 413);
  let bytes: Uint8Array | null = null;
  let orgId: string | null = null;
  try {
    const form = await req.formData();
    const f = form.get("audio");
    if (f instanceof File && f.size > 0 && f.size <= MAX) bytes = new Uint8Array(await f.arrayBuffer());
    const rawOrg = form.get("org_id");
    orgId = isOrgId(rawOrg) ? rawOrg : null;
  } catch {
    return json({ error: "Solicitud no válida" }, 400);
  }
  const kind = bytes ? sniffAudio(bytes) : null;
  if (!bytes || !kind) return json({ error: "Audio no válido" }, 400);
  if (!await licenseAllows(auth.supabase, orgId, "voz")) {
    return json({ error: "Activa una licencia con acceso a voz.", code: "license" }, 402);
  }
  const { data: allowed } = await auth.supabase.rpc("consume_api_quota", { p_per_minute: 10, p_per_day: 200 });
  if (allowed !== true) return json({ error: "Demasiadas búsquedas por voz seguidas. Espera un minuto." }, 429);
  try {
    const text = await transcribe(key, bytes, kind);
    return json({ text });
  } catch (e) {
    return json({ error: "No se pudo entender el audio", code: e instanceof GroqError ? e.code : "stt" }, 502);
  }
}
