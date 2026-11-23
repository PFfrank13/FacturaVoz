import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { sendResend } from "@/lib/collections";
import { buildDayCloseEmail, type DaySummary } from "@/lib/dayclose";
import { userEmail } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export type DayCloseReply = { ok?: boolean; summary?: DaySummary; emailed?: boolean; error?: string; code?: string };

/**
 * Cierre del día (arqueo ciego): guarda el cierre con el efectivo contado y envía el reporte al dueño.
 * El resumen lo calcula la base con los permisos de quien cierra (day_summary). Lo usan el móvil
 * (`/api/day-close`) y el ERP web, con el cliente del usuario (RLS).
 */
export async function closeDay(supabase: SupabaseClient, userId: string, orgId: string, day: string, counted: number, note: string | null): Promise<{ status: number; body: DayCloseReply }> {
  const reply = (b: DayCloseReply, status = 200) => ({ status, body: b });
  const { data: summary, error } = await supabase.rpc("day_summary", { p_org: orgId, p_day: day });
  if (error || !summary) return reply({ error: "Sin acceso a esa empresa" }, 403);
  const s = summary as DaySummary;
  const expectedCents = Math.round(Number(s.expected_cash ?? 0) * 100);
  const countedCents = Math.round(counted * 100);
  if (!Number.isFinite(expectedCents)) return reply({ error: "Saldo esperado inválido" }, 500);
  if (Math.abs(expectedCents - countedCents) > 1 && !note?.trim()) {
    return reply({ error: "Existe una diferencia de caja. Escribe el motivo antes de cerrar.", code: "CLOSE_NOTE_REQUIRED" }, 422);
  }
  const { error: upErr } = await supabase
    .from("day_closings")
    .insert({ org_id: orgId, day, summary: s, expected_cash: Number(s.expected_cash ?? 0), counted_cash: counted, note, closed_by: userId });
  if (upErr) return reply({
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
    const closer = (await userEmail(userId)) ?? "un integrante del equipo";
    if (to) {
      const business = String(org?.trade_name || org?.name || "Tu negocio");
      const mail = buildDayCloseEmail({ business, summary: s, counted, closedBy: closer });
      emailed = await sendResend(to, mail.subject, mail.html, undefined, business);
    }
  }
  return reply({ ok: true, summary: s, emailed });
}
