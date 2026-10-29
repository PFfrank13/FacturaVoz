import { apiAuth, apiJson, OPTIONS_API } from "@/lib/apikey";
import { totalsOf } from "@/lib/publicbase";

export const OPTIONS = OPTIONS_API;
export const maxDuration = 20;

type Row = {
  id: string;
  number: string;
  issue_date: string;
  due_date: string | null;
  status: string;
  currency: string;
  tax_rate: number | string;
  clients: { name: string; tax_id: string | null } | null;
  invoice_items: { description: string; quantity: number | string; unit_price: number | string }[];
  fiscal_documents: { doc_type: string; series: string; correlative: number; status: string } | { doc_type: string; series: string; correlative: number; status: string }[] | null;
  payments: { amount: number | string }[];
};

/** GET /api/v1/invoices?from=AAAA-MM-DD&to=AAAA-MM-DD&status=sent|paid|draft&limit=100 */
export async function GET(req: Request) {
  const ctx = await apiAuth(req, "invoices:read");
  if (ctx instanceof Response) return ctx;
  const u = new URL(req.url);
  const from = /^\d{4}-\d{2}-\d{2}$/.test(u.searchParams.get("from") ?? "") ? u.searchParams.get("from")! : "1900-01-01";
  const to = /^\d{4}-\d{2}-\d{2}$/.test(u.searchParams.get("to") ?? "") ? u.searchParams.get("to")! : "2999-12-31";
  const status = ["draft", "sent", "paid"].includes(u.searchParams.get("status") ?? "") ? u.searchParams.get("status")! : null;
  const limit = Math.min(Math.max(Number(u.searchParams.get("limit") ?? "100") || 100, 1), 500);
  let q = ctx.admin
    .from("invoices")
    .select("id, number, issue_date, due_date, status, currency, tax_rate, clients(name, tax_id), invoice_items(description, quantity, unit_price), fiscal_documents(doc_type, series, correlative, status), payments(amount)")
    .eq("org_id", ctx.orgId)
    .gte("issue_date", from)
    .lte("issue_date", to)
    .order("issue_date", { ascending: false })
    .limit(limit);
  if (status) q = q.eq("status", status);
  const { data, error } = await q;
  if (error) return apiJson({ error: "server_error" }, 500);
  return apiJson({
    data: ((data ?? []) as unknown as Row[]).map((r) => {
      const t = totalsOf(r.invoice_items, r.tax_rate);
      const fd = Array.isArray(r.fiscal_documents) ? r.fiscal_documents[0] : r.fiscal_documents;
      const paid = Math.round(r.payments.reduce((a, p) => a + Number(p.amount), 0) * 100) / 100;
      return {
        id: r.id,
        number: fd ? `${fd.series}-${String(fd.correlative).padStart(8, "0")}` : r.number,
        internal_number: r.number,
        sunat: fd ? { type: fd.doc_type === "01" ? "factura" : "boleta", status: fd.status } : null,
        issue_date: r.issue_date,
        due_date: r.due_date,
        status: r.status,
        currency: r.currency,
        client: r.clients ? { name: r.clients.name, tax_id: r.clients.tax_id } : null,
        items: r.invoice_items.map((i) => ({ description: i.description, quantity: Number(i.quantity), unit_price: Number(i.unit_price) })),
        ...t,
        paid,
        balance: Math.max(0, Math.round((t.total - paid) * 100) / 100),
      };
    }),
  });
}
