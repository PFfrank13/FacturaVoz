import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { sendResend } from "@/lib/collections";
import { buildDayCloseEmail, type DaySummary } from "@/lib/dayclose";
import { UUID } from "@/lib/publicbase";
import { userEmail } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

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

  const { data: summary, error } = await auth.supabase.rpc("day_summary", { p_org: orgId, p_day: day });
  if (error || !summary) return json({ error: "Sin acceso a esa empresa" }, 403);
  const s = summary as DaySummary;
  const expectedCents = Math.round(Number(s.expected_cash ?? 0) * 100);
  const countedCents = Math.round(counted * 100);
  if (!Number.isFinite(expectedCents)) return json({ error: "Saldo esperado inválido" }, 500);
  if (Math.abs(expectedCents - countedCents) > 1 && !note?.trim()) {
    return json({ error: "Existe una diferencia de caja. Escribe el motivo antes de cerrar.", code: "CLOSE_NOTE_REQUIRED" }, 422);
  }
  const { error: upErr } = await auth.supabase
    .from("day_closings")
    .insert({ org_id: orgId, day, summary: s, expected_cash: Number(s.expected_cash ?? 0), counted_cash: counted, note, closed_by: auth.userId });
  if (upErr) return json({
    error: upErr.code === "42501" ? "Tu rol o tu plan no permite cerrar caja"
      : upErr.code === "23505" ? "La caja de ese día ya está cerrada; no se sobrescribe un arqueo firmado"
      : "No se pudo guardar el cierre", code: upErr.code,
  }, upErr.code === "42501" ? 403 : upErr.code === "23505" ? 409 : 500);

  let emailed = false;
  if (process.env.RESEND_API_KEY && process.env.SUPABASE_SERVICE_ROLE_KEY) {
    const admin = createAdminClient();
    const [{ data: org }, { data: owner }, { data: st }] = await Promise.all([
      admin.from("organizations").select("name, trade_name").eq("id", orgId).maybeSingle(),
      admin.from("organization_members").select("user_id").eq("org_id", orgId).eq("role", "owner").limit(1).maybeSingle(),
      admin.from("org_settings").select("daily_report_to").eq("org_id", orgId).maybeSingle(),
    ]);
    const to = (st?.daily_report_to as string | null) || (owner ? await userEmail(owner.user_id as string) : null);
    const closer = (await userEmail(auth.userId)) ?? "un integrante del equipo";
    if (to) {
      const business = String(org?.trade_name || org?.name || "Tu negocio");
      const mail = buildDayCloseEmail({ business, summary: s, counted, closedBy: closer });
      emailed = await sendResend(to, mail.subject, mail.html, undefined, business);
    }
  }
  return json({ ok: true, summary: s, emailed });
}
