import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { amountLegend } from "@/lib/fiscal/words";
import { totalsOf } from "@/lib/publicbase";

/**
 * Portal del cliente final (sin cuenta): con el enlace/QR de su comprobante ve su historial con ese negocio,
 * imprime la representación (A4 o ticket) y descarga el XML y la constancia (CDR) de SUNAT.
 */
export type PortalItem = { id: string; number: string; issueDate: string; currency: string; status: string; total: number; paid: number; fiscal: { series: string; correlative: number; status: string; docType: string } | null };
export type Portal = { token: string; org: { name: string; legalName: string; ruc: string; address: string; logoUrl: string | null }; client: { name: string; taxId: string } | null; invoiceId: string; history: PortalItem[] };

export const isPortalToken = (t: unknown): t is string => typeof t === "string" && /^[A-Za-z0-9_-]{20,80}$/.test(t);

export async function signedLogo(path: string | null | undefined): Promise<string | null> {
  if (!path) return null;
  const { data } = await createAdminClient().storage.from("org-media").createSignedUrl(path, 3600);
  return data?.signedUrl ?? null;
}

export async function getPortal(token: string): Promise<Portal | null> {
  if (!isPortalToken(token)) return null;
  const { data } = await createAdminClient().rpc("portal_get", { p_token: token });
  if (!data) return null;
  const d = data as {
    org: { name: string; legal_name: string; ruc: string | null; address: string | null; logo_path: string | null };
    client: { name: string; tax_id: string | null } | null;
    invoice_id: string;
    history: { id: string; number: string; issue_date: string; currency: string; status: string; total: number; paid: number; fiscal: { series: string; correlative: number; status: string; doc_type: string } | null }[];
  };
  return {
    token,
    org: { name: d.org.name, legalName: d.org.legal_name, ruc: d.org.ruc ?? "", address: d.org.address ?? "", logoUrl: await signedLogo(d.org.logo_path) },
    client: d.client ? { name: d.client.name, taxId: d.client.tax_id ?? "" } : null,
    invoiceId: d.invoice_id,
    history: d.history.map((h) => ({
      id: h.id,
      number: h.number,
      issueDate: h.issue_date,
      currency: h.currency,
      status: h.status,
      total: Number(h.total),
      paid: Number(h.paid),
      fiscal: h.fiscal ? { series: h.fiscal.series, correlative: h.fiscal.correlative, status: h.fiscal.status, docType: h.fiscal.doc_type } : null,
    })),
  };
}

export type PrintLine = { qty: number; unit: string; description: string; unitValue: number; amount: number };
export type PrintDoc = {
  title: string;
  number: string;
  fiscal: boolean;
  env: string;
  status: string;
  issuer: { name: string; trade: string; ruc: string; address: string; logoUrl: string | null };
  client: { name: string; docLabel: string; doc: string; address: string };
  date: string;
  currency: string;
  payment: string;
  lines: PrintLine[];
  totals: { label: string; value: number; strong?: boolean }[];
  legend: string;
  hash: string;
  qr: string | null;
  hasXml: boolean;
  hasCdr: boolean;
};

const DOC_LABEL: Record<string, string> = { "6": "RUC", "1": "DNI", "4": "C. EXTRANJERÍA", "7": "PASAPORTE" };
const n = (v: unknown) => (typeof v === "number" ? v : Number(v ?? 0) || 0);

/** Representación impresa: si hay comprobante SUNAT se arma SOLO con lo enviado a SUNAT (como la app). */
export async function getPrintDoc(portal: Portal, invoiceId: string): Promise<PrintDoc | null> {
  if (!portal.history.some((h) => h.id === invoiceId)) return null;
  const admin = createAdminClient();
  const { data: inv } = await admin
    .from("invoices")
    .select("id, number, issue_date, due_date, currency, tax_rate, status, clients(name, tax_id, address), invoice_items(description, quantity, unit_price, position), organizations(name, trade_name, tax_id, address, logo_path)")
    .eq("id", invoiceId)
    .order("position", { referencedTable: "invoice_items", ascending: true })
    .maybeSingle();
  if (!inv) return null;
  const { data: fd } = await admin.from("fiscal_documents").select("doc_type, series, correlative, env, status, payload, totals, legend, hash, xml, cdr").eq("invoice_id", invoiceId).maybeSingle();
  const org = (Array.isArray(inv.organizations) ? inv.organizations[0] : inv.organizations) as { name: string; trade_name: string | null; tax_id: string | null; address: string | null; logo_path: string | null } | null;
  const logoUrl = await signedLogo(org?.logo_path);
  if (fd) {
    const p = fd.payload as Record<string, unknown>;
    const company = (p.company ?? {}) as Record<string, unknown>;
    const addr = (company.address ?? {}) as Record<string, unknown>;
    const client = (p.client ?? {}) as Record<string, unknown>;
    const t = fd.totals as Record<string, unknown>;
    const fp = (p.formaPago ?? {}) as Record<string, unknown>;
    const cuotas = Array.isArray(p.cuotas) ? (p.cuotas as Record<string, unknown>[]) : [];
    const details = Array.isArray(p.details) ? (p.details as Record<string, unknown>[]) : [];
    const isoDate = String(p.fechaEmision ?? "").slice(0, 10);
    const series = fd.series as string;
    const corr = String(fd.correlative).padStart(8, "0");
    const tipoDoc = String(client.tipoDoc ?? "-");
    const igv = n(t.igv);
    const total = n(t.total);
    const rate = details.length ? n(details[0].porcentajeIgv) : 18;
    return {
      title: fd.doc_type === "01" ? "FACTURA ELECTRÓNICA" : "BOLETA DE VENTA ELECTRÓNICA",
      number: `${series}-${corr}`,
      fiscal: true,
      env: fd.env as string,
      status: fd.status as string,
      issuer: {
        name: String(company.razonSocial ?? ""),
        trade: String(company.nombreComercial ?? ""),
        ruc: String(company.ruc ?? ""),
        address: [addr.direccion, [addr.distrito, addr.provincia, addr.departamento].filter((x) => x && x !== "-").join(" - ")].filter(Boolean).join(" · "),
        logoUrl,
      },
      client: {
        name: String(client.rznSocial ?? ""),
        docLabel: DOC_LABEL[tipoDoc] ?? "DOC.",
        doc: tipoDoc === "-" ? "" : String(client.numDoc ?? ""),
        address: String(((client.address ?? {}) as Record<string, unknown>).direccion ?? ""),
      },
      date: isoDate,
      currency: String(p.tipoMoneda ?? "PEN"),
      payment: fp.tipo === "Credito" ? `Crédito${cuotas.length ? ` · vence ${String(cuotas[0].fechaPago ?? "").slice(0, 10)}` : ""}` : "Contado",
      lines: details.map((d) => ({ qty: n(d.cantidad), unit: String(d.unidad ?? "NIU"), description: String(d.descripcion ?? ""), unitValue: n(d.mtoValorUnitario), amount: n(d.mtoValorVenta) })),
      totals: [
        ...(n(t.gravadas) > 0 ? [{ label: "Op. Gravada", value: n(t.gravadas) }] : []),
        ...(n(t.exoneradas) > 0 ? [{ label: "Op. Exonerada", value: n(t.exoneradas) }] : []),
        ...(n(t.inafectas) > 0 ? [{ label: "Op. Inafecta", value: n(t.inafectas) }] : []),
        { label: `IGV (${rate}%)`, value: igv },
        { label: "IMPORTE TOTAL", value: total, strong: true },
      ],
      legend: String(fd.legend ?? ""),
      hash: String(fd.hash ?? ""),
      // Anexo N.° 6 (Aspectos técnicos), num. 6.4 — 10 campos separados por "|" y corrección de errores nivel Q:
      // RUC|TIPO|SERIE|NÚMERO|IGV|TOTAL|FECHA|TIPO DOC ADQ.|NÚM. DOC ADQ.|VALOR RESUMEN (hash)
      qr: [company.ruc, fd.doc_type, series, corr, igv.toFixed(2), total.toFixed(2), isoDate, tipoDoc, client.numDoc ?? "", String(fd.hash ?? "")].join("|"),
      hasXml: !!fd.xml,
      hasCdr: !!fd.cdr,
    };
  }
  const items = ((inv.invoice_items ?? []) as { description: string; quantity: number | string; unit_price: number | string }[]).map((i) => ({ description: i.description, quantity: Number(i.quantity), unit_price: Number(i.unit_price) }));
  const tt = totalsOf(items, inv.tax_rate as number);
  const client = (Array.isArray(inv.clients) ? inv.clients[0] : inv.clients) as { name: string; tax_id: string | null; address: string | null } | null;
  return {
    title: "NOTA DE VENTA",
    number: inv.number as string,
    fiscal: false,
    env: "",
    status: inv.status as string,
    issuer: { name: org?.name ?? "", trade: org?.trade_name ?? "", ruc: org?.tax_id ?? "", address: org?.address ?? "", logoUrl },
    client: { name: client?.name ?? "", docLabel: "Documento", doc: client?.tax_id ?? "", address: client?.address ?? "" },
    date: inv.issue_date as string,
    currency: inv.currency as string,
    payment: inv.due_date ? `Crédito · vence ${inv.due_date}` : "Contado",
    lines: items.map((i) => ({ qty: i.quantity, unit: "", description: i.description, unitValue: i.unit_price, amount: Math.round(i.quantity * i.unit_price * 100) / 100 })),
    totals: [
      { label: "Subtotal", value: tt.subtotal },
      { label: `Impuesto (${Number(inv.tax_rate)}%)`, value: tt.tax },
      { label: "TOTAL", value: tt.total, strong: true },
    ],
    legend: amountLegend(tt.total, (inv.currency as string) === "USD" ? "USD" : "PEN"),
    hash: "",
    qr: null,
    hasXml: false,
    hasCdr: false,
  };
}
