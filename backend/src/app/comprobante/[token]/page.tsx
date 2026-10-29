import type { Metadata } from "next";
import PrintButton from "@/components/public/PrintButton";
import { NotFoundCard } from "@/components/public/Shell";
import { fmtDate, fmtMoney } from "@/lib/publicbase";
import { getPortal, getPrintDoc } from "@/lib/publicdocs";
import { qrSvg } from "@/lib/qr";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Comprobante", robots: { index: false, follow: false } };

const qty = (q: number) => (Number.isInteger(q) ? String(q) : q.toFixed(2));

/**
 * Representación impresa para el cliente final: A4 (por defecto) o ticket de 80/58 mm (?f=80 | ?f=58).
 * Imprimir o "Guardar como PDF" lo hace el navegador. Incluye QR (formato SUNAT, corrección Q) y valor resumen (hash).
 */
export default async function DocPage({ params, searchParams }: { params: Promise<{ token: string }>; searchParams: Promise<{ i?: string; f?: string }> }) {
  const { token } = await params;
  const sp = await searchParams;
  const portal = await getPortal(token).catch(() => null);
  if (!portal) return <NotFoundCard text="Este enlace no existe o fue retirado por el negocio." />;
  const doc = await getPrintDoc(portal, typeof sp.i === "string" ? sp.i : portal.invoiceId).catch(() => null);
  if (!doc) return <NotFoundCard text="No encontramos ese comprobante." />;
  const ticket = sp.f === "80" || sp.f === "58";
  const width = sp.f === "58" ? "58mm" : "80mm";
  const money = (v: number) => fmtMoney(v, doc.currency);
  const qr = doc.qr ? qrSvg(doc.qr, { scale: ticket ? 3 : 4 }) : null;
  const warn = doc.fiscal && doc.env === "beta" ? "DOCUMENTO DE PRUEBA (SUNAT BETA) — SIN VALIDEZ TRIBUTARIA" : doc.fiscal && doc.status !== "accepted" ? "COMPROBANTE AÚN NO CONFIRMADO POR SUNAT" : !doc.fiscal ? "DOCUMENTO SIN VALIDEZ TRIBUTARIA" : "";
  const legal = doc.fiscal ? `Representación impresa de la ${doc.title === "FACTURA ELECTRÓNICA" ? "Factura Electrónica" : "Boleta de Venta Electrónica"}. Consulte su validez en www.sunat.gob.pe` : "Nota de venta interna.";

  if (ticket) {
    return (
      <main className="bg-white p-2 font-mono text-[11px] leading-snug text-black">
        <style>{`@page{size:${width} auto;margin:2mm}@media print{.no-print{display:none}}`}</style>
        <div style={{ width, margin: "0 auto" }}>
          {doc.issuer.logoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={doc.issuer.logoUrl} alt="" style={{ display: "block", margin: "0 auto 4px", maxHeight: 60, maxWidth: "70%", filter: "grayscale(1) contrast(1.4)" }} />
          ) : null}
          <p className="text-center font-bold">{doc.issuer.trade || doc.issuer.name}</p>
          {doc.issuer.trade && doc.issuer.trade !== doc.issuer.name ? <p className="text-center">{doc.issuer.name}</p> : null}
          {doc.issuer.ruc ? <p className="text-center">RUC {doc.issuer.ruc}</p> : null}
          {doc.issuer.address ? <p className="text-center">{doc.issuer.address}</p> : null}
          <hr className="my-1 border-dashed border-black" />
          <p className="text-center font-bold">{doc.title}</p>
          <p className="text-center font-bold">{doc.number}</p>
          {warn ? <p className="text-center font-bold">{warn}</p> : null}
          <hr className="my-1 border-dashed border-black" />
          <p>Fecha: {fmtDate(doc.date)}</p>
          <p>Cliente: {doc.client.name}</p>
          {doc.client.doc ? <p>{doc.client.docLabel}: {doc.client.doc}</p> : null}
          <p>Pago: {doc.payment}</p>
          <hr className="my-1 border-dashed border-black" />
          {doc.lines.map((l, k) => (
            <div key={k}>
              <p>{l.description}</p>
              <p className="flex justify-between"><span>{qty(l.qty)} x {l.unitValue.toFixed(2)}</span><span>{l.amount.toFixed(2)}</span></p>
            </div>
          ))}
          <hr className="my-1 border-dashed border-black" />
          {doc.totals.map((t) => (
            <p key={t.label} className={`flex justify-between ${t.strong ? "font-bold" : ""}`}><span>{t.label}</span><span>{money(t.value)}</span></p>
          ))}
          {doc.legend ? <p className="mt-1">{doc.legend}</p> : null}
          {qr ? <div className="mt-2 flex justify-center" dangerouslySetInnerHTML={{ __html: qr }} /> : null}
          {doc.hash ? <p className="mt-1 break-all text-center">Valor resumen: {doc.hash}</p> : null}
          <p className="mt-1 text-center">{legal}</p>
          <div className="mt-4 text-center"><PrintButton label="Imprimir ticket" /></div>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f3f4f6] p-4 text-[#111827] print:bg-white print:p-0">
      <style>{`@page{size:A4;margin:14mm}@media print{.no-print{display:none}}`}</style>
      <div className="mx-auto max-w-[800px] rounded-xl bg-white p-8 shadow print:shadow-none">
        {warn ? <p className="mb-3 rounded bg-[#b45309] py-1 text-center text-[12px] font-bold text-white">{warn}</p> : null}
        <div className="flex items-start justify-between gap-6">
          <div className="flex items-start gap-4">
            {doc.issuer.logoUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={doc.issuer.logoUrl} alt="" className="h-16 w-auto max-w-[160px] object-contain" />
            ) : null}
            <div>
              <p className="text-[18px] font-bold text-[#1e3a8a]">{doc.issuer.name}</p>
              {doc.issuer.trade && doc.issuer.trade !== doc.issuer.name ? <p className="text-[13px]">{doc.issuer.trade}</p> : null}
              <p className="text-[12px] text-[#6b7280]">{doc.issuer.address}</p>
            </div>
          </div>
          <div className="min-w-[220px] rounded border-2 border-[#1e3a8a] p-3 text-center">
            {doc.issuer.ruc ? <p className="font-bold">R.U.C. {doc.issuer.ruc}</p> : null}
            <p className="font-bold text-[#1e3a8a]">{doc.title}</p>
            <p className="text-[17px] font-bold">{doc.number}</p>
          </div>
        </div>
        <div className="mt-5 grid grid-cols-[130px_1fr] gap-y-1 rounded bg-[#f3f4f6] p-3 text-[13px]">
          <span className="text-[#6b7280]">Señor(es)</span><b>{doc.client.name}</b>
          {doc.client.doc ? (<><span className="text-[#6b7280]">{doc.client.docLabel}</span><b>{doc.client.doc}</b></>) : null}
          {doc.client.address ? (<><span className="text-[#6b7280]">Dirección</span><b>{doc.client.address}</b></>) : null}
          <span className="text-[#6b7280]">Fecha de emisión</span><b>{fmtDate(doc.date)}</b>
          <span className="text-[#6b7280]">Moneda</span><b>{doc.currency === "USD" ? "DÓLARES AMERICANOS (USD)" : "SOLES (PEN)"}</b>
          <span className="text-[#6b7280]">Forma de pago</span><b>{doc.payment}</b>
        </div>
        <table className="mt-4 w-full text-[13px]">
          <thead><tr className="bg-[#1e3a8a] text-left text-white"><th className="p-2">Cant.</th><th className="p-2">Unid.</th><th className="p-2">Descripción</th><th className="p-2 text-right">V. Unit.</th><th className="p-2 text-right">Importe</th></tr></thead>
          <tbody>
            {doc.lines.map((l, k) => (
              <tr key={k} className="border-b border-[#e5e7eb]"><td className="p-2">{qty(l.qty)}</td><td className="p-2">{l.unit}</td><td className="p-2">{l.description}</td><td className="p-2 text-right">{money(l.unitValue)}</td><td className="p-2 text-right">{money(l.amount)}</td></tr>
            ))}
          </tbody>
        </table>
        <div className="mt-4 flex justify-between gap-6">
          <p className="max-w-[60%] text-[13px] font-bold">{doc.legend}</p>
          <div className="w-[240px] text-[13px]">
            {doc.totals.map((t) => (
              <p key={t.label} className={`flex justify-between py-0.5 ${t.strong ? "text-[15px] font-bold" : "text-[#6b7280]"}`}><span>{t.label}</span><span className="text-[#111827]">{money(t.value)}</span></p>
            ))}
          </div>
        </div>
        <div className="mt-6 flex items-start gap-4 border-t border-[#e5e7eb] pt-4">
          {qr ? <div dangerouslySetInnerHTML={{ __html: qr }} /> : null}
          <div className="text-[12px] text-[#6b7280]">
            {doc.hash ? <p>Valor resumen (hash): {doc.hash}</p> : null}
            <p className="mt-1">{legal}</p>
            {doc.hasXml ? <p className="no-print mt-2"><a className="text-[#6a62e2] underline" href={`/api/public/doc?t=${token}&i=${sp.i ?? portal.invoiceId}&k=xml`}>Descargar XML</a>{doc.hasCdr ? <> · <a className="text-[#6a62e2] underline" href={`/api/public/doc?t=${token}&i=${sp.i ?? portal.invoiceId}&k=cdr`}>Descargar CDR</a></> : null}</p> : null}
          </div>
        </div>
        <div className="no-print mt-6 flex flex-wrap gap-3"><PrintButton /><a className="rounded-2xl bg-[#f3f1fc] px-5 py-3 text-[15px] font-semibold text-[#6a62e2]" href={`/portal/${token}`}>Ver mis comprobantes</a></div>
      </div>
    </main>
  );
}
