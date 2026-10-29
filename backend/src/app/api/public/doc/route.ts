import { NextResponse } from "next/server";
import { getPortal } from "@/lib/publicdocs";
import { createAdminClient } from "@/lib/supabase/admin";

export const maxDuration = 15;

/** Descarga del XML firmado o del CDR (constancia de SUNAT) desde el portal del cliente final. */
export async function GET(req: Request) {
  const u = new URL(req.url);
  const token = u.searchParams.get("t") ?? "";
  const invoiceId = u.searchParams.get("i") ?? "";
  const kind = u.searchParams.get("k") === "cdr" ? "cdr" : "xml";
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return NextResponse.json({ error: "No disponible" }, { status: 503 });
  const portal = await getPortal(token).catch(() => null);
  if (!portal || !portal.history.some((h) => h.id === invoiceId)) return NextResponse.json({ error: "No encontrado" }, { status: 404 });
  const { data } = await createAdminClient().from("fiscal_documents").select("series, correlative, xml, cdr, org_id, status").eq("invoice_id", invoiceId).maybeSingle();
  if (!data || data.status !== "accepted") return NextResponse.json({ error: "No disponible" }, { status: 404 });
  const name = `${portal.org.ruc || "comprobante"}-${data.series}-${String(data.correlative).padStart(8, "0")}`;
  const headers = { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" };
  if (kind === "xml") {
    const xml = String(data.xml ?? "");
    if (!xml) return NextResponse.json({ error: "Sin XML" }, { status: 404 });
    return new NextResponse(xml, { headers: { ...headers, "Content-Type": "application/xml; charset=utf-8", "Content-Disposition": `attachment; filename="${name}.xml"` } });
  }
  const cdr = String(data.cdr ?? "");
  if (!cdr) return NextResponse.json({ error: "Sin CDR" }, { status: 404 });
  // Lycet/Greenter entregan el CDR como ZIP en base64.
  return new NextResponse(Buffer.from(cdr, "base64"), { headers: { ...headers, "Content-Type": "application/zip", "Content-Disposition": `attachment; filename="R-${name}.zip"` } });
}
