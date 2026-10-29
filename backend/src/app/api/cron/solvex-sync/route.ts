import { NextResponse } from "next/server";
import { hasCronSecret } from "@/lib/cron";
import { createAdminClient } from "@/lib/supabase/admin";
import { heartbeat, hubConfig, isOrgId, requestTrial, syncAll } from "@/lib/solvex";

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
    await admin.rpc("license_set_enforced", { p_on: false });
    return NextResponse.json({ mode: "desarrollo", message: "Solvex Hub no configurado: licencias simuladas (todo habilitado)." });
  }
  await admin.rpc("license_set_enforced", { p_on: true });

  const out = { applied: 0, stale: 0, unknown: 0, bad_tokens: 0, trials: 0, trials_used: 0, trial_errors: 0, error: "" };
  try {
    const { ok, bad } = await syncAll(cfg);
    out.bad_tokens = bad;
    for (const t of ok) {
      if (!isOrgId(t.tenant)) {
        out.unknown++;
        continue;
      }
      const { data } = await admin.rpc("license_apply", { p_org: t.tenant, p_payload: t.payload, p_token: t.token });
      if (data === "ok") out.applied++;
      else if (data === "stale") out.stale++;
      else out.unknown++;
    }
  } catch (e) {
    out.error = e instanceof Error ? e.message.slice(0, 120) : "sync";
  }

  const { data: pending } = await admin.rpc("license_pending_trials", { p_limit: 25 });
  for (const p of (pending ?? []) as { org_id: string; ruc: string; name: string; owner_email: string | null }[]) {
    try {
      const r = await requestTrial(cfg, { tenant: p.org_id, ruc: p.ruc, businessName: p.name, email: p.owner_email });
      if (r.status === "ok") {
        await admin.rpc("license_apply", { p_org: p.org_id, p_payload: r.data.payload, p_token: r.data.token });
        await admin.rpc("license_mark", { p_org: p.org_id, p_trial_requested: true, p_error: null });
        out.trials++;
      } else if (r.status === "used") {
        await admin.rpc("license_mark", { p_org: p.org_id, p_trial_requested: true, p_error: "Este RUC ya usó su prueba gratis" });
        out.trials_used++;
      } else {
        await admin.rpc("license_mark", { p_org: p.org_id, p_trial_requested: false, p_error: r.message });
        out.trial_errors++;
      }
    } catch {
      out.trial_errors++;
    }
  }
  const { count } = await admin.from("organizations").select("id", { count: "exact", head: true });
  await heartbeat(cfg, count ?? 0);
  return NextResponse.json(out);
}
