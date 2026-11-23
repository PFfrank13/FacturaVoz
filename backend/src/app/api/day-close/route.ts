import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { closeDay } from "@/lib/dayclose-core";
import { UUID } from "@/lib/publicbase";

export const maxDuration = 20;
export const OPTIONS = preflight;

/**
 * Cierre del día en un toque: guarda el cierre (con el efectivo contado) y envía el reporte por correo al dueño.
 * El resumen lo calcula la base de datos con los permisos de quien cierra (day_summary).
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = await readJson(req, 2_000);
  const orgId = typeof body?.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
  const day = typeof body?.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.day) ? body.day : null;
  const counted = typeof body?.counted === "number" && Number.isFinite(body.counted) && body.counted >= 0 && body.counted < 1e8 ? Math.round(body.counted * 100) / 100 : null;
  const note = typeof body?.note === "string" ? body.note.slice(0, 300) : null;
  if (!orgId || !day || counted === null) return json({ error: "Indica el efectivo contado para el cierre ciego" }, 400);

  const r = await closeDay(auth.supabase, auth.userId, orgId, day, counted, note);
  return json(r.body, r.status);
}
