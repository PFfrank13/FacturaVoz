import { NextResponse } from "next/server";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed } from "@/lib/erp/access";

/** Signed XML or SUNAT CDR of an accepted receipt, read with the user's RLS session. */
export async function GET(req: Request, { params }: { params: Promise<{ org: string; id: string }> }) {
  const { org, id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return NextResponse.json({ error: "No válido" }, { status: 400 });
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "comprobantes")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return NextResponse.json({ error: "Sin acceso" }, { status: 403 });
  const kind = new URL(req.url).searchParams.get("k") === "cdr" ? "cdr" : "xml";
  const inv = await c.db.from("invoices").select("id").eq("org_id", org).eq("id", id).maybeSingle();
  if (inv.error || !inv.data) return NextResponse.json({ error: "No encontrado" }, { status: 404 });
  const doc = await c.db.from("fiscal_documents").select("series,correlative,xml,cdr,status").eq("invoice_id", id).maybeSingle();
  if (doc.error || !doc.data || doc.data.status !== "accepted") return NextResponse.json({ error: "Aún no hay archivo de SUNAT" }, { status: 404 });
  const name = `${doc.data.series}-${String(doc.data.correlative).padStart(8, "0")}`;
  const headers = { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" };
  if (kind === "xml") {
    if (!doc.data.xml) return NextResponse.json({ error: "Sin XML" }, { status: 404 });
    return new NextResponse(String(doc.data.xml), { headers: { ...headers, "Content-Type": "application/xml; charset=utf-8", "Content-Disposition": `attachment; filename="${name}.xml"` } });
  }
  if (!doc.data.cdr) return NextResponse.json({ error: "Sin CDR" }, { status: 404 });
  return new NextResponse(Buffer.from(String(doc.data.cdr), "base64"), { headers: { ...headers, "Content-Type": "application/zip", "Content-Disposition": `attachment; filename="R-${name}.zip"` } });
}
