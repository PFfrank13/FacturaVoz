import { escapeHtml } from "./email";
import { fmtMoney } from "./publicbase";

/** Correo del cierre del día (para el dueño). Puro y testeable. */
export type DaySummary = {
  day: string;
  currency: string;
  sales?: { sales_total?: number; sales_count?: number; drafts_count?: number };
  payments_by_method?: Record<string, number>;
  cash_opening?: number;
  cash_sales?: number;
  cash_in?: number;
  cash_out?: number;
  fiado_charged?: number;
  fiado_paid?: number;
  expected_cash?: number;
  expenses?: number | null;
};

const METHOD: Record<string, string> = { efectivo: "Efectivo", yape: "Yape", plin: "Plin", transferencia: "Transferencia", tarjeta: "Tarjeta", mercadopago: "Mercado Pago", otro: "Otro" };

export function buildDayCloseEmail(o: { business: string; summary: DaySummary; counted: number | null; closedBy: string }) {
  const s = o.summary;
  const cur = s.currency || "PEN";
  const m = (n: number | null | undefined) => escapeHtml(fmtMoney(Number(n ?? 0), cur));
  const diff = o.counted == null ? null : Math.round((o.counted - Number(s.expected_cash ?? 0)) * 100) / 100;
  const [y, mo, d] = s.day.split("-");
  const rows: [string, string, string?][] = [
    ["Ventas emitidas", `${m(s.sales?.sales_total)} (${s.sales?.sales_count ?? 0})`],
    ...Object.entries(s.payments_by_method ?? {}).map(([k, v]) => [`Cobrado · ${METHOD[k] ?? k}`, m(v)] as [string, string]),
    ["Fiado del día", m(s.fiado_charged)],
    ["Abonos de fiados", m(s.fiado_paid)],
    ["Ingresos/egresos de caja", `${m(s.cash_in)} / ${m(s.cash_out)}`],
    ...(s.expenses == null ? [] : [["Gastos", m(s.expenses)] as [string, string]]),
    ["Efectivo esperado en caja", m(s.expected_cash)],
    ...(o.counted == null ? [] : [["Efectivo contado", m(o.counted)] as [string, string], ["Diferencia", m(diff), diff !== 0 ? "#d94a5e" : "#23956f"] as [string, string, string]]),
  ];
  const subject = `Cierre del ${d}/${mo}/${y} · ${o.business}`.replace(/[\r\n]+/g, " ").slice(0, 150);
  const html = `<!doctype html><html lang="es"><body style="margin:0;background:#f8f6fd;font-family:Arial,Helvetica,sans-serif;color:#26254b">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:24px;overflow:hidden">
<tr><td style="background:linear-gradient(135deg,#6a62e2,#b58bf5);padding:24px 28px;color:#fff"><div style="font-size:13px;opacity:.85">${escapeHtml(o.business)}</div>
<div style="font-size:22px;font-weight:700;margin-top:4px">Cierre del día ${d}/${mo}/${y}</div></td></tr>
<tr><td style="padding:22px 28px">
<table role="presentation" width="100%" style="font-size:14.5px;border-collapse:collapse">
${rows.map(([k, v, c]) => `<tr><td style="padding:8px 0;color:#55577a;border-bottom:1px solid #ece9f7">${escapeHtml(k)}</td><td align="right" style="padding:8px 0;font-weight:700;border-bottom:1px solid #ece9f7${c ? `;color:${c}` : ""}">${v}</td></tr>`).join("")}
</table>
${(s.sales?.drafts_count ?? 0) > 0 ? `<p style="margin:16px 0 0;font-size:13px;color:#c57a12">Quedan ${s.sales?.drafts_count} borrador(es) sin emitir.</p>` : ""}
<p style="margin:18px 0 0;font-size:12px;color:#8a8cab">Cerrado por ${escapeHtml(o.closedBy)} · Enviado con FacturaVoz.</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject, html };
}
