import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { rucValid } from "@/lib/doclookup";
import { createAdminClient } from "@/lib/supabase/admin";
import { hubConfig, isOrgId, requestTrial } from "@/lib/solvex";

export const maxDuration = 25;
export const OPTIONS = preflight;

/**
 * El dueño activa su PRUEBA GRATIS de 3 días en Solvex Hub en cuanto registra el RUC de su empresa
 * (sin esperar al cron). Una sola prueba por RUC. Sin Hub configurado responde "desarrollo".
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = await readJson(req, 2_000);
  const orgId = body && isOrgId(body.org_id) ? body.org_id : null;
  if (!orgId) return json({ error: "Empresa no válida" }, 400);
  const { data: role } = await auth.supabase.rpc("my_org_role", { p_org: orgId });
  if (role !== "owner" && role !== "admin") return json({ error: "Solo el propietario o un administrador" }, 403);

  const cfg = hubConfig();
  if (!cfg) return json({ status: "desarrollo", message: "Licencias en modo desarrollo: todo habilitado." });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);
  const admin = createAdminClient();
  const { data: org } = await admin.from("organizations").select("name, trade_name, tax_id").eq("id", orgId).maybeSingle();
  const ruc = String(org?.tax_id ?? "").trim();
  if (!rucValid(ruc)) return json({ error: "Registra primero el RUC de tu empresa (11 dígitos) en Ajustes → Datos del negocio." }, 412);

  const r = await requestTrial(cfg, { tenant: orgId, ruc, businessName: String(org?.trade_name || org?.name || "Mi empresa") });
  if (r.status === "ok") {
    await admin.rpc("license_set_enforced", { p_on: true });
    await admin.rpc("license_apply", { p_org: orgId, p_payload: r.data.payload, p_token: r.data.token });
    await admin.rpc("license_mark", { p_org: orgId, p_trial_requested: true, p_error: null });
    return json({ status: "ok", plan: r.data.payload.plan, period_end: r.data.payload.period_end });
  }
  if (r.status === "used") {
    await admin.rpc("license_mark", { p_org: orgId, p_trial_requested: true, p_error: "Este RUC ya usó su prueba gratis" });
    return json({ status: "used", message: "Este RUC ya usó su prueba gratis. Elige un plan para continuar.", plans_url: process.env.SOLVEX_PLANS_URL ?? null }, 409);
  }
  await admin.rpc("license_mark", { p_org: orgId, p_trial_requested: false, p_error: r.message });
  return json({ status: "error", message: "No pudimos contactar al servidor de licencias. Seguirás con tu prueba local; lo intentaremos de nuevo." }, 502);
}
