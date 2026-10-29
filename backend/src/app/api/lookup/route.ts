import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { fetchDoc, kindOf, type DocResult } from "@/lib/doclookup";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 15;
export const OPTIONS = preflight;

const FRESH_DAYS = { dni: 180, ruc: 15 } as const;
const PER_HOUR = 60;

/**
 * Consulta DNI (8 dígitos) / RUC (11 dígitos): nombre o razón social, dirección y estado.
 * Caché en la base (doc_lookups) + límite por usuario (60/hora). Si el proveedor no está configurado o falla,
 * responde ok:false con un motivo y la app deja escribir los datos a mano (nunca bloquea la venta).
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = await readJson(req, 1_000);
  const number = typeof body?.number === "string" ? body.number.replace(/\D/g, "") : "";
  const kind = kindOf(number);
  if (!kind) return json({ ok: false, reason: "invalid", message: number.length === 11 ? "Ese RUC no es válido (revisa los dígitos)." : "Escribe un DNI (8 dígitos) o RUC (11)." });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ ok: false, reason: "not_configured", message: "Consulta automática no disponible: escribe los datos." });

  const admin = createAdminClient();
  const { data: cached } = await admin.from("doc_lookups").select("data, fetched_at").eq("doc_type", kind).eq("number", number).maybeSingle();
  if (cached && Date.now() - Date.parse(cached.fetched_at as string) < FRESH_DAYS[kind] * 864e5) {
    return json({ ok: true, cached: true, data: cached.data as DocResult });
  }

  // Límite justo por usuario (solo cuenta las consultas que salen al proveedor)
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await auth.supabase.from("api_usage").select("id", { count: "exact", head: true }).eq("kind", "lookup").gte("created_at", since);
  if ((count ?? 0) >= PER_HOUR) return json({ ok: false, reason: "limit", message: "Muchas consultas en una hora. Escribe los datos o espera un poco." }, 429);
  await auth.supabase.from("api_usage").insert({ user_id: auth.userId, kind: "lookup" });

  const r = await fetchDoc(kind, number);
  if (!r.ok) {
    if (cached) return json({ ok: true, cached: true, stale: true, data: cached.data as DocResult });
    const message = {
      not_configured: "La consulta automática no está configurada. Escribe el nombre y la dirección.",
      not_found: kind === "dni" ? "No encontramos ese DNI. Escribe el nombre a mano." : "No encontramos ese RUC en SUNAT. Revisa el número.",
      limit: "El servicio de consulta alcanzó su límite por hoy. Escribe los datos a mano.",
      error: "El servicio de consulta no respondió. Escribe los datos a mano.",
    }[r.reason];
    return json({ ok: false, reason: r.reason, message });
  }
  await admin.from("doc_lookups").upsert({ doc_type: kind, number, data: r.data, fetched_at: new Date().toISOString() });
  return json({ ok: true, cached: false, data: r.data });
}
