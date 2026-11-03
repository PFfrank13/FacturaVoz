import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { PLANNER_SYSTEM, prepareSteps, sanitizePlan } from "@/lib/agent";
import { chatJson, cleanText, GroqError } from "@/lib/groq";
import { limaToday } from "@/lib/publicdata";
import { UUID } from "@/lib/publicbase";

export const maxDuration = 45;
export const OPTIONS = preflight;

/**
 * Tareas del Copiloto (plan Empresa). El dueño o administrador escribe qué quiere; el Copiloto la PREPARA y queda
 * "por aprobar". No hace nada hasta que se aprueba (api/agent/decide). Solo acciones de una lista cerrada.
 */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const key = process.env.GROQ_API_KEY;
  if (!key) return json({ error: "Servicio de IA no configurado en el servidor", code: "no_key" }, 503);
  const body = await readJson(req, 4_000);
  if (!body) return json({ error: "Solicitud no válida" }, 400);
  const orgId = typeof body.org_id === "string" && UUID.test(body.org_id) ? body.org_id : null;
  const text = typeof body.text === "string" ? cleanText(body.text, 800) : "";
  if (!orgId) return json({ error: "Elige una empresa" }, 400);
  if (!text) return json({ error: "Cuéntame qué tarea quieres encargarme" }, 400);
  const { supabase } = auth;

  const [{ data: lic }, quota] = await Promise.all([
    supabase.rpc("my_license", { p_org: orgId }),
    supabase.rpc("consume_api_quota", { p_per_minute: 4, p_per_day: 40 }),
  ]);
  const features = ((lic as { features?: Record<string, unknown> } | null)?.features ?? null) as Record<string, unknown> | null;
  const status = lic as { enforced?: boolean; dev?: boolean; source?: string; mode?: string } | null;
  if (status?.enforced !== true || status.dev === true || status.source !== "hub"
      || (status.mode !== "full" && status.mode !== "warning") || features?.copiloto_agente !== true) {
    return json({ error: "Las Tareas del Copiloto son del plan Empresa. Mejora tu plan en Menú → Mi plan.", code: "feature" }, 402);
  }
  if (quota.error) return json({ error: "Falta ejecutar la migración de cuotas en Supabase", code: "quota_rpc" }, 500);
  if (quota.data !== true) return json({ error: "Demasiados pedidos seguidos. Espera un minuto." }, 429);

  try {
    const [snap, org] = await Promise.all([
      supabase.rpc("business_snapshot", { p_org: orgId }),
      supabase.from("organizations").select("name, trade_name").eq("id", orgId).maybeSingle(),
    ]);
    if (snap.error) return json({ error: "Sin acceso a esa empresa" }, 403);
    const business = String((org.data as { trade_name?: string; name?: string } | null)?.trade_name || (org.data as { name?: string } | null)?.name || "");
    const raw = await chatJson(key, PLANNER_SYSTEM, `<pedido>\n${text}\n</pedido>`, 600);
    const plan = sanitizePlan(raw);
    if (!plan) return json({ error: "Eso todavía no lo sé hacer solo. Puedo: preparar mensajes de cobro, armar la lista de reposición, programar recordatorios de cobro o hacer el resumen de la semana.", code: "unsupported" }, 422);
    const results = await prepareSteps(supabase, orgId, plan, (snap.data ?? {}) as Record<string, unknown>, business, limaToday());
    const { data: task, error } = await supabase
      .from("agent_tasks")
      .insert({ org_id: orgId, prompt: text, title: plan.title, plan: { steps: plan.steps, results } })
      .select("id, title, status, plan, created_at")
      .single();
    if (error) return json({ error: "Solo el dueño o un administrador puede encargar tareas.", code: error.code }, 403);
    return json({ task });
  } catch (e) {
    if (e instanceof GroqError && e.status === 429) return json({ error: "Servicio ocupado, inténtalo en un minuto" }, 503);
    console.error("agent: failed", e instanceof GroqError ? e.code : e instanceof Error ? e.name : "unknown");
    return json({ error: "No pude preparar la tarea. Inténtalo de nuevo." }, 502);
  }
}
