import type { SupabaseClient } from "@supabase/supabase-js";
import { authenticateBearer, corsHeaders, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { buildSystemPrompt, enrichSnapshot, sanitizeAssistant, type ClientActivity } from "@/lib/assistant";
import { chatJson, chatStream, cleanText, extractJson, GroqError, partialJsonString, sniffAudio, transcribe } from "@/lib/groq";
import { limaToday } from "@/lib/publicdata";
import { UUID } from "@/lib/publicbase";
import { estimateTaxes, type Regime } from "@/lib/taxes";
import { isRubro, redactMoney, rubroContext, rubroPromptBlock } from "@/lib/rubro-copilot";

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
  const wantsStream = (req.headers.get("accept") ?? "").includes("text/event-stream");

  // Permisos y cuota EN PARALELO (antes iban uno tras otro y sumaban medio segundo o más).
  const [{ data: lic }, quota] = await Promise.all([
    supabase.rpc("my_license", { p_org: orgId }),
    supabase.rpc("consume_api_quota", { p_per_minute: 8, p_per_day: 150 }),
  ]);
  // Membresía: el Copiloto es función del plan (en modo desarrollo o prueba, todo está habilitado)
  const features = ((lic as { features?: Record<string, unknown> } | null)?.features ?? null) as Record<string, unknown> | null;
  if (features && features.copiloto === false) return json({ error: "Tu plan no incluye el Copiloto. Mejora tu plan para usarlo.", code: "feature" }, 402);
  if (quota.error) return json({ error: "Falta ejecutar la migración de cuotas en Supabase", code: "quota_rpc" }, 500);
  if (quota.data !== true) return json({ error: "Demasiadas consultas seguidas. Espera un minuto." }, 429);

  // El contexto del negocio se arma MIENTRAS se transcribe el audio.
  const plan = String((lic as { plan?: string } | null)?.plan ?? "");
  const ctxPromise = gatherContext(supabase, orgId, plan, features);
  const sttPromise = audio && kind ? transcribe(key, audio, kind) : Promise.resolve(text);
  // Evita "unhandled rejection" si uno falla antes de que se lo espere.
  ctxPromise.catch(() => null);
  sttPromise.catch(() => null);

  if (!wantsStream) {
    try {
      const [ctx, heard] = await Promise.all([ctxPromise, sttPromise]);
      if (ctx.error) return json({ error: ctx.error, code: ctx.code }, ctx.status);
      text = heard;
      if (!text) return json({ error: "No se oyó nada. Habla más cerca del micrófono.", code: "empty" }, 422);
      const raw = await chatJson(key, buildSystemPrompt(ctx.snapshot ?? {}, ctx.name ?? "", ctx.extra), `<pedido>\n${text}\n</pedido>`, 1800);
      return json({ transcript: text, reply: sanitizeAssistant(raw) });
    } catch (e) {
      if (e instanceof GroqError && e.status === 429) return json({ error: "Servicio ocupado, inténtalo en un minuto", transcript: text }, 503);
      console.error("assistant: failed", e instanceof GroqError ? e.code : e instanceof Error ? e.name : "unknown");
      return json({ error: "No pude procesar tu pedido. Inténtalo de nuevo.", code: e instanceof GroqError ? e.code : "assistant", transcript: text }, 502);
    }
  }

  // ── Tiempo real (SSE): transcript → la respuesta palabra por palabra → respuesta final validada ──
  const enc = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (obj: Record<string, unknown>) => controller.enqueue(enc.encode(`data: ${JSON.stringify(obj)}\n\n`));
      try {
        send({ t: "status", text: audio ? "Escuchando lo que dijiste…" : "Pensando…" });
        const heard = await sttPromise;
        text = heard;
        if (!text) {
          send({ t: "error", error: "No se oyó nada. Habla más cerca del micrófono.", code: "empty" });
          return controller.close();
        }
        if (audio) send({ t: "transcript", text });
        const ctx = await ctxPromise;
        if (ctx.error) {
          send({ t: "error", error: ctx.error, code: ctx.code });
          return controller.close();
        }
        let shown = "";
        const full = await chatStream(key, buildSystemPrompt(ctx.snapshot ?? {}, ctx.name ?? "", ctx.extra), `<pedido>\n${text}\n</pedido>`, (buf) => {
          const p = partialJsonString(buf, "answer");
          if (!p) return;
          // Se manda solo lo nuevo; nunca un trozo de escape a medias (partialJsonString ya lo espera).
          if (p.text.length > shown.length && p.text.startsWith(shown)) {
            send({ t: "delta", text: p.text.slice(shown.length) });
            shown = p.text;
          }
        });
        const parsed = extractJson(full);
        if (!parsed) {
          send({ t: "error", error: "No pude armar la respuesta. Inténtalo de nuevo.", code: "llm_json" });
          return controller.close();
        }
        send({ t: "final", transcript: text, reply: sanitizeAssistant(parsed) });
        controller.close();
      } catch (e) {
        const busy = e instanceof GroqError && e.status === 429;
        console.error("assistant/stream: failed", e instanceof GroqError ? e.code : e instanceof Error ? e.name : "unknown");
        send({ t: "error", error: busy ? "Servicio ocupado, inténtalo en un minuto" : "No pude procesar tu pedido. Inténtalo de nuevo.", code: e instanceof GroqError ? e.code : "assistant", transcript: text });
        controller.close();
      }
    },
  });
  return new Response(stream, {
    headers: {
      ...corsHeaders(req.headers.get("origin")),
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-store, no-transform",
      "X-Accel-Buffering": "no",
      Connection: "keep-alive",
    },
  });
}

type Ctx =
  | { snapshot: Record<string, unknown>; name: string; extra: { block: string; rubroData: Record<string, unknown> }; error?: undefined }
  | { error: string; code?: string; status: number; snapshot?: undefined; name?: undefined; extra?: undefined };

/** Todo lo que el Copiloto necesita saber, en UNA ronda de consultas paralelas (RLS con el token del usuario). */
async function gatherContext(supabase: SupabaseClient, orgId: string, plan: string, features: Record<string, unknown> | null): Promise<Ctx> {
  // Rol y rubro primero (deciden qué datos se consultan); todo lo demás en paralelo.
  const [access, settings] = await Promise.all([
    supabase.rpc("my_access", { p_org: orgId }),
    supabase.from("org_settings").select("business_type").eq("org_id", orgId).maybeSingle(),
  ]);
  const acc = (access.data ?? {}) as { role?: string; can?: { finance?: boolean } };
  const role = acc.role ?? "owner";
  const canMoney = access.error ? true : acc.can?.finance === true;
  const bt = (settings.data as { business_type?: string } | null)?.business_type;
  const rubro = isRubro(bt) ? bt : null;
  const [snap, org, activity, taxes, rubroData] = await Promise.all([
    supabase.rpc("business_snapshot", { p_org: orgId }),
    supabase.from("organizations").select("name, trade_name, monthly_goal").eq("id", orgId).maybeSingle(),
    canMoney ? supabase.rpc("client_activity", { p_org: orgId }) : Promise.resolve({ data: [], error: null }),
    canMoney ? taxContext(supabase, orgId) : Promise.resolve(null),
    rubroContext(supabase, orgId, rubro, canMoney),
  ]);
  if (snap.error) {
    const missing = snap.error.code === "PGRST202" || snap.error.code === "42883";
    return { error: missing ? "Falta ejecutar la migración 20261101_negocio_pro.sql" : "Sin acceso a esa empresa", code: snap.error.code, status: missing ? 500 : 403 };
  }
  // Si la columna monthly_goal aún no existe, se reintenta sin ella (el Copiloto funciona igual).
  let o = org.data as { name?: string; trade_name?: string; monthly_goal?: number | string | null } | null;
  if (org.error) o = ((await supabase.from("organizations").select("name, trade_name").eq("id", orgId).maybeSingle()).data ?? null) as typeof o;
  const enriched = enrichSnapshot(
    (snap.data ?? {}) as Record<string, unknown>,
    ((activity.data ?? []) as ClientActivity[]).slice(0, 500),
    o?.monthly_goal == null ? null : Number(o.monthly_goal),
  );
  Object.assign(enriched, { taxes });
  return {
    snapshot: canMoney ? enriched : redactMoney(enriched),
    name: String(o?.trade_name || o?.name || ""),
    extra: { block: rubroPromptBlock({ rubro, role, canMoney, plan, features }), rubroData },
  };
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
