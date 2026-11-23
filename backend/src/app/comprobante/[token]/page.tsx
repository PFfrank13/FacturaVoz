import type { Metadata } from "next";
import ReceiptPrint from "@/components/print/ReceiptPrint";
import { NotFoundCard } from "@/components/public/Shell";
import { getPortal, getPrintDoc } from "@/lib/publicdocs";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Comprobante", robots: { index: false, follow: false } };

/**
 * Representación impresa para el cliente final: A4 (por defecto) o ticket de 80/58 mm (?f=80 | ?f=58).
 * Imprimir o "Guardar como PDF" lo hace el navegador. Incluye QR (formato SUNAT, corrección Q) y valor resumen (hash).
 */
export default async function DocPage({ params, searchParams }: { params: Promise<{ token: string }>; searchParams: Promise<{ i?: string; f?: string }> }) {
  const { token } = await params;
  const sp = await searchParams;
  const portal = await getPortal(token).catch(() => null);
  if (!portal) return <NotFoundCard text="Este enlace no existe o fue retirado por el negocio." />;
  const invoiceId = typeof sp.i === "string" ? sp.i : portal.invoiceId;
  const doc = await getPrintDoc(portal, invoiceId).catch(() => null);
  if (!doc) return <NotFoundCard text="No encontramos ese comprobante." />;
  const paper = sp.f === "80" || sp.f === "58" ? sp.f : "a4";
  const file = (k: "xml" | "cdr") => `/api/public/doc?t=${token}&i=${invoiceId}&k=${k}`;
  return (
    <ReceiptPrint
      doc={doc}
      paper={paper}
      downloads={paper === "a4" && doc.hasXml ? { xml: file("xml"), cdr: doc.hasCdr ? file("cdr") : undefined } : undefined}
      actions={paper === "a4" ? <a className="rounded-2xl bg-[#f3f1fc] px-5 py-3 text-[15px] font-semibold text-[#6a62e2]" href={`/portal/${token}`}>Ver mis comprobantes</a> : null}
    />
  );
}
