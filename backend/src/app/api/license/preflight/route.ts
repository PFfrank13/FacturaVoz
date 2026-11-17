import { authenticateBearer } from "@/lib/api-auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient as createServerClient } from "@/lib/supabase/server";
import { hubConfig, isOrgId, LicenseError, syncAll } from "@/lib/solvex";
import { evaluatePreflight } from "@/lib/license-preflight";
import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

const json = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });

/**
 * PREFLIGHT de licencia (solo lectura). GET /api/license/preflight?org={id}
 * Consulta Solvex Hub con la clave de la instancia, verifica cada token (firma Ed25519, emisor, audiencia, tenant) y
 * dice si la reconciliación ACTIVARÍA la empresa, sin escribir NADA (ni en Supabase ni en el Hub).
 * Acceso: propietario o administrador de esa empresa, con sesión de la app (Bearer) o de la web (cookie).
 * Respuesta sin secretos: solo plan, estado, fechas y los 4 últimos caracteres del código.
 */
export async function GET(req: Request) {
  const orgId = new URL(req.url).searchParams.get("org");
  if (!isOrgId(orgId)) return json({ error: "Empresa no válida." }, 400);

  let role: unknown = null;
  const bearer = await authenticateBearer(req);
  if (bearer) {
    role = (await bearer.supabase.rpc("my_org_role", { p_org: orgId })).data;
  } else {
    const web = await createServerClient();
    const { data: { user } } = await web.auth.getUser();
    if (!user) return json({ error: "Inicia sesión (app o web) como propietario o administrador." }, 401);
    role = (await web.rpc("my_org_role", { p_org: orgId })).data;
  }
  if (role !== "owner" && role !== "admin") return json({ error: "Solo el propietario o administrador puede ver el preflight." }, 403);

  const cfg = hubConfig();
  if (!cfg) return json({ verdict: "NO-GO", reasons: ["Las variables SOLVEX_* de este entorno faltan o no tienen el formato esperado."], config: { hub: false } }, 503);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ verdict: "NO-GO", reasons: ["Falta SUPABASE_SERVICE_ROLE_KEY en este entorno."] }, 503);

  const admin = createAdminClient();
  const { data: st, error: stErr } = await admin.rpc("license_preflight_state", { p_org: orgId });
  if (stErr || !st) return json({ verdict: "NO-GO", reasons: ["Falta aplicar la FASE A (20261209_v34a) en esta base."], read_only: true }, 503);
  const state = st as { source: string | null; license_code: string | null; pending_code: string | null; activated_code: string | null };

  const config = {
    hub: true,
    hub_https: cfg.url.startsWith("https://"),
    instance_id_formato_ok: /^ins_[a-z0-9]{20}$/.test(cfg.instanceId),
    api_key_formato_ok: true, // hubConfig() ya validó el formato slxk_…
    webhook_secret_configurado: cfg.webhookSecret.length > 0,
    llaves_publicas_fijadas: cfg.keys.length,
  };
  try {
    const t0 = Date.now();
    const { ok, bad } = await syncAll(cfg);
    const result = evaluatePreflight(orgId, ok, bad, state);
    return json({ ...result, config, hub_ms: Date.now() - t0, read_only: true });
  } catch (e) {
    const msg = e instanceof LicenseError ? e.message : "No se pudo contactar a Solvex Hub";
    return json({ verdict: "NO-GO", reasons: [`Solvex Hub: ${msg}`], config, read_only: true }, 502);
  }
}
