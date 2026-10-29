import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { fetchDoc, kindOf, rucWarning, type DocResult } from "@/lib/doclookup";
import { UUID } from "@/lib/publicbase";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 15;
export const OPTIONS = preflight;

const FRESH_DAYS = { dni: 180, ruc: 15 } as const;
const PER_HOUR = 60;

/**
 * Consulta DNI (8 dígitos) / RUC (11 dígitos): nombre o razón social, dirección, estado y condición.
 * 1) Caché en la base (doc_lookups): DNI 180 días, RUC 15 días. La caché NO gasta cupo.
 * 2) Límites: por persona y por empresa al día (consume_lookup) + 60/hora por persona.
 * 3) Si el proveedor falla o no está configurado → ok:false con un motivo y la app deja escribir a mano.
 * Body: { number, org_id? }. Respuesta: { ok, data?, cached?, stale?, reason?, message?, usage? }.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = await readJson(req, 1_000);
  const number = typeof body?.number === "string" ? body.number.replace(/\D/g, "") : "";
  const orgId = typeof body?.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
  const kind = kindOf(number);
  if (!kind) {
    return json({
      ok: false,
      reason: "invalid",
      message: number.length === 11 ? "Ese RUC no es válido: el último dígito no cuadra. Revisa los números." : "Escribe un DNI (8 dígitos) o RUC (11).",
    });
  }
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ ok: false, reason: "not_configured", message: "Consulta automática no disponible: escribe los datos." });

  const admin = createAdminClient();
  const { data: cached } = await admin.from("doc_lookups").select("data, fetched_at").eq("doc_type", kind).eq("number", number).maybeSingle();
  const withWarning = (d: DocResult): DocResult => ({ ...d, warning: d.kind === "ruc" ? rucWarning(d.status ?? "", d.condition ?? "") : "" });
  if (cached && Date.now() - Date.parse(cached.fetched_at as string) < FRESH_DAYS[kind] * 864e5) {
    return json({ ok: true, cached: true, data: withWarning(cached.data as DocResult) });
  }

  // Límites (solo cuentan las consultas que salen al proveedor)
  let usage: unknown = null;
  if (orgId) {
    const { data: q, error } = await auth.supabase.rpc("consume_lookup", { p_org: orgId });
    if (!error && q && typeof q === "object") {
      usage = q;
      const r = q as { ok?: boolean; reason?: string };
      if (r.ok === false) {
        if (cached) return json({ ok: true, cached: true, stale: true, data: withWarning(cached.data as DocResult) });
        return json(
          {
            ok: false,
            reason: "limit",
            usage,
            message: r.reason === "user_limit" ? "Llegaste a tu límite de consultas de hoy. Escribe los datos a mano." : "Tu negocio llegó al límite de consultas de hoy de su plan. Escribe los datos a mano.",
          },
          429,
        );
      }
    }
  }
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await auth.supabase.from("api_usage").select("id", { count: "exact", head: true }).eq("kind", "lookup").gte("created_at", since);
  if ((count ?? 0) >= PER_HOUR) return json({ ok: false, reason: "limit", message: "Muchas consultas en una hora. Escribe los datos o espera un poco." }, 429);
  await auth.supabase.from("api_usage").insert({ user_id: auth.userId, kind: "lookup" });

  const r = await fetchDoc(kind, number);
  if (!r.ok) {
    if (cached) return json({ ok: true, cached: true, stale: true, data: withWarning(cached.data as DocResult) });
    const message = {
      not_configured: "La consulta automática no está configurada (falta DOC_API_TOKEN en el servidor). Escribe el nombre y la dirección.",
      not_found: kind === "dni" ? "No encontramos ese DNI. Escribe el nombre a mano." : "No encontramos ese RUC en SUNAT. Revisa el número.",
      limit: "El servicio de consulta alcanzó su límite. Escribe los datos a mano.",
      error: "El servicio de consulta no respondió. Escribe los datos a mano.",
      auth: "El servicio de consulta rechazó la clave del servidor. Avísale al administrador. Mientras tanto, escribe los datos a mano.",
    }[r.reason];
    return json({ ok: false, reason: r.reason, message, usage });
  }
  await admin.from("doc_lookups").upsert({ doc_type: kind, number, data: r.data, fetched_at: new Date().toISOString() });
  return json({ ok: true, cached: false, data: r.data, usage });
}
