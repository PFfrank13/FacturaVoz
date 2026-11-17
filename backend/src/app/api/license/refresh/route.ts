import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { hubConfig, isOrgId, syncAll } from "@/lib/solvex";

export const runtime = "nodejs";
export const maxDuration = 30;
export const OPTIONS = preflight;

/**
 * "Ya activé / comprobar licencia": trae AHORA desde Solvex Hub la licencia de esta empresa.
 * - Requiere sesión y ser miembro de la empresa (cualquier rol puede pedir la comprobación; no cambia el plan).
 * - Verifica firma Ed25519, emisor, audiencia (esta instancia) y que tenant_ref = organizations.id (syncAll).
 * - Aplica con license_sync_apply: nunca da acceso que el Hub no haya firmado.
 * - Límite: 8 comprobaciones por hora y empresa (license_activation_attempt).
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "Inicia sesión para comprobar la licencia." }, 401);
  const body = await readJson(req, 512);
  const orgId = body && isOrgId(body.org_id) ? body.org_id : null;
  if (!orgId) return json({ error: "Empresa no válida." }, 400);
  const { data: role, error: roleError } = await auth.supabase.rpc("my_org_role", { p_org: orgId });
  if (roleError || !role) return json({ error: "No perteneces a esta empresa." }, 403);

  const cfg = hubConfig();
  if (!cfg || !process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Solvex Hub aún no está conectado a FacturaVoz. Contacta a soporte." }, 503);
  const admin = createAdminClient();
  const { data: allowed, error: rateError } = await admin.rpc("license_activation_attempt", { p_org: orgId, p_user: auth.userId });
  if (rateError) return json({ error: "Servicio de licencias no disponible." }, 503);
  if (allowed !== true) return json({ error: "Demasiadas comprobaciones. Inténtalo en una hora." }, 429);

  try {
    const { ok } = await syncAll(cfg);
    const mine = ok.filter((t) => t.tenant === orgId && t.payload.tenant === orgId);
    if (!mine.length) {
      return json({ ok: false, found: false, error: "Solvex Hub no tiene una licencia asignada a esta empresa. Pide a Solvex que la asigne a tu ID de empresa." }, 404);
    }
    // Si hubiera varios tokens, el más reciente gana (license_apply descarta los más viejos).
    mine.sort((a, b) => (a.payload.iat ?? 0) - (b.payload.iat ?? 0));
    let result = "";
    for (const t of mine) {
      const { data, error } = await admin.rpc("license_sync_apply", { p_org: orgId, p_payload: t.payload, p_token: t.token });
      if (error) throw new Error("apply");
      result = String(data);
    }
    const last = mine[mine.length - 1].payload;
    return json({ ok: true, found: true, result, plan: last.plan, status: last.status, mode: last.mode, period_end: last.period_end ?? null });
  } catch {
    // Sin registrar tokens, códigos ni datos del cliente.
    return json({ error: "No pudimos consultar Solvex Hub. Inténtalo de nuevo." }, 502);
  }
}
