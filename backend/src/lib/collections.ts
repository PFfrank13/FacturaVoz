import { escapeHtml, senderFor } from "./email";
import { fmtDate, fmtMoney } from "./publicbase";

/** Cobranza automática: el tono sube poco a poco según los días respecto al vencimiento. */

export type Tone = "friendly" | "due" | "late" | "firm" | "final";

export function toneFor(stage: number): Tone {
  if (stage < 0) return "friendly";
  if (stage === 0) return "due";
  if (stage <= 7) return "late";
  if (stage <= 29) return "firm";
  return "final";
}

export function reminderLine(stage: number, dueIso: string): string {
  const due = fmtDate(dueIso);
  const n = Math.abs(stage);
  switch (toneFor(stage)) {
    case "friendly":
      return `Te recordamos con anticipación que vence ${n === 1 ? "mañana" : `en ${n} días`} (${due}).`;
    case "due":
      return `Hoy (${due}) es la fecha de vencimiento.`;
    case "late":
      return `Venció el ${due} (hace ${n} ${n === 1 ? "día" : "días"}). Seguramente fue un descuido: aquí tienes el enlace para pagar en un minuto.`;
    case "firm":
      return `Lleva ${n} días vencido (desde el ${due}). Te agradeceremos regularizarlo a la brevedad.`;
    case "final":
      return `Lleva ${n} días vencido (desde el ${due}). Por favor, comunícate con nosotros hoy para regularizarlo y evitar la suspensión del crédito.`;
  }
}

export function buildReminderEmail(o: {
  business: string;
  client: string;
  number: string;
  currency: string;
  total: number;
  balance: number;
  dueDate: string;
  stage: number;
  payUrl: string;
}) {
  const business = escapeHtml(o.business || "Tu proveedor");
  const client = escapeHtml(o.client || "cliente");
  const number = escapeHtml(o.number);
  const tone = toneFor(o.stage);
  const subject = (
    tone === "friendly" ? `Recordatorio: ${o.number} vence pronto` : tone === "due" ? `${o.number} vence hoy` : `Pago pendiente: ${o.number}`
  )
    .concat(` · ${o.business || "FacturaVoz"}`)
    .replace(/[\r\n]+/g, " ")
    .slice(0, 150);
  const button = o.payUrl
    ? `<a href="${escapeHtml(o.payUrl)}" style="display:inline-block;background:#6a62e2;color:#ffffff;text-decoration:none;font-weight:700;padding:14px 26px;border-radius:14px;font-size:16px">Pagar ahora</a>
<p style="margin:12px 0 0;font-size:12px;color:#8a8cab">Yape, Plin, transferencia o tarjeta, según lo que acepte ${business}.</p>`
    : "";
  const html = `<!doctype html><html lang="es"><body style="margin:0;background:#f8f6fd;font-family:Arial,Helvetica,sans-serif;color:#26254b">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:24px;overflow:hidden">
<tr><td style="background:linear-gradient(135deg,#6a62e2,#b58bf5);padding:26px 28px;color:#ffffff">
<div style="font-size:13px;opacity:.85">${business}</div>
<div style="font-size:22px;font-weight:700;margin-top:4px">Comprobante ${number}</div></td></tr>
<tr><td style="padding:26px 28px">
<p style="margin:0 0 12px;font-size:16px">Hola ${client},</p>
<p style="margin:0 0 18px;font-size:15px;line-height:1.55;color:#55577a">${escapeHtml(reminderLine(o.stage, o.dueDate))}</p>
<div style="background:#f3f1fc;border-radius:16px;padding:16px 18px;font-size:15px;margin-bottom:22px">
<div>Total <b style="float:right">${escapeHtml(fmtMoney(o.total, o.currency))}</b></div>
<div style="margin-top:8px">Saldo pendiente <b style="float:right;font-size:18px;color:#d94a5e">${escapeHtml(fmtMoney(o.balance, o.currency))}</b></div></div>
${button}
<p style="margin:22px 0 0;font-size:12px;color:#8a8cab">Si ya pagaste, ignora este mensaje y ¡gracias! Enviado con FacturaVoz.</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject, html };
}

export function buildQuoteAnswerEmail(o: { business: string; client: string; number: string; accepted: boolean; total: string; note: string }) {
  const subject = `${o.accepted ? "¡Cotización aceptada!" : "Cotización rechazada"} · ${o.number} · ${o.client}`.replace(/[\r\n]+/g, " ").slice(0, 150);
  const html = `<!doctype html><html lang="es"><body style="margin:0;background:#f8f6fd;font-family:Arial,Helvetica,sans-serif;color:#26254b">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:24px;overflow:hidden">
<tr><td style="background:${o.accepted ? "linear-gradient(135deg,#23956f,#4fd1a1)" : "linear-gradient(135deg,#d94a5e,#ff8a7a)"};padding:26px 28px;color:#ffffff;font-size:22px;font-weight:700">${escapeHtml(subject)}</td></tr>
<tr><td style="padding:26px 28px;font-size:15px;line-height:1.55;color:#55577a">
<b>${escapeHtml(o.client)}</b> ${o.accepted ? "aceptó" : "rechazó"} la cotización <b>${escapeHtml(o.number)}</b> por <b>${escapeHtml(o.total)}</b>.
${o.note ? `<p style="margin:14px 0 0;padding:12px 14px;background:#f3f1fc;border-radius:12px">“${escapeHtml(o.note)}”</p>` : ""}
${o.accepted ? `<p style="margin:16px 0 0">Abre FacturaVoz → Cotizaciones y toca <b>Convertir en factura</b>: no tendrás que volver a escribir nada.</p>` : ""}
<p style="margin:18px 0 0;font-size:12px;color:#8a8cab">Enviado con FacturaVoz a ${escapeHtml(o.business || "tu empresa")}.</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject, html };
}

/** Envía un correo con Resend. Devuelve true si se aceptó. */
export async function sendResend(to: string, subject: string, html: string, replyTo?: string, fromName?: string): Promise<boolean> {
  const key = process.env.RESEND_API_KEY;
  if (!key) return false;
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(15_000),
      body: JSON.stringify({
        from: senderFor(fromName),
        to: [to],
        ...(replyTo ? { reply_to: replyTo } : {}),
        subject,
        html,
      }),
    });
    return res.ok;
  } catch {
    return false;
  }
}
