import { authenticateBearer, jsonWith, preflight, readJson } from "@/lib/api-auth";
import { executeApproved, type StepResult } from "@/lib/agent";
import { UUID } from "@/lib/publicbase";

export const maxDuration = 30;
export const OPTIONS = preflight;

/** Aprobar o rechazar una tarea preparada. Aprobar ejecuta solo lo que escribe (recordatorios) y la deja "hecha". */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  const body = await readJson(req, 1_000);
  const id = typeof body?.task_id === "string" && UUID.test(body.task_id) ? body.task_id : null;
  const decision = body?.decision === "approve" ? "approve" : body?.decision === "reject" ? "reject" : null;
  if (!id || !decision) return json({ error: "Solicitud no válida" }, 400);
  const { supabase } = auth;

  const { data: task } = await supabase.from("agent_tasks").select("id, org_id, status, plan").eq("id", id).maybeSingle();
  if (!task) return json({ error: "No encontré esa tarea" }, 404);
  if (task.status !== "proposed") return json({ error: "Esa tarea ya fue atendida", code: "closed" }, 409);

  const next = decision === "approve" ? "approved" : "rejected";
  // El UPDATE solo prospera si sigue "por aprobar" (evita doble ejecución si tocan dos veces).
  const { data: upd, error } = await supabase.from("agent_tasks").update({ status: next }).eq("id", id).eq("status", "proposed").select("id").maybeSingle();
  if (error || !upd) return json({ error: "No se pudo registrar tu decisión (¿plan Empresa y rol de administrador?)" }, 403);
  if (decision === "reject") return json({ status: "rejected" });

  try {
    const results = ((task.plan as { results?: StepResult[] } | null)?.results ?? []) as StepResult[];
    const summary = await executeApproved(supabase, task.org_id as string, results);
    await supabase.from("agent_tasks").update({ status: "done", result: summary }).eq("id", id);
    return json({ status: "done", result: summary });
  } catch {
    await supabase.from("agent_tasks").update({ status: "failed", result: { error: "No se pudo ejecutar" } }).eq("id", id);
    return json({ status: "failed", error: "Aprobaste la tarea pero no se pudo ejecutar. Inténtalo de nuevo desde cero." }, 500);
  }
}
