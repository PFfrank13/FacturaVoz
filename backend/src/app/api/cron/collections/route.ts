import { NextResponse } from "next/server";
import { buildReminderEmail, sendResend } from "@/lib/collections";
import { hasCronSecret } from "@/lib/cron";
import { publicBase } from "@/lib/publicbase";
import { limaToday, userEmail } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 60;

type Candidate = {
  org_id: string;
  invoice_id: string;
  number: string;
  client_name: string;
  client_email: string;
  currency: string;
  due_date: string;
  total: number;
  balance: number;
  days_overdue: number;
  stage: number;
  business_name: string;
  pay_token: string | null;
};

/**
 * Motor de cobranza silencioso (Vercel Cron, 1 vez al día): detecta facturas por vencer o vencidas de las
 * empresas que activaron la cobranza automática y envía el recordatorio con su enlace de pago. Cada etapa se
 * envía una sola vez (reminder_log). Límite por corrida para respetar el plan gratuito de Resend (100/día).
 */
export async function GET(req: Request) {
  if (!hasCronSecret(req)) return NextResponse.json({ error: "No autorizado" }, { status: 401 });
  if (!process.env.RESEND_API_KEY) return NextResponse.json({ error: "RESEND_API_KEY no configurada" }, { status: 503 });
  const admin = createAdminClient();
  const limit = Math.min(Number(process.env.COLLECTIONS_DAILY_LIMIT ?? "80") || 80, 500);
  const { data, error } = await admin.rpc("collections_candidates", { p_today: limaToday(), p_limit: limit });
  if (error) return NextResponse.json({ error: "rpc", code: error.code }, { status: 500 });

  const base = publicBase(req);
  const owners = new Map<string, string | null>();
  async function replyTo(orgId: string) {
    if (!owners.has(orgId)) {
      const { data: m } = await admin.from("organization_members").select("user_id").eq("org_id", orgId).eq("role", "owner").limit(1).maybeSingle();
      owners.set(orgId, m ? await userEmail(m.user_id as string) : null);
    }
    return owners.get(orgId) ?? undefined;
  }

  let sent = 0;
  let failed = 0;
  for (const c of (data ?? []) as Candidate[]) {
    let token = c.pay_token;
    if (!token) {
      const { data: t } = await admin.rpc("ensure_pay_link", { p_invoice: c.invoice_id });
      token = (t as string | null) ?? null;
    }
    const mail = buildReminderEmail({
      business: c.business_name,
      client: c.client_name,
      number: c.number,
      currency: c.currency,
      total: Number(c.total),
      balance: Number(c.balance),
      dueDate: c.due_date,
      stage: c.stage,
      payUrl: token && base ? `${base}/pagar/${token}` : "",
    });
    const ok = await sendResend(c.client_email, mail.subject, mail.html, await replyTo(c.org_id));
    if (ok) {
      sent++;
      await admin.from("reminder_log").insert({ org_id: c.org_id, invoice_id: c.invoice_id, stage: c.stage, channel: "email", sent_to: c.client_email });
    } else {
      failed++;
    }
  }
  return NextResponse.json({ checked: data?.length ?? 0, sent, failed });
}
