import { NextResponse } from "next/server";
import { hasCronSecret } from "@/lib/cron";
import { createAdminClient } from "@/lib/supabase/admin";
import { heartbeat, hubConfig, isOrgId, syncAll } from "@/lib/solvex";

export const maxDuration = 60;

/**
 * Sincronización con Solvex Hub (Vercel Cron, 1 vez al día; el webhook cubre el tiempo real).
 *  - Sin Hub configurado → modo desarrollo: el control de licencias queda APAGADO (todo funciona, marcado "desarrollo").
 *  - Con Hub → enciende el control, trae el token de cada empresa (tolera webhooks perdidos), pide las pruebas
 *    gratis pendientes (empresas con RUC que aún usan la prueba local) y envía el "sigo vivo".
 */
export async function GET(req: Request) {
  if (!hasCronSecret(req)) return NextResponse.json({ error: "No autorizado (revisa CRON_SECRET)" }, { status: 401 });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return NextResponse.json({ error: "SUPABASE_SERVICE_ROLE_KEY no configurada" }, { status: 503 });
  const admin = createAdminClient();
  const cfg = hubConfig();
  if (!cfg) {
    // Nunca se desactiva el control de licencias por una configuración ausente.
    return NextResponse.json({ error: "Solvex Hub no configurado; activación obligatoria" }, { status: 503 });
  }

  const out = { applied: 0, stale: 0, unknown: 0, bad_tokens: 0, trials: 0, trials_used: 0, trial_errors: 0, error: "" };
  try {
    const { ok, bad } = await syncAll(cfg);
    out.bad_tokens = bad;
    for (const t of ok) {
      if (!isOrgId(t.tenant)) {
        out.unknown++;
        continue;
      }
      // Standalone development tenants must not be overwritten by external sync.
      const { data: license } = await admin.from("org_licenses").select("source").eq("org_id", t.tenant).maybeSingle();
      if (license?.source === "local") continue;
      const { data } = await admin.rpc("license_apply", { p_org: t.tenant, p_payload: t.payload, p_token: t.token });
      if (data === "ok") out.applied++;
      else if (data === "stale") out.stale++;
      else out.unknown++;
    }
  } catch (e) {
    out.error = e instanceof Error ? e.message.slice(0, 120) : "sync";
  }

  const { count } = await admin.from("organizations").select("id", { count: "exact", head: true });
  await heartbeat(cfg, count ?? 0);
  return NextResponse.json(out);
}
