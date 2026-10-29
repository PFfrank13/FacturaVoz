import type { SupabaseClient } from "@supabase/supabase-js";
import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { buildSystemPrompt, enrichSnapshot, sanitizeAssistant, type ClientActivity } from "@/lib/assistant";
import { chatJson, cleanText, GroqError, sniffAudio, transcribe } from "@/lib/groq";
import { limaToday } from "@/lib/publicdata";
import { UUID } from "@/lib/publicbase";
import { estimateTaxes, type Regime } from "@/lib/taxes";

export const maxDuration = 45;
export const OPTIONS = preflight;

const MAX_AUDIO = 4_000_000;

/**
 * Copiloto: audio (multipart "audio") o texto (JSON {"text"}) + org_id.
 * Responde {transcript, reply} donde reply.intent dice qué hacer en la app.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const key = process.env.GROQ_API_KEY;
  if (!key) return json({ error: "Servicio de IA no configurado en el servidor", code: "no_key" }, 503);
  const { supabase } = auth;

  let audio: Uint8Array | null = null;
  let text = "";
  let orgId: string | null = null;
  const ctype = req.headers.get("content-type") ?? "";
  if (ctype.startsWith("multipart/form-data")) {
    if (Number(req.headers.get("content-length") ?? "0") > MAX_AUDIO + 100_000) return json({ error: "Audio demasiado grande" }, 413);
    try {
      const form = await req.formData();
      const f = form.get("audio");
      if (f instanceof File && f.size > 0 && f.size <= MAX_AUDIO) audio = new Uint8Array(await f.arrayBuffer());
      const o = form.get("org_id");
      orgId = typeof o === "string" && UUID.test(o) ? o : null;
    } catch {
      return json({ error: "Solicitud no válida" }, 400);
    }
    if (!audio) return json({ error: "Audio no válido" }, 400);
  } else {
    const body = await readJson(req, 10_000);
    if (!body) return json({ error: "Solicitud no válida" }, 400);
    text = typeof body.text === "string" ? cleanText(body.text, 1000) : "";
    orgId = typeof body.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
    if (!text) return json({ error: "Escribe o dicta una pregunta" }, 400);
  }
  if (!orgId) return json({ error: "Elige una empresa" }, 400);

  const kind = audio ? sniffAudio(audio) : null;
  if (audio && !kind) return json({ error: "Formato de audio no válido" }, 400);

  // Membresía: el Copiloto es función del plan (en modo desarrollo o prueba, todo está habilitado)
  const { data: lic } = await supabase.rpc("my_license", { p_org: orgId });
  const features = ((lic as { features?: Record<string, unknown> } | null)?.features ?? null) as Record<string, unknown> | null;
  if (features && features.copiloto === false) return json({ error: "Tu plan no incluye el Copiloto. Mejora tu plan para usarlo.", code: "feature" }, 402);

  const { data: allowed, error: qErr } = await supabase.rpc("consume_api_quota", { p_per_minute: 5, p_per_day: 100 });
  if (qErr) return json({ error: "Falta ejecutar la migración de cuotas en Supabase", code: "quota_rpc" }, 500);
  if (allowed !== true) return json({ error: "Demasiadas consultas seguidas. Espera un minuto." }, 429);

  // Resumen del negocio (RLS: solo si el usuario es miembro de esa empresa)
  const { data: snapshot, error: snapErr } = await supabase.rpc("business_snapshot", { p_org: orgId });
  if (snapErr) {
    const missing = snapErr.code === "PGRST202" || snapErr.code === "42883";
    return json({ error: missing ? "Falta ejecutar la migración 20261101_negocio_pro.sql" : "Sin acceso a esa empresa", code: snapErr.code }, missing ? 500 : 403);
  }
  const { data: org } = await supabase.from("organizations").select("name, trade_name").eq("id", orgId).maybeSingle();
  // Meta y actividad de clientes (migración 20261102). Si aún no existen, el copiloto funciona sin ellos.
  const { data: goalRow } = await supabase.from("organizations").select("monthly_goal").eq("id", orgId).maybeSingle();
  const { data: activity } = await supabase.rpc("client_activity", { p_org: orgId });
  const enriched = enrichSnapshot(
    (snapshot ?? {}) as Record<string, unknown>,
    ((activity ?? []) as ClientActivity[]).slice(0, 500),
    goalRow?.monthly_goal == null ? null : Number(goalRow.monthly_goal),
  );
  Object.assign(enriched, { taxes: await taxContext(supabase, orgId) });

  try {
    if (audio && kind) {
      text = await transcribe(key, audio, kind);
      if (!text) return json({ error: "No se oyó nada. Habla más cerca del micrófono.", code: "empty" }, 422);
    }
    const raw = await chatJson(key, buildSystemPrompt(enriched, String(org?.trade_name || org?.name || "")), `<pedido>\n${text}\n</pedido>`, 1800);
    return json({ transcript: text, reply: sanitizeAssistant(raw) });
  } catch (e) {
    if (e instanceof GroqError && e.status === 429) return json({ error: "Servicio ocupado, inténtalo en un minuto", transcript: text }, 503);
    console.error("assistant: failed", e instanceof GroqError ? e.code : e instanceof Error ? e.name : "unknown");
    return json({ error: "No pude procesar tu pedido. Inténtalo de nuevo.", code: e instanceof GroqError ? e.code : "assistant", transcript: text }, 502);
  }
}

type Summary = { sales_base?: number; sales_tax?: number };

/** Impuestos del mes (estimado referencial) según el régimen del negocio. Solo cifras agregadas. */
async function taxContext(supabase: SupabaseClient, orgId: string) {
  try {
    const today = limaToday();
    const monthStart = `${today.slice(0, 7)}-01`;
    const d = new Date(`${monthStart}T00:00:00Z`);
    const next = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1)).toISOString().slice(0, 10);
    const { data: org } = await supabase.from("organizations").select("currency").eq("id", orgId).maybeSingle();
    const cur = (org?.currency as string | null) ?? "PEN";
    const [{ data: m }, { data: y }, { data: st }, { data: exp }] = await Promise.all([
      supabase.rpc("sales_summary", { p_org: orgId, p_from: monthStart, p_to: next, p_currency: cur }),
      supabase.rpc("sales_summary", { p_org: orgId, p_from: `${today.slice(0, 4)}-01-01`, p_to: next, p_currency: cur }),
      supabase.from("org_settings").select("tax_regime").eq("org_id", orgId).maybeSingle(),
      supabase.from("expenses").select("tax").eq("org_id", orgId).eq("currency", cur).gte("spent_on", monthStart).lt("spent_on", next).limit(5000),
    ]);
    const month = (m ?? {}) as Summary;
    const year = (y ?? {}) as Summary;
    const purchasesTax = ((exp ?? []) as { tax: number | string }[]).reduce((a, e) => a + Number(e.tax || 0), 0);
    const regime = ((st?.tax_regime as string | null) ?? null) as Regime | null;
    const est = estimateTaxes({
      regime,
      monthSalesBase: Number(month.sales_base ?? 0),
      monthSalesTax: Number(month.sales_tax ?? 0),
      monthPurchasesTax: purchasesTax,
      yearSalesBase: Number(year.sales_base ?? 0),
    });
    const lastDay = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
    const daysLeft = Math.max(1, lastDay - Number(today.slice(8, 10)) + 1);
    return {
      ...est,
      month_sales_base: Number(month.sales_base ?? 0),
      year_sales_base: Number(year.sales_base ?? 0),
      purchases_igv_credit: Math.round(purchasesTax * 100) / 100,
      save_per_day_until_month_end: Math.round((est.total / daysLeft) * 100) / 100,
      disclaimer: "Estimado referencial: confírmalo con tu contador.",
    };
  } catch {
    return null;
  }
}
