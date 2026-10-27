import type { Metadata } from "next";
import PayActions from "@/components/public/PayActions";
import { Lines, NotFoundCard, PublicShell, TotalsBox } from "@/components/public/Shell";
import { fmtDate, fmtMoney } from "@/lib/publicbase";
import { getPublicInvoice } from "@/lib/publicdata";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Pagar comprobante", robots: { index: false, follow: false } };

const SYMBOLS: Record<string, string> = { PEN: "S/", USD: "US$", EUR: "€" };

export default async function PayPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const inv = await getPublicInvoice(token).catch(() => null);
  if (!inv) return <NotFoundCard text="Este enlace de pago no existe o está incompleto. Pide al negocio que te lo reenvíe." />;
  const fmt = (n: number) => fmtMoney(n, inv.currency);
  return (
    <PublicShell eyebrow={`${inv.docLabel} · ${inv.business || "tu proveedor"}`} title={inv.number} subtitle={inv.businessTaxId ? `RUC ${inv.businessTaxId}` : undefined}>
      <div className="mb-4 flex flex-wrap gap-x-6 gap-y-1 text-[13.5px] text-[#77799b]">
        <span>
          Para <b className="text-[#26254b]">{inv.client || "—"}</b>
        </span>
        <span>Emitido {fmtDate(inv.issueDate)}</span>
        {inv.dueDate ? <span className={inv.overdue ? "font-semibold text-[#d94a5e]" : ""}>Vence {fmtDate(inv.dueDate)}</span> : null}
      </div>
      <Lines items={inv.items} fmt={fmt} />
      <TotalsBox
        rows={[
          { label: "Total", value: fmt(inv.total) },
          ...(inv.paid > 0 ? [{ label: "Pagado", value: fmt(inv.paid), tone: "ok" as const }] : []),
          { label: "Saldo pendiente", value: fmt(inv.balance), strong: true, tone: inv.balance > 0 ? ("bad" as const) : ("ok" as const) },
        ]}
      />
      {inv.payable ? (
        <PayActions token={token} balance={inv.balance} currencySymbol={SYMBOLS[inv.currency] ?? inv.currency} pay={inv.pay} />
      ) : (
        <div className="mt-6 rounded-2xl bg-[#23956f]/10 p-5 text-center">
          <p className="text-3xl">✅</p>
          <p className="mt-2 text-lg font-bold text-[#23956f]">{inv.balance <= 0.004 ? "¡Pagado! Gracias" : "Este comprobante no admite pagos"}</p>
        </div>
      )}
    </PublicShell>
  );
}
