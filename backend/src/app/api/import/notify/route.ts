import { timingSafeEqual } from "node:crypto";
import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { buildImportEmail, isEmail } from "@/lib/email";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 30;
export const OPTIONS = preflight;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function hasSecret(req: Request): boolean {
  const secret = process.env.CRON_SECRET;
  const m = /^Bearer (.+)$/.exec(req.headers.get("authorization") ?? "");
  if (!secret || secret.length < 16 || !m) return false;
  const a = Buffer.from(m[1]);
  const b = Buffer.from(secret);
  return a.length === b.length && timingSafeEqual(a, b);
}

type Job = { id: string; org_id: string; user_id: string; status: string; imported: number; skipped: number; error: string | null };

/** Envía el aviso de un trabajo terminado y lo marca como avisado (una sola vez). */
async function notifyJob(job: Job): Promise<"sent" | "skipped" | "error"> {
  const key = process.env.RESEND_API_KEY;
  if (!key) return "error";
  if (job.status !== "done" && job.status !== "failed") return "skipped";
  const admin = createAdminClient();
  // Reserva atómica: solo quien logra poner notified_at envía (evita correos dobles).
  const { data: claimed } = await admin
    .from("import_jobs")
    .update({ notified_at: new Date().toISOString() })
    .eq("id", job.id)
    .is("notified_at", null)
    .select("id")
    .maybeSingle();
  if (!claimed) return "skipped";
  const { data: u } = await admin.auth.admin.getUserById(job.user_id);
  const to = u.user?.email;
  const { data: org } = await admin.from("organizations").select("name").eq("id", job.org_id).maybeSingle();
  if (!to || !isEmail(to)) return "skipped";
  const mail = buildImportEmail({ business: String(org?.name ?? ""), status: job.status as "done" | "failed", imported: job.imported, skipped: job.skipped, error: job.error });
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(15_000),
      body: JSON.stringify({ from: process.env.RESEND_FROM || "FacturaVoz <onboarding@resend.dev>", to: [to], subject: mail.subject, html: mail.html }),
    });
    if (!res.ok) {
      await admin.from("import_jobs").update({ notified_at: null }).eq("id", job.id); // reintentable
      return "error";
    }
    return "sent";
  } catch {
    await admin.from("import_jobs").update({ notified_at: null }).eq("id", job.id);
    return "error";
  }
}

const COLS = "id, org_id, user_id, status, imported, skipped, error";

/**
 * Tres formas de llamarla:
 *  - App abierta (Bearer del usuario) con {job_id}.
 *  - Database Webhook de Supabase (Authorization: Bearer CRON_SECRET) con {record:{id}}: aviso inmediato aunque la app esté cerrada.
 *  - Cron diario de Vercel (GET) como red de seguridad.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const body = await readJson(req, 20_000);
  if (!body) return json({ error: "Solicitud no válida" }, 400);

  if (hasSecret(req)) {
    const rec = (body.record ?? {}) as Record<string, unknown>;
    const id = typeof rec.id === "string" && UUID.test(rec.id) ? rec.id : null;
    if (!id) return json({ error: "Solicitud no válida" }, 400);
    const { data: job } = await createAdminClient().from("import_jobs").select(COLS).eq("id", id).maybeSingle();
    if (!job) return json({ error: "No encontrado" }, 404);
    return json({ result: await notifyJob(job as Job) });
  }

  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const id = typeof body.job_id === "string" && UUID.test(body.job_id) ? body.job_id : null;
  if (!id) return json({ error: "Solicitud no válida" }, 400);
  const { data: job } = await auth.supabase.from("import_jobs").select(COLS).eq("id", id).maybeSingle(); // RLS
  if (!job || (job as Job).user_id !== auth.userId) return json({ error: "No encontrado" }, 404);
  return json({ result: await notifyJob(job as Job) });
}

export async function GET(req: Request) {
  const json = jsonWith(null);
  if (!hasSecret(req)) return json({ error: "No autorizado" }, 401);
  const admin = createAdminClient();
  const since = new Date(Date.now() - 3 * 86400_000).toISOString();
  const { data: jobs } = await admin
    .from("import_jobs")
    .select(COLS)
    .in("status", ["done", "failed"])
    .is("notified_at", null)
    .gte("finished_at", since)
    .limit(50);
  let sent = 0;
  for (const j of (jobs ?? []) as Job[]) if ((await notifyJob(j)) === "sent") sent++;
  return json({ checked: jobs?.length ?? 0, sent });
}
