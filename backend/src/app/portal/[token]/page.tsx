import type { Metadata } from "next";
import { NotFoundCard, PublicShell } from "@/components/public/Shell";
import { fmtDate, fmtMoney } from "@/lib/publicbase";
import { getPortal } from "@/lib/publicdocs";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Mis comprobantes", robots: { index: false, follow: false } };

const STATUS: Record<string, string> = { accepted: "Aceptado por SUNAT", rejected: "Rechazado por SUNAT", pending: "En proceso", error: "En proceso" };

/** Portal del cliente final: sin cuenta, con el enlace o QR de su comprobante. */
export default async function PortalPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const p = await getPortal(token).catch(() => null);
  if (!p) return <NotFoundCard text="Este enlace no existe o fue retirado por el negocio." />;
  return (
    <PublicShell eyebrow={p.org.name} title={p.client ? `Hola, ${p.client.name.split(" ")[0]}` : "Tus comprobantes"} subtitle="Descarga tus comprobantes cuando quieras">
      {p.org.logoUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={p.org.logoUrl} alt={p.org.name} className="mb-4 h-14 w-auto object-contain" />
      ) : null}
      <p className="text-[13px] text-[#77799b]">
        {p.org.legalName}
        {p.org.ruc ? ` · RUC ${p.org.ruc}` : ""}
      </p>
      <ul className="mt-4 divide-y divide-[#ece9f7]">
        {p.history.map((h) => {
          const num = h.fiscal ? `${h.fiscal.series}-${String(h.fiscal.correlative).padStart(8, "0")}` : h.number;
          const balance = Math.max(0, Math.round((h.total - h.paid) * 100) / 100);
          return (
            <li key={h.id} className={`py-4 ${h.id === p.invoiceId ? "rounded-2xl bg-[#f3f1fc] px-3" : ""}`}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-semibold">{num}</p>
                  <p className="text-[13px] text-[#77799b]">
                    {fmtDate(h.issueDate)}
                    {h.fiscal ? ` · ${STATUS[h.fiscal.status] ?? h.fiscal.status}` : " · Nota de venta"}
                  </p>
                </div>
                <div className="text-right">
                  <p className="font-bold tabular-nums">{fmtMoney(h.total, h.currency)}</p>
                  {balance > 0.004 ? <p className="text-[12.5px] font-semibold text-[#d94a5e]">Debe {fmtMoney(balance, h.currency)}</p> : <p className="text-[12.5px] text-[#23956f]">Pagado</p>}
                </div>
              </div>
              <div className="mt-3 flex flex-wrap gap-2 text-[13px] font-semibold">
                <a className="rounded-xl bg-white px-3 py-2 text-[#6a62e2] shadow-sm" href={`/comprobante/${p.token}?i=${h.id}`}>Ver / PDF</a>
                <a className="rounded-xl bg-white px-3 py-2 text-[#6a62e2] shadow-sm" href={`/comprobante/${p.token}?i=${h.id}&f=80`}>Ticket</a>
                {h.fiscal?.status === "accepted" ? (
                  <>
                    <a className="rounded-xl bg-white px-3 py-2 text-[#6a62e2] shadow-sm" href={`/api/public/doc?t=${p.token}&i=${h.id}&k=xml`}>XML</a>
                    <a className="rounded-xl bg-white px-3 py-2 text-[#6a62e2] shadow-sm" href={`/api/public/doc?t=${p.token}&i=${h.id}&k=cdr`}>CDR</a>
                  </>
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
      <p className="mt-6 text-center text-[12px] text-[#8a8cab]">Puedes verificar cualquier comprobante electrónico en sunat.gob.pe con los datos de su código QR.</p>
    </PublicShell>
  );
}
