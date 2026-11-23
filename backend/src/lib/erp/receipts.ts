/** Pure helpers for the web Comprobantes module (no I/O, fully testable). */

export type FiscalInfo = {
  doc_type: "01" | "03" | string; series: string; correlative: number;
  status: "pending" | "accepted" | "rejected" | "error" | string;
  sunat_code: string | null; sunat_message: string | null; issued_at: string; env?: string;
};

export type ReceiptRow = {
  id: string; number: string; issue_date: string; status: string; currency: string | null;
  doc_kind: string | null; amt_total: number | string | null; voided_at: string | null;
  client: { name: string | null; tax_id: string | null } | null;
  fiscal: FiscalInfo | null;
};

export type ReceiptKind = "factura" | "boleta" | "nota_credito" | "nota_venta" | "borrador";

export function receiptKind(r: Pick<ReceiptRow, "doc_kind" | "fiscal">): ReceiptKind {
  if (r.fiscal?.doc_type === "01") return "factura";
  if (r.fiscal?.doc_type === "03") return "boleta";
  if (r.doc_kind === "factura" || r.doc_kind === "boleta" || r.doc_kind === "nota_credito" || r.doc_kind === "nota_venta") return r.doc_kind;
  return "borrador";
}

export const kindLabel: Record<ReceiptKind, string> = {
  factura: "Factura", boleta: "Boleta", nota_credito: "Nota de crédito", nota_venta: "Nota de venta", borrador: "Borrador",
};

export type SunatState = "aceptado" | "pendiente" | "rechazado" | "error" | "anulado" | "sin_envio";

export function sunatState(r: Pick<ReceiptRow, "voided_at" | "fiscal">): SunatState {
  if (r.voided_at) return "anulado";
  switch (r.fiscal?.status) {
    case "accepted": return "aceptado";
    case "pending": return "pendiente";
    case "rejected": return "rechazado";
    case "error": return "error";
    default: return "sin_envio";
  }
}

export const sunatLabel: Record<SunatState, string> = {
  aceptado: "Aceptado por SUNAT", pendiente: "Pendiente de envío", rechazado: "Rechazado por SUNAT",
  error: "Error de envío", anulado: "Anulado", sin_envio: "No enviado a SUNAT",
};

/** Lima calendar date (YYYY-MM-DD) of an instant. */
export function limaDate(instant: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima", year: "numeric", month: "2-digit", day: "2-digit" }).format(instant);
}

function addDays(date: string, days: number): string {
  const d = new Date(`${date}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/**
 * How an accepted electronic receipt can still be cancelled.
 * Boletas are cancelled inside the daily summary and facturas with a
 * «comunicación de baja», both up to 7 calendar days after issue; later, only
 * a credit note corrects them.
 */
export function voidWindow(r: Pick<ReceiptRow, "issue_date" | "voided_at" | "fiscal">, today = limaDate(new Date())):
  { kind: "baja" | "resumen" | "nota_credito" | "none"; until: string | null } {
  if (r.voided_at || r.fiscal?.status !== "accepted") return { kind: "none", until: null };
  const until = addDays(r.issue_date, 7);
  if (today > until) return { kind: "nota_credito", until: null };
  return { kind: r.fiscal.doc_type === "01" ? "baja" : "resumen", until };
}

export function voidHint(w: ReturnType<typeof voidWindow>): string | null {
  const fmt = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "long", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
  switch (w.kind) {
    case "baja": return `Puedes anularla con comunicación de baja hasta el ${fmt(w.until!)}.`;
    case "resumen": return `Puedes anularla en el resumen diario hasta el ${fmt(w.until!)}.`;
    case "nota_credito": return "Pasó el plazo de anulación: corrígela con una nota de crédito.";
    default: return null;
  }
}

export function receiptNumber(r: Pick<ReceiptRow, "number" | "fiscal">): string {
  return r.fiscal ? `${r.fiscal.series}-${String(r.fiscal.correlative).padStart(8, "0")}` : r.number;
}

export type ReceiptFilter = { q?: string; kind?: ReceiptKind | "todos"; sunat?: SunatState | "todos" };

export function matchesReceipt(r: ReceiptRow, f: ReceiptFilter): boolean {
  if (f.kind && f.kind !== "todos" && receiptKind(r) !== f.kind) return false;
  if (f.sunat && f.sunat !== "todos" && sunatState(r) !== f.sunat) return false;
  const q = f.q?.trim().toLocaleLowerCase("es");
  if (!q) return true;
  return [receiptNumber(r), r.number, r.client?.name ?? "", r.client?.tax_id ?? ""]
    .some(v => v.toLocaleLowerCase("es").includes(q));
}

export function summarize(rows: ReceiptRow[]) {
  let total = 0, accepted = 0, attention = 0;
  for (const r of rows) {
    const s = sunatState(r);
    if (s !== "anulado" && receiptKind(r) !== "nota_credito") total += Number(r.amt_total ?? 0);
    if (s === "aceptado") accepted++;
    if (s === "rechazado" || s === "error" || s === "pendiente") attention++;
  }
  return { total, accepted, attention, count: rows.length };
}

const isoDate = /^\d{4}-\d{2}-\d{2}$/;
const realDate = (d: string) => isoDate.test(d) && new Date(`${d}T12:00:00Z`).toISOString().slice(0, 10) === d;

/**
 * Issue-date range from the URL (`desde`/`hasta`, both included). Invalid or
 * reversed values, or ranges longer than 366 days, fall back to «sin rango»
 * so the list never silently hides receipts.
 */
export function parseRange(from: unknown, to: unknown): { from: string; to: string } | null {
  if (typeof from !== "string" || typeof to !== "string" || !realDate(from) || !realDate(to) || from > to) return null;
  if (Date.parse(to) - Date.parse(from) > 366 * 86400000) return null;
  return { from, to };
}

/** Quick ranges for the filter, in Lima calendar days. */
export function presetRange(preset: "hoy" | "7dias" | "mes", today = limaDate(new Date())): { from: string; to: string } {
  if (preset === "hoy") return { from: today, to: today };
  if (preset === "7dias") return { from: addDays(today, -6), to: today };
  return { from: `${today.slice(0, 7)}-01`, to: today };
}

/** Text sent with the receipt link, by WhatsApp or e-mail (same wording as the mobile app). */
export function shareMessage(o: { client: string | null | undefined; number: string; business: string; url: string }): string {
  const who = o.client && o.client.trim() && o.client !== "—" ? ` ${o.client.trim()}` : "";
  return `Hola${who}, aquí tienes tu comprobante ${o.number}${o.business ? ` de ${o.business}` : ""}:\n${o.url}`;
}

/** mailto: link with subject and body; the user's own mail app sends it (no server cost, replies reach the business). */
export function mailtoHref(o: { to: string | null | undefined; number: string; business: string; body: string }): string {
  const to = o.to && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(o.to.trim()) ? o.to.trim() : "";
  const subject = `Comprobante ${o.number}${o.business ? ` · ${o.business}` : ""}`;
  return `mailto:${encodeURIComponent(to).replace(/%40/g, "@")}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(o.body)}`;
}
