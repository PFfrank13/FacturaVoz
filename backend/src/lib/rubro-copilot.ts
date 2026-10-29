import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Copiloto por rubro (D): rol, vocabulario y datos propios de cada tipo de negocio, MÁS los permisos del rol
 * y lo que incluye el plan. Todo lo que el Copiloto dice sale de consultas reales (RLS con el token del usuario);
 * si un dato no está, debe decir "no lo tengo". El historial privado (datos de salud) NUNCA se consulta.
 * Mantener alineado con app/lib/rubros.dart.
 */
export type RubroId = "bodega" | "restaurante" | "servicios_tecnicos" | "salon" | "consultorio" | "taller" | "mayorista" | "educacion" | "construccion";

export const RUBRO_COPILOT: Record<RubroId, { name: string; role: string; client: string; job: string }> = {
  bodega: { name: "Bodega o tienda", role: "el ayudante de una bodega de barrio: ventas del día, fiados, productos que se acaban y la caja", client: "casero", job: "pedido" },
  restaurante: { name: "Restaurante o cafetería", role: "el administrador de un restaurante: mesas, comandas, platos más vendidos, margen por plato, caja y propinas", client: "comensal", job: "reserva" },
  servicios_tecnicos: { name: "Servicios técnicos e internet", role: "el jefe de operaciones de un proveedor de internet y servicios técnicos: instalaciones, técnicos, mensualidades y morosos", client: "abonado", job: "instalación" },
  salon: { name: "Salón o barbería", role: "el administrador de un salón o barbería: citas, no-shows, comisiones por estilista y paquetes", client: "cliente", job: "cita" },
  consultorio: { name: "Consultorio o profesional independiente", role: "el asistente ADMINISTRATIVO de un consultorio: agenda, citas por confirmar, sesiones y cobros. NUNCA hables de diagnósticos, tratamientos ni notas clínicas: no los tienes", client: "paciente", job: "cita" },
  taller: { name: "Taller mecánico", role: "el jefe de un taller mecánico: órdenes por placa, presupuestos por aprobar, repuestos y mantenimientos que tocan", client: "cliente", job: "orden" },
  mayorista: { name: "Mayorista o distribuidor", role: "el gerente comercial de una distribuidora: pedidos, crédito con límite por cliente, cobranza y precios por mayor", client: "cliente", job: "despacho" },
  educacion: { name: "Academia o educación", role: "el administrador de una academia: matrículas, pensiones pendientes por grupo, apoderados y horarios", client: "alumno o apoderado", job: "matrícula" },
  construccion: { name: "Construcción o contratista", role: "el jefe de obra y finanzas de un contratista: hitos, valorizaciones, adelantos, gastos por obra y margen", client: "cliente", job: "obra" },
};

export const isRubro = (v: unknown): v is RubroId => typeof v === "string" && v in RUBRO_COPILOT;

/** Campos de dinero del resumen: se quitan si el rol no puede ver dinero (cajero, técnico, vendedor). */
const MONEY_KEYS = [
  "sales_this_month", "sales_last_month", "sales_last_month_same_day", "receivable_total", "overdue_total", "debtors", "due_next_7_days",
  "top_clients_90d", "expenses_this_month", "expenses_last_month", "collected_this_month", "open_quotes", "slow_payers", "taxes",
  "goal_progress", "monthly_goal", "clients_at_risk", "best_clients", "credit_notes_this_month",
];

export function redactMoney(snapshot: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(snapshot)) if (!MONEY_KEYS.includes(k)) out[k] = v;
  out.money_hidden = "Este usuario no puede ver montos del negocio por su rol.";
  return out;
}

export type Who = { rubro: RubroId | null; role: string; canMoney: boolean; plan: string; features: Record<string, unknown> | null };

/** Bloque del prompt con rubro, rol y plan (va ANTES de las reglas generales). */
export function rubroPromptBlock(w: Who): string {
  const r = w.rubro ? RUBRO_COPILOT[w.rubro] : null;
  const off = w.features ? Object.entries(w.features).filter(([, v]) => v === false).map(([k]) => k).slice(0, 30) : [];
  return [
    r ? `Rubro: ${r.name}. Eres ${r.role}. Al cliente le dices "${r.client}" y al trabajo "${r.job}".` : "Rubro: no elegido todavía (responde de forma general).",
    `Rol de quien pregunta: ${w.role}.${w.canMoney ? "" : " NO puede ver montos del negocio: si pregunta por ventas, ganancias o deudas, dile con amabilidad que eso lo ve el dueño o finanzas."}`,
    `Plan: ${w.plan || "desconocido"}.${off.length ? ` Funciones NO incluidas en su plan: ${off.join(", ")}. Si pide algo de eso, dile que está disponible en un plan mayor (Menú → Mi plan).` : ""}`,
    "Acciones: la app SIEMPRE pide confirmación; anular o borrar cobros pide además el PIN del dueño. Tú solo propones.",
    "Datos: responde SOLO con lo que está en <resumen> y <rubro_datos>. Si no está, di exactamente qué no tienes (\"no lo tengo registrado\") y dónde verlo. Nunca inventes nombres, cifras ni fechas.",
  ].join("\n");
}

const today = () => new Date(Date.now() - 5 * 3600_000).toISOString().slice(0, 10); // Lima (UTC−5, sin horario de verano)
const addDays = (iso: string, n: number) => new Date(Date.parse(`${iso}T00:00:00Z`) + n * 864e5).toISOString().slice(0, 10);

type Q = PromiseLike<{ data: unknown; error: unknown }>;
async function safe<T>(q: Q, map: (d: unknown) => T): Promise<T | null> {
  try {
    const { data, error } = await q;
    return error ? null : map(data);
  } catch {
    return null;
  }
}

/** Datos reales propios del rubro (consultas livianas en paralelo; todo con RLS del usuario). */
export async function rubroContext(supabase: SupabaseClient, orgId: string, rubro: RubroId | null, canMoney: boolean): Promise<Record<string, unknown>> {
  if (!rubro) return {};
  const d0 = today();
  const d1 = addDays(d0, 1);
  const d2 = addDays(d0, 2);
  const jobsBetween = (from: string, to: string) =>
    safe(
      supabase.from("jobs").select("title, kind, status, scheduled_at, clients(name)").eq("org_id", orgId).gte("scheduled_at", `${from}T05:00:00Z`).lt("scheduled_at", `${to}T05:00:00Z`).order("scheduled_at").limit(25),
      (d) => (d as { title: string; status: string; scheduled_at: string; clients: { name?: string } | null }[]).map((j) => ({ title: j.title, status: j.status, at: j.scheduled_at, client: j.clients?.name ?? "" })),
    );
  const openJobs = () =>
    safe(
      supabase.from("jobs").select("title, status, clients(name)").eq("org_id", orgId).is("done_at", null).order("created_at", { ascending: false }).limit(40),
      (d) => {
        const rows = d as { title: string; status: string; clients: { name?: string } | null }[];
        const by: Record<string, number> = {};
        for (const r of rows) by[r.status] = (by[r.status] ?? 0) + 1;
        return { by_status: by, latest: rows.slice(0, 8).map((r) => ({ title: r.title, status: r.status, client: r.clients?.name ?? "" })) };
      },
    );
  const reminders = () =>
    safe(
      supabase.from("service_reminders").select("title, due_on, clients(name)").eq("org_id", orgId).is("done_at", null).lte("due_on", addDays(d0, 14)).order("due_on").limit(15),
      (d) => (d as { title: string; due_on: string; clients: { name?: string } | null }[]).map((r) => ({ title: r.title, due: r.due_on, client: r.clients?.name ?? "" })),
    );
  const packages = () =>
    safe(
      supabase.from("service_packages").select("name, sessions_total, sessions_used, expires_on, clients(name)").eq("org_id", orgId).order("created_at", { ascending: false }).limit(60),
      (d) =>
        (d as { name: string; sessions_total: number; sessions_used: number; expires_on: string | null; clients: { name?: string } | null }[])
          .filter((p) => p.sessions_used < p.sessions_total && (!p.expires_on || p.expires_on >= d0))
          .slice(0, 15)
          .map((p) => ({ client: p.clients?.name ?? "", package: p.name, left: p.sessions_total - p.sessions_used })),
    );
  const out: Record<string, unknown> = { today: d0 };
  const tasks: Promise<void>[] = [];
  const put = (k: string, p: Promise<unknown>) => tasks.push(p.then((v) => { if (v != null) out[k] = v; }));

  switch (rubro) {
    case "bodega":
      if (canMoney) put("fiados_top", safe(supabase.rpc("credit_balances", { p_org: orgId }), (d) => (d as { client_name?: string; balance?: number; oldest_due?: string | null }[]).slice(0, 10).map((x) => ({ client: x.client_name, balance: x.balance, oldest_due: x.oldest_due }))));
      break;
    case "restaurante":
      put("kitchen_open", safe(supabase.from("quotes").select("number, table_label, kitchen_status").eq("org_id", orgId).not("kitchen_status", "is", null).neq("kitchen_status", "entregado").limit(30), (d) => d));
      put("reservations_today", jobsBetween(d0, d1));
      break;
    case "servicios_tecnicos":
      put("jobs_today_tomorrow", jobsBetween(d0, d2));
      put("jobs_open", openJobs());
      put("service_cut", safe(supabase.from("clients").select("name").eq("org_id", orgId).eq("extra->>servicio", "cortado").limit(30), (d) => (d as { name: string }[]).map((c) => c.name)));
      break;
    case "salon":
    case "consultorio":
      put("appointments_today_tomorrow", jobsBetween(d0, d2));
      put("packages_with_sessions", packages());
      put("comeback_reminders", reminders());
      put("no_shows_90d", safe(supabase.from("jobs").select("clients(name)").eq("org_id", orgId).eq("status", "no_vino").gte("created_at", `${addDays(d0, -90)}T00:00:00Z`).limit(50), (d) => (d as unknown[]).length));
      break;
    case "taller":
      put("orders_open", openJobs());
      put("maintenance_due", reminders());
      break;
    case "mayorista":
      if (canMoney) put("credit_limits", safe(supabase.from("clients").select("name, credit_limit").eq("org_id", orgId).not("credit_limit", "is", null).limit(80), (d) => d));
      break;
    case "educacion":
      put("classes_today_tomorrow", jobsBetween(d0, d2));
      put("packages_with_sessions", packages());
      break;
    case "construccion":
      put("works_open", openJobs());
      if (canMoney) put("milestones", safe(supabase.from("job_milestones").select("title, amount, status, due_date, jobs(title)").eq("org_id", orgId).neq("status", "facturado").order("due_date").limit(30), (d) => d));
      break;
  }
  await Promise.all(tasks);
  return out;
}
