import type { Metadata } from "next";
import QuoteActions from "@/components/public/QuoteActions";
import { Lines, NotFoundCard, PublicShell, TotalsBox } from "@/components/public/Shell";
import { fmtDate, fmtMoney } from "@/lib/publicbase";
import { getPublicQuote } from "@/lib/publicdata";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Cotización", robots: { index: false, follow: false } };

export default async function QuotePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const q = await getPublicQuote(token).catch(() => null);
  if (!q) return <NotFoundCard text="Esta cotización no existe o el enlace está incompleto. Pide al negocio que te lo reenvíe." />;
  const fmt = (n: number) => fmtMoney(n, q.currency);
  return (
    <PublicShell eyebrow={`Cotización de ${q.business || "tu proveedor"}`} title={q.number} subtitle={q.businessTaxId ? `RUC ${q.businessTaxId}` : undefined}>
      <div className="mb-4 flex flex-wrap gap-x-6 gap-y-1 text-[13.5px] text-[#77799b]">
        <span>
          Para <b className="text-[#26254b]">{q.client || "—"}</b>
        </span>
        <span>Emitida {fmtDate(q.issueDate)}</span>
        {q.validUntil ? <span className={q.expired ? "font-semibold text-[#c57a12]" : ""}>Válida hasta {fmtDate(q.validUntil)}</span> : null}
      </div>
      <Lines items={q.items} fmt={fmt} />
      <TotalsBox
        rows={[
          { label: "Subtotal", value: fmt(q.subtotal) },
          { label: `IGV (${q.taxRate % 1 === 0 ? q.taxRate.toFixed(0) : q.taxRate}%)`, value: fmt(q.tax) },
          { label: "Total", value: fmt(q.total), strong: true },
        ]}
      />
      {q.notes ? <p className="mt-4 text-sm text-[#55577a]">{q.notes}</p> : null}
      <QuoteActions token={token} initialStatus={q.status} expired={q.expired} />
    </PublicShell>
  );
}
