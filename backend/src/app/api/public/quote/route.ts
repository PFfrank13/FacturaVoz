import { NextResponse } from "next/server";
import { readJson } from "@/lib/api-auth";
import { buildQuoteAnswerEmail, sendResend } from "@/lib/collections";
import { fmtMoney, isToken } from "@/lib/publicbase";
import { getPublicQuote, sameOrigin, userEmail } from "@/lib/publicdata";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 20;

const json = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });

/** El cliente final acepta o rechaza una cotización desde /cotizacion/<token>. */
export async function POST(req: Request) {
  if (!sameOrigin(req)) return json({ error: "Origen no permitido" }, 403);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);
  const body = await readJson(req, 4_000);
  if (!body || !isToken(body.token)) return json({ error: "Solicitud no válida" }, 400);
  const action = body.action === "accept" ? "accept" : body.action === "reject" ? "reject" : null;
  const name = typeof body.name === "string" ? body.name.replace(/\s+/g, " ").trim().slice(0, 120) : "";
  const note = typeof body.note === "string" ? body.note.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 500) : "";
  if (!action) return json({ error: "Acción no válida" }, 400);
  if (action === "accept" && name.length < 3) return json({ error: "Escribe tu nombre para aceptar" }, 400);

  const q = await getPublicQuote(body.token);
  if (!q) return json({ error: "Cotización no encontrada" }, 404);
  if (q.status !== "draft" && q.status !== "sent") return json({ status: q.status, already: true });
  if (q.expired) return json({ error: "Esta cotización ya venció. Pide una actualizada." }, 409);

  const admin = createAdminClient();
  const { data: upd } = await admin
    .from("quotes")
    .update({
      status: action === "accept" ? "accepted" : "rejected",
      responded_at: new Date().toISOString(),
      responder_name: name || null,
      response_note: note || null,
    })
    .eq("id", q.id)
    .in("status", ["draft", "sent"])
    .select("status")
    .maybeSingle();
  if (!upd) return json({ status: q.status, already: true });

  // Aviso al vendedor (best-effort; además la app lo ve en vivo por Realtime).
  const to = await userEmail(q.userId);
  if (to) {
    const mail = buildQuoteAnswerEmail({
      business: q.business,
      client: name || q.client,
      number: q.number,
      accepted: action === "accept",
      total: fmtMoney(q.total, q.currency),
      note,
    });
    await sendResend(to, mail.subject, mail.html);
  }
  return json({ status: upd.status });
}
