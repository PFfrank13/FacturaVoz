import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { lookupDocument } from "@/lib/lookup";
import { UUID } from "@/lib/publicbase";

export const maxDuration = 15;
export const OPTIONS = preflight;

/** Consulta DNI/RUC para el móvil. Body: { number, org_id? }. Reglas en `lookupDocument`. */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = await readJson(req, 1_000);
  const number = typeof body?.number === "string" ? body.number.replace(/\D/g, "") : "";
  const orgId = typeof body?.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
  const r = await lookupDocument(auth.supabase, auth.userId, number, orgId);
  return json(r.body, r.status);
}
