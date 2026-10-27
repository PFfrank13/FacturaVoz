import { NextResponse } from "next/server";
import { readJson } from "@/lib/api-auth";
import { escapeHtml } from "@/lib/email";
import { sendResend } from "@/lib/collections";
import { fmtMoney, isToken } from "@/lib/publicbase";
import { getPublicInvoice, sameOrigin, userEmail } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 20;

const json = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });
const METHODS = ["yape", "plin", "transferencia", "otro"];

/** "Ya pagué": el cliente reporta su pago; el negocio lo confirma con un toque en la app. */
export async function POST(req: Request) {
  if (!sameOrigin(req)) return json({ error: "Origen no permitido" }, 403);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);
  const body = await readJson(req, 4_000);
  if (!body || !isToken(body.token)) return json({ error: "Solicitud no válida" }, 400);
  const amount = Math.round(Number(String(body.amount ?? "").replace(",", ".")) * 100) / 100;
  const method = typeof body.method === "string" && METHODS.includes(body.method) ? body.method : null;
  const op = typeof body.operation_code === "string" ? body.operation_code.replace(/[^\w-]/g, "").slice(0, 40) : "";
  const payer = typeof body.payer_name === "string" ? body.payer_name.replace(/\s+/g, " ").trim().slice(0, 120) : "";
  if (!method) return json({ error: "Elige cómo pagaste" }, 400);
  if (!Number.isFinite(amount) || amount <= 0) return json({ error: "Escribe el monto que pagaste" }, 400);

  const inv = await getPublicInvoice(body.token);
  if (!inv) return json({ error: "Comprobante no encontrado" }, 404);
  if (!inv.payable) return json({ error: "Este comprobante ya no tiene saldo pendiente" }, 409);
  if (amount > inv.balance + 0.01) return json({ error: `El monto supera el saldo (${fmtMoney(inv.balance, inv.currency)})` }, 400);
  if (inv.pendingClaims >= 5) return json({ error: "Ya hay pagos reportados esperando confirmación. El negocio los revisará pronto." }, 429);

  const { error } = await createAdminClient().from("payment_claims").insert({
    org_id: inv.orgId,
    invoice_id: inv.invoiceId,
    amount,
    method,
    operation_code: op || null,
    payer_name: payer || null,
  });
  if (error) return json({ error: "No se pudo registrar. Inténtalo de nuevo." }, 500);

  const to = await userEmail(inv.createdBy);
  if (to) {
    const subject = `Pago reportado: ${fmtMoney(amount, inv.currency)} · ${inv.number}`;
    const html = `<!doctype html><html lang="es"><body style="font-family:Arial,Helvetica,sans-serif;color:#26254b;background:#f8f6fd;padding:24px">
<div style="max-width:520px;margin:auto;background:#fff;border-radius:20px;padding:24px">
<h2 style="margin:0 0 12px">💸 ${escapeHtml(inv.client || "Tu cliente")} reportó un pago</h2>
<p style="font-size:15px;line-height:1.5;color:#55577a"><b>${escapeHtml(fmtMoney(amount, inv.currency))}</b> por <b>${escapeHtml(method)}</b>${op ? ` (operación ${escapeHtml(op)})` : ""} para ${escapeHtml(inv.number)}.</p>
<p style="font-size:15px;line-height:1.5;color:#55577a">Verifícalo en tu app de Yape/Plin o en tu banco y confírmalo en FacturaVoz → Cobranza con un toque.</p>
</div></body></html>`;
    await sendResend(to, subject, html);
  }
  return json({ ok: true });
}
