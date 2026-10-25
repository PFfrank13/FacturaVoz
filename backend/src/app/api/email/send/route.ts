import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { buildEmail, isEmail, looksLikePdf, MAX_PDF_BYTES, safeFilename } from "@/lib/email";

export const maxDuration = 30;
export const OPTIONS = preflight;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Envía el comprobante (PDF generado en el dispositivo) al correo del cliente con Resend. */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const key = process.env.RESEND_API_KEY;
  if (!key) return json({ error: "El envío por correo no está configurado en el servidor", code: "no_resend" }, 503);
  const { supabase } = auth;

  const body = await readJson(req, Math.ceil(MAX_PDF_BYTES * 1.4) + 2000);
  if (!body) return json({ error: "Solicitud no válida o archivo demasiado grande" }, 400);
  const invoiceId = typeof body.invoice_id === "string" && UUID.test(body.invoice_id) ? body.invoice_id : null;
  const to = typeof body.to === "string" ? body.to.trim() : "";
  const wantsCopy = body.copy_to_self !== false; // por defecto el dueño recibe copia
  const b64 = typeof body.pdf_b64 === "string" ? body.pdf_b64 : "";
  if (!invoiceId || !b64) return json({ error: "Solicitud no válida" }, 400);
  if (to && !isEmail(to)) return json({ error: "Revisa el correo del destinatario" }, 400);
  // Copia al correo con el que el usuario inició sesión (viene del token, no del cliente)
  const { data: me } = await supabase.auth.getUser();
  const owner = me.user?.email && isEmail(me.user.email) ? me.user.email : "";
  if (!to && !owner) return json({ error: "Tu cuenta no tiene correo para enviar la copia" }, 400);
  let pdf: Buffer;
  try {
    pdf = Buffer.from(b64, "base64");
  } catch {
    return json({ error: "PDF no válido" }, 400);
  }
  if (pdf.length > MAX_PDF_BYTES) return json({ error: "El PDF es demasiado grande" }, 413);
  if (!looksLikePdf(pdf)) return json({ error: "PDF no válido" }, 400);

  // El comprobante debe ser del usuario (RLS) — nadie puede usar el servicio como relé de spam con facturas ajenas
  const { data: inv } = await supabase
    .from("invoices")
    .select("number, org_id, clients(name), invoice_items(quantity, unit_price), tax_rate, currency")
    .eq("id", invoiceId)
    .maybeSingle();
  if (!inv) return json({ error: "Comprobante no encontrado" }, 404);
  const { data: prof } = await supabase.from("organizations").select("name").eq("id", inv.org_id).maybeSingle();

  // Cuota compartida con el dictado (misma función atómica)
  const { data: allowed, error: qErr } = await supabase.rpc("consume_api_quota", { p_per_minute: 5, p_per_day: 100 });
  if (qErr) return json({ error: "No se pudo comprobar la cuota", code: "quota_rpc" }, 500);
  if (allowed !== true) return json({ error: "Demasiados envíos, espera un momento" }, 429);

  const items = (inv.invoice_items ?? []) as { quantity: number; unit_price: number }[];
  const sub = items.reduce((s, i) => s + Math.round(Number(i.quantity) * Number(i.unit_price) * 100) / 100, 0);
  const tax = items.reduce((s, i) => s + Math.round(((Math.round(Number(i.quantity) * Number(i.unit_price) * 100) / 100) * Number(inv.tax_rate)) ) / 100, 0);
  const total = Math.round((sub + tax) * 100) / 100;
  const client = Array.isArray(inv.clients) ? inv.clients[0]?.name : (inv.clients as { name?: string } | null)?.name;
  const mail = buildEmail({
    business: String(prof?.name ?? ""),
    client: String(client ?? ""),
    number: String(inv.number),
    total: `${inv.currency} ${total.toFixed(2)}`,
  });

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(20_000),
      body: JSON.stringify({
        from: process.env.RESEND_FROM || "FacturaVoz <onboarding@resend.dev>",
        to: [to || owner],
        ...(to && wantsCopy && owner && owner.toLowerCase() !== to.toLowerCase() ? { bcc: [owner] } : {}),
        subject: mail.subject,
        html: mail.html,
        attachments: [{ filename: safeFilename(String(inv.number)), content: pdf.toString("base64") }],
      }),
    });
    if (!res.ok) {
      // Resend devuelve 403 si el dominio remitente no está verificado (modo prueba: solo a tu propio correo)
      const code = res.status === 403 || res.status === 422 ? "resend_domain" : `resend_${res.status}`;
      return json({ error: "No se pudo enviar el correo. Verifica el dominio remitente en Resend.", code }, 502);
    }
    return json({ ok: true });
  } catch {
    return json({ error: "No se pudo contactar el servicio de correo", code: "resend_net" }, 502);
  }
}
