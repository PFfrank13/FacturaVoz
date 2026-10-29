import { NextResponse } from "next/server";
import { sendResend } from "@/lib/collections";
import { hasCronSecret } from "@/lib/cron";
import { buildDayCloseEmail, type DaySummary } from "@/lib/dayclose";
import { limaToday, userEmail } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 60;

/**
 * Tarea diaria (Vercel Cron, ~23:30 hora de Lima):
 *  1) Reporte del día por correo al dueño de las empresas que lo activaron y no cerraron caja manualmente.
 *  2) Limpieza: papelera > 30 días, eventos del Hub, caché de DNI/RUC, cola de webhooks entregada.
 */
export async function GET(req: Request) {
  if (!hasCronSecret(req)) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return NextResponse.json({ error: "Servicio no disponible" }, { status: 503 });
  const admin = createAdminClient();
  const day = limaToday();
  let reports = 0;
  if (process.env.RESEND_API_KEY) {
    const { data: orgs } = await admin.from("org_settings").select("org_id, daily_report_to").eq("daily_report", true).limit(200);
    for (const o of (orgs ?? []) as { org_id: string; daily_report_to: string | null }[]) {
      const { data: closed } = await admin.from("day_closings").select("id").eq("org_id", o.org_id).eq("day", day).maybeSingle();
      if (closed) continue;
      const { data: mode } = await admin.rpc("org_mode_service", { p_org: o.org_id });
      if (mode !== "full" && mode !== "warning") continue;
      const { data: owner } = await admin.from("organization_members").select("user_id").eq("org_id", o.org_id).eq("role", "owner").limit(1).maybeSingle();
      const to = o.daily_report_to || (owner ? await userEmail(owner.user_id as string) : null);
      if (!to) continue;
      const summary = await serviceDaySummary(admin, o.org_id, day);
      const { data: org } = await admin.from("organizations").select("name, trade_name").eq("id", o.org_id).maybeSingle();
      const business = String(org?.trade_name || org?.name || "Tu negocio");
      const mail = buildDayCloseEmail({ business, summary, counted: null, closedBy: "FacturaVoz (automático)" });
      if (await sendResend(to, mail.subject, mail.html, undefined, business)) reports++;
    }
  }
  const { data: cleanup } = await admin.rpc("maintenance_cleanup");
  return NextResponse.json({ day, reports, cleanup });
}

/** Resumen del día calculado con la clave del servidor (mismas reglas que day_summary). */
async function serviceDaySummary(admin: ReturnType<typeof createAdminClient>, orgId: string, day: string): Promise<DaySummary> {
  const { data: org } = await admin.from("organizations").select("currency").eq("id", orgId).maybeSingle();
  const currency = (org?.currency as string | null) ?? "PEN";
  const next = new Date(Date.parse(`${day}T00:00:00Z`) + 864e5).toISOString().slice(0, 10);
  const [{ data: sales }, { data: pays }, { data: moves }, { data: exp }] = await Promise.all([
    admin.rpc("sales_summary", { p_org: orgId, p_from: day, p_to: next, p_currency: currency }),
    admin.from("payments").select("amount, method").eq("org_id", orgId).eq("paid_on", day),
    admin.from("cash_movements").select("kind, amount, method").eq("org_id", orgId).eq("day", day),
    admin.from("expenses").select("total").eq("org_id", orgId).eq("spent_on", day).eq("currency", currency),
  ]);
  const byMethod: Record<string, number> = {};
  for (const p of (pays ?? []) as { amount: number | string; method: string }[]) byMethod[p.method] = Math.round(((byMethod[p.method] ?? 0) + Number(p.amount)) * 100) / 100;
  const sum = (k: string) => ((moves ?? []) as { kind: string; amount: number | string; method: string }[]).filter((m) => m.kind === k && m.method === "efectivo").reduce((a, m) => a + Number(m.amount), 0);
  const opening = ((moves ?? []) as { kind: string; amount: number | string }[]).filter((m) => m.kind === "apertura").reduce((a, m) => a + Number(m.amount), 0);
  const cashSales = byMethod.efectivo ?? 0;
  return {
    day,
    currency,
    sales: (sales ?? {}) as DaySummary["sales"],
    payments_by_method: byMethod,
    cash_opening: opening,
    cash_sales: cashSales,
    cash_in: sum("ingreso"),
    cash_out: sum("egreso"),
    expected_cash: Math.round((opening + cashSales + sum("ingreso") - sum("egreso")) * 100) / 100,
    expenses: ((exp ?? []) as { total: number | string }[]).reduce((a, e) => a + Number(e.total), 0),
  };
}
