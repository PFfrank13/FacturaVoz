import { NextResponse } from "next/server";
import { workspaceContext } from "@/lib/erp/context";
import { can, modules, moduleAllowed } from "@/lib/erp/access";
import { purchasesRegister, salesRegister, toCsv, type PurchaseReg, type SaleReg } from "@/lib/erp/registers";

export const dynamic = "force-dynamic";

const isDate = (v: string | null): v is string => !!v && /^\d{4}-\d{2}-\d{2}$/.test(v) && new Date(`${v}T12:00:00Z`).toISOString().slice(0, 10) === v;
const one = <T,>(v: T | T[] | null | undefined): T | null => (Array.isArray(v) ? v[0] : v) ?? null;

/** CSV of the sales or purchase register of a period, read with the user's session (RLS) and finance rights. */
export async function GET(req: Request, { params }: { params: Promise<{ org: string }> }) {
  const { org } = await params;
  const url = new URL(req.url);
  const tipo = url.searchParams.get("tipo") === "compras" ? "compras" : "ventas";
  const from = url.searchParams.get("from"), to = url.searchParams.get("to");
  if (!isDate(from) || !isDate(to) || from > to || Date.parse(to) - Date.parse(from) > 366 * 86400000) return NextResponse.json({ error: "Periodo no válido" }, { status: 400 });
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "reportes")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector) || !can(c.access, "finance")) return NextResponse.json({ error: "Sin acceso" }, { status: 403 });
  let rows: unknown[][];
  if (tipo === "ventas") {
    const { data, error } = await c.db.from("invoices")
      .select("issue_date,doc_kind,voided_at,currency,amt_base,amt_tax,amt_total,number,client:clients(name,tax_id,doc_type),fiscal:fiscal_documents(doc_type,series,correlative,status,totals)")
      .eq("org_id", org).gte("issue_date", from).lte("issue_date", to).neq("status", "draft").order("issue_date").limit(20000);
    if (error) return NextResponse.json({ error: "No se pudo leer" }, { status: 500 });
    rows = salesRegister(((data ?? []) as unknown as (Omit<SaleReg, "client" | "fiscal"> & { client: unknown; fiscal: unknown })[])
      .map(r => ({ ...r, client: one(r.client as SaleReg["client"]), fiscal: one(r.fiscal as SaleReg["fiscal"]) })));
  } else {
    const { data, error } = await c.db.from("expenses").select("spent_on,supplier_name,supplier_tax_id,doc_number,total,tax,currency,category")
      .eq("org_id", org).gte("spent_on", from).lte("spent_on", to).order("spent_on").limit(20000);
    if (error) return NextResponse.json({ error: "No se pudo leer" }, { status: 500 });
    rows = purchasesRegister((data ?? []) as PurchaseReg[]);
  }
  return new NextResponse(toCsv(rows), {
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="registro-${tipo}-${from}-a-${to}.csv"`,
      "cache-control": "no-store",
    },
  });
}
