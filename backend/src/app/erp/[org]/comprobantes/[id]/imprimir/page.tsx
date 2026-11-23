import { notFound } from "next/navigation";
import ReceiptPrint from "@/components/print/ReceiptPrint";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed } from "@/lib/erp/access";
import { buildPrintDoc } from "@/lib/publicdocs";
import "./print.css";

export const dynamic = "force-dynamic";

/**
 * The same printable receipt the customer portal shows (SUNAT QR, hash, test warnings), read with the
 * signed-in user's session so RLS decides what they may see. A4 by default, `?formato=ticket` (80 mm) or `58`.
 */
export default async function PrintReceipt({ params, searchParams }: { params: Promise<{ org: string; id: string }>; searchParams: Promise<{ formato?: string }> }) {
  const { org, id } = await params;
  const formato = (await searchParams).formato;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "comprobantes")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) notFound();
  const owned = await c.db.from("invoices").select("id").eq("org_id", org).eq("id", id).maybeSingle();
  if (!owned.data) notFound();
  const signLogo = async (path: string | null | undefined) => {
    if (!path) return null;
    const { data } = await c.db.storage.from("org-media").createSignedUrl(path, 3600);
    return data?.signedUrl ?? null;
  };
  const doc = await buildPrintDoc(c.db, id, signLogo).catch(() => null);
  if (!doc) notFound();
  const paper = formato === "ticket" || formato === "80" ? "80" : formato === "58" ? "58" : "a4";
  const base = `/erp/${org}/comprobantes/${id}`;
  const link = "rounded-2xl bg-[#eef2ff] px-5 py-3 text-[15px] font-semibold text-[#1e3a8a]";
  return <div className="fv-print-frame">
    <ReceiptPrint
      doc={doc}
      paper={paper}
      downloads={doc.hasXml ? { xml: `${base}/archivo?k=xml`, cdr: doc.hasCdr ? `${base}/archivo?k=cdr` : undefined } : undefined}
      actions={<>
        <a className={link} href={paper === "a4" ? "?formato=ticket" : "?"}>{paper === "a4" ? "Ticket 80 mm" : "Ver en A4"}</a>
        {paper !== "58" && <a className={link} href="?formato=58">Ticket 58 mm</a>}
        <a className={link} href={`/erp/${org}/comprobantes`}>Volver a comprobantes</a>
      </>}
    />
  </div>;
}
