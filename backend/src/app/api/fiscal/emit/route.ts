import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { createAdminClient } from "@/lib/supabase/admin";
import { validateClientDoc } from "@/lib/fiscal/ids";
import { buildInvoicePayload, validateFiscalInput } from "@/lib/fiscal/payload";
import { sendInvoice, statusCdr, type SunatOutcome } from "@/lib/fiscal/lycet";
import type { Afectacion } from "@/lib/fiscal/calc";

export const maxDuration = 60;
export const OPTIONS = preflight;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type ItemRow = { description: string; quantity: number | string; unit_price: number | string; position: number };

/**
 * Emite (o reintenta) el comprobante electrónico de una factura guardada.
 * Idempotente: un reintento reutiliza el mismo número y el mismo contenido.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Servicio no disponible" }, 503);
  const { supabase, userId } = auth;

  const body = await readJson(req, 20_000);
  if (!body) return json({ error: "Solicitud no válida" }, 400);
  const invoiceId = typeof body.invoice_id === "string" && UUID.test(body.invoice_id) ? body.invoice_id : null;
  const docType = body.doc_type === "01" ? "01" : body.doc_type === "03" ? "03" : null;
  const afectacion = (["gravado", "exonerado", "inafecto"] as const).find((a) => a === body.afectacion) as Afectacion | undefined;
  const unit = body.unit === "ZZ" ? "ZZ" : "NIU";
  if (!invoiceId || !docType || !afectacion) return json({ error: "Faltan datos del comprobante" }, 400);

  const doc = validateClientDoc(String(body.client_doc_type ?? ""), String(body.client_doc_number ?? ""));
  if (!doc.ok) return json({ error: doc.error }, 400);
  const clientAddress = typeof body.client_address === "string" ? body.client_address.trim().slice(0, 200) : "";

  // La factura (RLS: solo si eres miembro de su empresa) define la empresa emisora
  const { data: inv } = await supabase
    .from("invoices")
    .select("id, org_id, status, currency, tax_rate, due_date, client_id, clients(id, name), invoice_items(description, quantity, unit_price, position)")
    .eq("id", invoiceId)
    .order("position", { referencedTable: "invoice_items", ascending: true })
    .maybeSingle();
  if (!inv) return json({ error: "Factura no encontrada" }, 404);
  const orgId = inv.org_id as string;

  // Empresa habilitada (el RUC sale de la tabla del servidor, NO de datos editables)
  const { data: company } = await supabase.from("fiscal_companies").select("ruc, env").eq("org_id", orgId).maybeSingle();
  if (!company) return json({ error: "Configura primero la facturación electrónica de esta empresa en Ajustes" }, 412);

  const { data: profile } = await supabase
    .from("organizations")
    .select("name, trade_name, address, ubigeo, department, province, district, series_factura, series_boleta")
    .eq("id", orgId)
    .maybeSingle();
  if (!profile) return json({ error: "Completa los datos del negocio" }, 412);
  if (inv.currency !== "PEN" && inv.currency !== "USD") return json({ error: "SUNAT solo admite soles (PEN) o dólares (USD)" }, 422);

  const client = (Array.isArray(inv.clients) ? inv.clients[0] : inv.clients) as { id: string; name: string } | null;
  const clientName = (typeof body.client_name === "string" && body.client_name.trim()) || client?.name || "";

  // Exonerado/inafecto: el impuesto debe ser 0. Mientras sea borrador se ajusta por elección explícita del usuario.
  let taxRate = Number(inv.tax_rate);
  if (afectacion !== "gravado" && taxRate !== 0 && inv.status === "draft") {
    const { error } = await supabase.from("invoices").update({ tax_rate: 0 }).eq("id", invoiceId);
    if (error) return json({ error: "No se pudo ajustar el impuesto" }, 500);
    taxRate = 0;
  }

  const input = {
    docType,
    currency: inv.currency as "PEN" | "USD",
    afectacion,
    taxRate,
    dueDate: (inv.due_date as string | null) ?? null,
    unit,
    issuer: {
      ruc: company.ruc as string,
      razonSocial: profile.name ?? "",
      nombreComercial: profile.trade_name,
      ubigeo: profile.ubigeo ?? "",
      departamento: profile.department ?? "",
      provincia: profile.province ?? "",
      distrito: profile.district ?? "",
      direccion: profile.address ?? "",
    },
    client: { tipoDoc: doc.tipoDoc, numDoc: doc.numDoc, name: clientName, address: clientAddress || null },
    lines: ((inv.invoice_items ?? []) as ItemRow[]).map((i) => ({
      description: i.description,
      quantity: Number(i.quantity),
      unit_price: Number(i.unit_price),
    })),
  } as const;
  const problem = validateFiscalInput(input);
  if (problem) return json({ error: problem }, 422);

  // Recuerda el documento del cliente para la próxima vez (con RLS del usuario)
  if (client) {
    await supabase
      .from("clients")
      .update({ tax_id: doc.numDoc === "-" ? null : doc.numDoc, doc_type: body.client_doc_type })
      .eq("id", client.id);
  }

  const { payload, totals, legend } = buildInvoicePayload(input);
  const series = docType === "01" ? profile.series_factura : profile.series_boleta;

  const admin = createAdminClient();
  const { data: reserved, error: resErr } = await admin.rpc("fiscal_reserve", {
    p_org: orgId,
    p_user: userId,
    p_invoice: invoiceId,
    p_doc_type: docType,
    p_series: series,
    p_payload: payload,
    p_totals: totals,
    p_legend: legend,
    p_afectacion: afectacion,
    p_env: company.env,
  });
  const row = Array.isArray(reserved) ? reserved[0] : null;
  if (resErr || !row) return json({ error: "No se pudo reservar el número del comprobante" }, 500);

  const base = { series: row.out_series as string, correlative: row.out_correlative as number };
  if (row.out_status === "accepted") return json({ status: "accepted", ...base, message: "Comprobante ya aceptado por SUNAT" });

  // Envío a SUNAT con el contenido EXACTO reservado
  let outcome: SunatOutcome = await sendInvoice(row.out_payload);
  if (outcome.status === "error" && outcome.code === "1033") {
    // SUNAT ya lo tenía registrado: recupera su CDR en vez de dejarlo pendiente
    const rec = await statusCdr(company.ruc as string, docType, base.series, String(base.correlative));
    if (rec) outcome = rec;
  }

  const { error: recErr } = await admin.rpc("fiscal_record", {
    p_org: orgId,
    p_invoice: invoiceId,
    p_status: outcome.status,
    p_code: outcome.code,
    p_message: outcome.message,
    p_hash: outcome.hash ?? null,
    p_xml: outcome.xml ?? null,
    p_cdr: outcome.cdr ?? null,
    p_error: outcome.status === "error" ? outcome.message : null,
  });
  if (recErr) console.error("fiscal_record failed");

  return json({
    status: outcome.status,
    ...base,
    code: outcome.code,
    message: outcome.message,
    hash: outcome.hash ?? null,
  });
}
