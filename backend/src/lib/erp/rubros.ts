/** Rules of the per-industry modules (ports of business_templates.dart, rubro_tools.dart, logic/cutoff.dart and logic/obra.dart). Pure. */

export type JobStatus = { key: string; label: string; done: boolean; color: string };
const st = (key: string, label: string, color: string, done = false): JobStatus => ({ key, label, color, done });

const base = [st("nuevo", "Nuevo", "#8a8cab"), st("en_proceso", "En proceso", "#c57a12"), st("terminado", "Terminado", "#23956f", true)];
const bySector: Record<string, JobStatus[]> = {
  bodega: [st("nuevo", "Pedido", "#8a8cab"), st("listo", "Listo para recoger", "#c57a12"), st("entregado", "Entregado", "#23956f", true)],
  restaurante: [st("nuevo", "Reservado", "#8a8cab"), st("confirmado", "Confirmado", "#c57a12"), st("atendido", "Atendido", "#23956f", true)],
  servicios_tecnicos: [st("nuevo", "Interesado", "#8a8cab"), st("visita", "Visita técnica", "#5b8def"), st("cotizado", "Cotizado", "#9b8cf5"), st("pendiente", "Instalación pendiente", "#c57a12"),
    st("en_camino", "En camino", "#e38b2c"), st("instalado", "Instalado", "#23956f", true), st("cobrado", "Cobrado", "#1f7a5b", true)],
  salon: [st("nuevo", "Por confirmar", "#8a8cab"), st("confirmado", "Confirmada", "#c57a12"), st("atendido", "Atendida", "#23956f", true), st("no_vino", "No vino", "#d94a5e")],
  consultorio: [st("nuevo", "Por confirmar", "#8a8cab"), st("confirmado", "Confirmada", "#c57a12"), st("atendido", "Atendida", "#23956f", true)],
  taller: [st("nuevo", "Recibido", "#8a8cab"), st("diagnostico", "Diagnóstico", "#5b8def"), st("cotizado", "Presupuesto enviado", "#9b8cf5"), st("en_reparacion", "En reparación", "#c57a12"),
    st("listo", "Listo para recoger", "#23956f", true), st("entregado", "Entregado", "#1f7a5b", true)],
  mayorista: [st("nuevo", "Pedido", "#8a8cab"), st("despachado", "Despachado", "#c57a12"), st("entregado", "Entregado", "#23956f", true)],
  educacion: [st("nuevo", "Inscrito", "#8a8cab"), st("activo", "En curso", "#c57a12"), st("terminado", "Terminó", "#23956f", true)],
  construccion: [st("nuevo", "Presupuesto", "#8a8cab"), st("aprobado", "Aprobado", "#9b8cf5"), st("en_obra", "En obra", "#c57a12"), st("terminado", "Entregado", "#23956f", true)],
};

/** The company's own statuses (org_settings.job_statuses) or the template of its industry. */
export function jobStatuses(sector: string | null, custom: unknown): JobStatus[] {
  if (Array.isArray(custom) && custom.length) {
    const list = custom.filter((x): x is Record<string, unknown> => !!x && typeof x === "object" && typeof (x as Record<string, unknown>).key === "string")
      .map(x => st(String(x.key), String(x.label || x.key), typeof x.color === "number" ? `#${(x.color & 0xffffff).toString(16).padStart(6, "0")}` : "#6a62e2", x.done === true));
    if (list.length) return list;
  }
  return bySector[sector ?? ""] ?? base;
}
export const statusOf = (list: JobStatus[], key: string) => list.find(s => s.key === key) ?? st(key, key.replace(/_/g, " "), "#8a8cab");

export const jobKinds: Record<string, string> = { visita: "Visita", instalacion: "Instalación", servicio: "Servicio", reparacion: "Reparación", cita: "Cita", obra: "Obra", pedido: "Pedido", clase: "Clase", otro: "Otro" };

/** Lima wall-clock "YYYY-MM-DDTHH:mm" (datetime-local) → ISO instant. Peru has no daylight saving (UTC−5). */
export function limaLocalToIso(v: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(v.trim());
  if (!m) return null;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4] + 5, +m[5]));
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
/** ISO instant → Lima "YYYY-MM-DDTHH:mm" for a datetime-local input. */
export function isoToLimaLocal(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(Date.parse(iso) - 5 * 3_600_000);
  return Number.isNaN(d.getTime()) ? "" : d.toISOString().slice(0, 16);
}

/** Split a bill: each pays the same rounded down to 0.10 (easier in cash), the last one pays the rest. */
export function splitEven(total: number, people: number): number[] {
  const r2 = (n: number) => Math.round(n * 100) / 100;
  if (people <= 1) return [r2(total)];
  const each = Math.floor((total / people) * 10) / 10;
  return [...Array<number>(people - 1).fill(each), r2(total - each * (people - 1))];
}

export const normPlate = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");

/** Construction: spending traffic light per project (a signal to review, not accounting). */
export function obraSignal(agreed: number, invoiced: number, spent: number): { alert: "none" | "faster" | "over"; spentShare: number; invoicedShare: number } {
  if (agreed <= 0) return { alert: "none", spentShare: 0, invoicedShare: 0 };
  const s = spent / agreed, i = invoiced / agreed;
  if (spent >= agreed - 0.004) return { alert: "over", spentShare: s, invoicedShare: i };
  return { alert: s - i > 0.15 ? "faster" : "none", spentShare: s, invoicedShare: i };
}

const days = (a: string, b: string) => Math.round((Date.parse(`${b}T12:00:00Z`) - Date.parse(`${a}T12:00:00Z`)) / 86_400_000);
/** Cut-off for late payment: only after a prior notice of at least one day (app rule, not a law). */
export function noticeAge(extra: Record<string, unknown>, key: string, today: string): number | null {
  const v = extra[key];
  return typeof v === "string" && v.length >= 10 ? days(v.slice(0, 10), today) : null;
}
export const canCut = (extra: Record<string, unknown>, today: string) => { const a = noticeAge(extra, "aviso_corte_fecha", today); return a != null && a >= 1; };
export function noticeText(extra: Record<string, unknown>, key: string, today: string, never = ""): string {
  const a = noticeAge(extra, key, today);
  return a == null ? never : a <= 0 ? "Avisado hoy" : `Avisado hace ${a} ${a === 1 ? "día" : "días"}`;
}
