/** Utilidades puras del envío de comprobantes por correo (testeables sin red). */

export const MAX_PDF_BYTES = 3_000_000; // Vercel limita el cuerpo a 4,5 MB (base64 pesa +33 %)

export const escapeHtml = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

/** Validación práctica: sin saltos de línea (evita inyección de cabeceras), un solo @, dominio con punto. */
export function isEmail(s: unknown): s is string {
  return typeof s === "string" && s.length <= 254 && /^[^\s@<>",;:\\]+@[^\s@<>",;:\\]+\.[^\s@<>",;:\\]{2,}$/.test(s);
}

/** Un PDF real empieza por "%PDF-". */
export function looksLikePdf(b: Uint8Array): boolean {
  return b.length > 8 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46 && b[4] === 0x2d;
}

/** Solo caracteres seguros para el nombre del adjunto. */
export const safeFilename = (n: string) => (n.replace(/[^\w.\-]+/g, "_").slice(0, 60) || "comprobante") + ".pdf";

export function buildEmail(opts: { business: string; client: string; number: string; total: string }) {
  const business = escapeHtml(opts.business || "Tu proveedor");
  const client = escapeHtml(opts.client || "cliente");
  const number = escapeHtml(opts.number);
  const total = escapeHtml(opts.total);
  const subject = `${opts.business || "Comprobante"} · ${opts.number}`.replace(/[\r\n]+/g, " ").slice(0, 150);
  const html = `<!doctype html><html lang="es"><body style="margin:0;background:#f8f6fd;font-family:Arial,Helvetica,sans-serif;color:#26254b">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:24px;overflow:hidden">
<tr><td style="background:linear-gradient(135deg,#6a62e2,#b58bf5);padding:28px 28px 24px;color:#ffffff">
<div style="font-size:13px;opacity:.85">Comprobante</div>
<div style="font-size:24px;font-weight:700;margin-top:4px">${number}</div></td></tr>
<tr><td style="padding:28px">
<p style="margin:0 0 14px;font-size:16px">Hola ${client},</p>
<p style="margin:0 0 20px;font-size:15px;line-height:1.5;color:#55577a"><b>${business}</b> te envía su comprobante. Lo encuentras adjunto en PDF.</p>
<div style="background:#f3f1fc;border-radius:16px;padding:16px 18px;font-size:15px">Total <b style="float:right;font-size:18px">${total}</b></div>
<p style="margin:22px 0 0;font-size:12px;color:#8a8cab">Enviado con FacturaVoz.</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject, html };
}

/** Aviso de fin de importación masiva. */
export function buildImportEmail(opts: { business: string; status: "done" | "failed"; imported: number; skipped: number; error?: string | null }) {
  const business = escapeHtml(opts.business || "tu empresa");
  const ok = opts.status === "done";
  const subject = ok ? "Tus facturas ya están importadas" : "No pudimos terminar tu importación";
  const detail = ok
    ? `Importamos <b>${opts.imported}</b> factura(s) en <b>${business}</b>${opts.skipped > 0 ? ` y omitimos <b>${opts.skipped}</b> fila(s) repetidas o con datos no válidos` : ""}.`
    : `La importación en <b>${business}</b> se detuvo${opts.error ? `: ${escapeHtml(opts.error)}` : ""}. Abre la app para reintentarlo.`;
  const html = `<!doctype html><html lang="es"><body style="margin:0;background:#f8f6fd;font-family:Arial,Helvetica,sans-serif;color:#26254b">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:24px;overflow:hidden">
<tr><td style="background:linear-gradient(135deg,#6a62e2,#b58bf5);padding:26px 28px;color:#ffffff;font-size:22px;font-weight:700">${escapeHtml(subject)}</td></tr>
<tr><td style="padding:26px 28px;font-size:15px;line-height:1.55;color:#55577a">${detail}<p style="margin:18px 0 0;font-size:12px;color:#8a8cab">Enviado con FacturaVoz.</p></td></tr>
</table></td></tr></table></body></html>`;
  return { subject, html };
}
