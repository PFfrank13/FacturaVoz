import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendNote, statusCdr, type SunatOutcome } from "@/lib/fiscal/lycet";
import { buildNotePayload, cleanReasonText, noteSeriesFor, type NoteReason } from "@/lib/fiscal/note";

export const maxDuration = 60;
export const OPTIONS = preflight;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Anula (total) un comprobante ACEPTADO con una nota de crédito electrónica.
 * Idempotente: reintentar reutiliza el mismo número.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);
  const { supabase, userId } = auth;

  const body = await readJson(req, 10_000);
  if (!body) return json({ error: "Solicitud no válida" }, 400);
  const invoiceId = typeof body.invoice_id === "string" && UUID.test(body.invoice_id) ? body.invoice_id : null;
  const reason: NoteReason | null = body.reason_code === "01" ? "01" : body.reason_code === "06" ? "06" : null;
  if (!invoiceId || !reason) return json({ error: "Faltan datos de la nota de crédito" }, 400);

  // Lectura con RLS del usuario: solo ve sus propios comprobantes
  const { data: doc } = await supabase
    .from("fiscal_documents")
    .select("doc_type, series, correlative, status, env, payload")
    .eq("invoice_id", invoiceId)
    .maybeSingle();
  if (!doc) return json({ error: "Este comprobante no se emitió a SUNAT" }, 404);
  if (doc.status !== "accepted") return json({ error: "Solo se puede anular un comprobante aceptado por SUNAT" }, 409);
  const { data: company } = await supabase.from("fiscal_companies").select("ruc, env").maybeSingle();
  if (!company) return json({ error: "Configura primero la facturación electrónica en Ajustes" }, 412);

  let built;
  try {
    built = buildNotePayload(doc.payload as Record<string, unknown>, reason, cleanReasonText(reason, body.reason_text));
  } catch {
    return json({ error: "No se pudo preparar la nota de crédito" }, 422);
  }

  const admin = createAdminClient();
  const { data: reserved, error: resErr } = await admin.rpc("fiscal_reserve_note", {
    p_user: userId,
    p_invoice: invoiceId,
    p_series: noteSeriesFor(doc.series as string),
    p_reason_code: reason,
    p_reason_text: built.payload.desMotivo as string,
    p_payload: built.payload,
    p_totals: built.totals,
    p_env: doc.env,
  });
  const row = Array.isArray(reserved) ? reserved[0] : null;
  if (resErr || !row) return json({ error: "No se pudo reservar el número de la nota de crédito" }, 500);

  const base = { series: row.out_series as string, correlative: row.out_correlative as number };
  if (row.out_status === "accepted") return json({ status: "accepted", ...base, message: "Nota de crédito ya aceptada por SUNAT" });

  let outcome: SunatOutcome = await sendNote(row.out_payload);
  if (outcome.status === "error" && outcome.code === "1033") {
    const rec = await statusCdr(company.ruc as string, "07", base.series, String(base.correlative));
    if (rec) outcome = rec;
  }

  const { error: recErr } = await admin.rpc("fiscal_record_note", {
    p_user: userId,
    p_invoice: invoiceId,
    p_status: outcome.status,
    p_code: outcome.code,
    p_message: outcome.message,
    p_hash: outcome.hash ?? null,
    p_xml: outcome.xml ?? null,
    p_cdr: outcome.cdr ?? null,
    p_error: outcome.status === "error" ? outcome.message : null,
  });
  if (recErr) console.error("fiscal_record_note failed");

  return json({ status: outcome.status, ...base, code: outcome.code, message: outcome.message, hash: outcome.hash ?? null });
}
