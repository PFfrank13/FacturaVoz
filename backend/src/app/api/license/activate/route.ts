import { timingSafeEqual } from "node:crypto";
import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { hubConfig, isOrgId, syncAll } from "@/lib/solvex";

export const runtime = "nodejs";
export const maxDuration = 30;
export const OPTIONS = preflight;

/**
 * Activación de una licencia existente en Solvex Hub.
 * El propietario entrega el código `lic` de la licencia que Solvex ya asignó
 * a tenant_ref = organizations.id. Jamás confiamos en un plan enviado por Flutter:
 * consultamos el Hub, verificamos la firma Ed25519, la audiencia y el tenant.
 *
 * Este endpoint NO crea licencias en el Hub ni transfiere entre organizaciones.
 * Si tu panel Hub quiere emitir claves NUEVAS sin tenant_ref previo, deberá
 * implementar un endpoint oficial de canje antes de automatizar ese flujo.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "Inicia sesión para activar la licencia." }, 401);
  const body = await readJson(req, 1024);
  const orgId = body && isOrgId(body.org_id) ? body.org_id : null;
  const key = typeof body?.license_key === "string" ? body.license_key.trim() : "";
  if (!orgId || !/^[A-Za-z0-9_-]{6,128}$/.test(key)) {
    return json({ error: "Introduce un código de licencia válido." }, 400);
  }
  const { data: role, error: roleError } = await auth.supabase.rpc("my_org_role", { p_org: orgId });
  if (roleError || (role !== "owner" && role !== "admin")) {
    return json({ error: "Solo el propietario o administrador puede activar esta empresa." }, 403);
  }

  const cfg = hubConfig();
  if (!cfg || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return json({ error: "Solvex Hub aún no está conectado a FacturaVoz. Contacta a soporte." }, 503);
  }
  const admin = createAdminClient();
  // PostgreSQL serializa y limita a ocho intentos por hora/empresa.
  const { data: allowed, error: rateError } = await admin.rpc("license_activation_attempt", {
    p_org: orgId, p_user: auth.userId,
  });
  if (rateError) return json({ error: "Aplica la última migración de licencias antes de activar." }, 503);
  if (allowed !== true) return json({ error: "Demasiados intentos. Inténtalo en una hora." }, 429);

  try {
    const licenses = await syncAll(cfg); // Hub firma y asigna el token a una instancia + tenant
    const match = licenses.ok.find((candidate) => {
      if (candidate.tenant !== orgId || candidate.payload.tenant !== orgId) return false;
      // La audiencia firmada es la instancia del producto, no confiamos en un product_id editable.
      const lic = candidate.payload.lic;
      if (!lic) return false;
      const a = Buffer.from(lic), b = Buffer.from(key);
      return a.length === b.length && timingSafeEqual(a, b);
    });
    if (!match) return json({ error: "Licencia no encontrada para esta empresa. Revisa el código y el ID de empresa en Solvex Hub." }, 403);
    if (match.payload.mode !== "full" && match.payload.mode !== "warning") {
      return json({ error: "La licencia existe pero no está activa. Consulta su estado en Solvex Hub." }, 409);
    }
    const { data, error } = await admin.rpc("license_activate_authorized", {
      p_org: orgId, p_user: auth.userId, p_payload: match.payload, p_token: match.token,
    });
    if (error || data !== "ok") throw new Error("license_apply");
    return json({ ok: true, plan: match.payload.plan, mode: match.payload.mode });
  } catch {
    // No registrar el código, JWT, nombre, RUC ni secretos en los logs.
    return json({ error: "No pudimos verificar la licencia en Solvex Hub. Inténtalo de nuevo." }, 502);
  }
}
