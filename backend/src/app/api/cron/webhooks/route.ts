import { NextResponse } from "next/server";
import { hasCronSecret } from "@/lib/cron";
import { createAdminClient } from "@/lib/supabase/admin";
import { nextAttempt, safeWebhookUrl, signWebhook } from "@/lib/webhooks";

export const maxDuration = 60;

type Row = { id: number; org_id: string; event: string; payload: unknown; attempts: number; org_webhooks: { url: string; secret: string; active: boolean } | null };

/**
 * Entrega la cola de webhooks (API pública). Lo llama Vercel Cron 1 vez al día como respaldo y, si se activó,
 * Supabase pg_cron + pg_net cada minuto (ver 20261112_servicios.sql).
 */
export async function GET(req: Request) {
  if (!hasCronSecret(req)) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return NextResponse.json({ error: "Servicio no disponible" }, { status: 503 });
  const admin = createAdminClient();
  const { data } = await admin
    .from("webhook_outbox")
    .select("id, org_id, event, payload, attempts, org_webhooks(url, secret, active)")
    .is("delivered_at", null)
    .lt("attempts", 12)
    .lte("next_at", new Date().toISOString())
    .order("id")
    .limit(100);
  let delivered = 0;
  let failed = 0;
  const started = Date.now();
  for (const r of (data ?? []) as unknown as Row[]) {
    if (Date.now() - started > 45_000) break;
    const hook = r.org_webhooks;
    if (!hook || !hook.active || !safeWebhookUrl(hook.url)) {
      await admin.from("webhook_outbox").update({ attempts: 12, last_error: "webhook inactivo o URL no permitida" }).eq("id", r.id);
      continue;
    }
    const body = JSON.stringify({ id: r.id, ...(r.payload as Record<string, unknown>) });
    const ts = Math.floor(Date.now() / 1000);
    let status = 0;
    let err: string | null = null;
    try {
      const res = await fetch(hook.url, {
        method: "POST",
        headers: { "Content-Type": "application/json", "FacturaVoz-Event": r.event, "FacturaVoz-Timestamp": String(ts), "FacturaVoz-Signature": signWebhook(hook.secret, ts, body) },
        body,
        redirect: "manual",
        signal: AbortSignal.timeout(10_000),
      });
      status = res.status;
    } catch (e) {
      err = e instanceof Error ? e.name : "error";
    }
    if (status >= 200 && status < 300) {
      delivered++;
      await admin.from("webhook_outbox").update({ delivered_at: new Date().toISOString(), attempts: r.attempts + 1, last_status: status, last_error: null }).eq("id", r.id);
    } else {
      failed++;
      await admin.from("webhook_outbox").update({ attempts: r.attempts + 1, next_at: nextAttempt(r.attempts), last_status: status || null, last_error: err ?? `HTTP ${status}` }).eq("id", r.id);
    }
  }
  return NextResponse.json({ pending: data?.length ?? 0, delivered, failed });
}
