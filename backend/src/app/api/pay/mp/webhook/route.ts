import { NextResponse } from "next/server";
import { unseal } from "@/lib/crypto";
import { MpError, mpGetPayment, paymentIdFrom } from "@/lib/mercadopago";
import { isToken } from "@/lib/publicbase";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 20;

/**
 * Notificación de Mercado Pago. No se confía en el cuerpo: se consulta el pago a Mercado Pago con el token
 * de la empresa dueña del enlace y solo se registra si está "approved" y su external_reference es este enlace.
 */
async function handle(req: Request) {
  const url = new URL(req.url);
  const token = url.searchParams.get("t");
  let body: Record<string, unknown> | null = null;
  if (req.method === "POST") {
    try {
      const t = await req.text();
      body = t && t.length < 20_000 ? (JSON.parse(t) as Record<string, unknown>) : null;
    } catch {
      body = null;
    }
  }
  const ok = () => NextResponse.json({ ok: true });
  if (!isToken(token)) return ok();
  const payId = paymentIdFrom(url, body);
  if (!payId) return ok();

  const admin = createAdminClient();
  const { data: link } = await admin.from("pay_links").select("org_id, invoice_id").eq("token", token).maybeSingle();
  if (!link) return ok();
  const { data: sec } = await admin.from("org_secrets").select("mp_token_enc").eq("org_id", link.org_id).maybeSingle();
  if (!sec?.mp_token_enc) return ok();
  const { data: inv } = await admin.from("invoices").select("currency").eq("id", link.invoice_id).maybeSingle();

  try {
    const p = await mpGetPayment(unseal(sec.mp_token_enc as string), payId);
    if (p.status !== "approved" || p.external_reference !== token || (inv && p.currency_id !== inv.currency)) return ok();
    const { data: result, error } = await admin.rpc("record_external_payment", {
      p_token: token,
      p_amount: Number(p.transaction_amount),
      p_method: "mercadopago",
      p_external_ref: `mp:${p.id}`,
      p_note: `Mercado Pago #${p.id}`,
    });
    if (error) {
      console.error("mp webhook: record failed", error.code);
      return NextResponse.json({ error: "retry" }, { status: 500 }); // Mercado Pago reintenta
    }
    return NextResponse.json({ ok: true, result });
  } catch (e) {
    console.error("mp webhook: failed", e instanceof MpError ? e.message : e instanceof Error ? e.name : "unknown");
    return NextResponse.json({ error: "retry" }, { status: 500 });
  }
}

export const POST = handle;
export const GET = handle;
