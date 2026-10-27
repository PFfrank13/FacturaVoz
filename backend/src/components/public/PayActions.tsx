"use client";

import { useState } from "react";

type Props = {
  token: string;
  balance: number;
  currencySymbol: string;
  pay: { yape: string; plin: string; bankName: string; bankAccount: string; bankCci: string; holder: string; note: string; mp: boolean };
};

function CopyRow({ label, value, display }: { label: string; value: string; display?: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      type="button"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(value);
          setDone(true);
          setTimeout(() => setDone(false), 1600);
        } catch {
          /* el usuario puede copiar a mano */
        }
      }}
      className="flex w-full items-center justify-between rounded-2xl bg-[#f3f1fc] px-4 py-3 text-left transition active:scale-[0.98]"
    >
      <span>
        <span className="block text-[12.5px] text-[#77799b]">{label}</span>
        <span className="block text-[16px] font-semibold tabular-nums tracking-wide">{display ?? value}</span>
      </span>
      <span className={`text-[13px] font-semibold ${done ? "text-[#23956f]" : "text-[#6a62e2]"}`}>{done ? "¡Copiado!" : "Copiar"}</span>
    </button>
  );
}

const fmtPhone = (p: string) => `${p.slice(0, 3)} ${p.slice(3, 6)} ${p.slice(6)}`;

/** Medios de pago + "Ya pagué" (cliente final). */
export default function PayActions({ token, balance, currencySymbol, pay }: Props) {
  const [claimOpen, setClaimOpen] = useState(false);
  const [amount, setAmount] = useState(balance.toFixed(2));
  const [method, setMethod] = useState(pay.yape ? "yape" : pay.plin ? "plin" : "transferencia");
  const [op, setOp] = useState("");
  const [payer, setPayer] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [sent, setSent] = useState(false);

  async function post(path: string, body: unknown) {
    const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const data = (await res.json().catch(() => ({}))) as { error?: string; url?: string };
    if (!res.ok) throw new Error(data.error ?? "No se pudo completar");
    return data;
  }

  async function card() {
    setBusy(true);
    setError("");
    try {
      const d = await post("/api/public/mp", { token });
      if (d.url) window.location.href = d.url;
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo abrir el pago");
      setBusy(false);
    }
  }

  async function claim() {
    setBusy(true);
    setError("");
    try {
      await post("/api/public/claim", { token, amount, method, operation_code: op, payer_name: payer });
      setSent(true);
      setClaimOpen(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo registrar");
    } finally {
      setBusy(false);
    }
  }

  const input = "w-full rounded-2xl border border-[#ece9f7] bg-white px-4 py-3 text-[15px] outline-none focus:border-[#6a62e2] focus:ring-2 focus:ring-[#6a62e2]/20";
  const hasTransfer = pay.bankAccount || pay.bankCci;
  return (
    <div className="mt-6 space-y-3">
      <p className="text-[13px] font-semibold uppercase tracking-wider text-[#77799b]">Cómo pagar</p>
      {pay.mp ? (
        <button
          disabled={busy}
          onClick={card}
          className="w-full rounded-2xl bg-gradient-to-br from-[#6a62e2] to-[#b58bf5] py-4 text-base font-semibold text-white shadow-lg shadow-[#6a62e2]/30 transition active:scale-[0.98] disabled:opacity-60"
        >
          💳 Pagar {currencySymbol} {balance.toFixed(2)} con tarjeta
        </button>
      ) : null}
      {pay.yape ? <CopyRow label={`Yape${pay.holder ? ` · ${pay.holder}` : ""}`} value={pay.yape} display={fmtPhone(pay.yape)} /> : null}
      {pay.plin ? <CopyRow label={`Plin${pay.holder ? ` · ${pay.holder}` : ""}`} value={pay.plin} display={fmtPhone(pay.plin)} /> : null}
      {pay.bankAccount ? <CopyRow label={`${pay.bankName || "Cuenta"}${pay.holder ? ` · ${pay.holder}` : ""}`} value={pay.bankAccount} /> : null}
      {pay.bankCci ? <CopyRow label="CCI (interbancario)" value={pay.bankCci} /> : null}
      {pay.note ? <p className="rounded-2xl bg-[#c57a12]/10 px-4 py-3 text-[13.5px] text-[#8a5a10]">{pay.note}</p> : null}
      {!pay.mp && !pay.yape && !pay.plin && !hasTransfer ? (
        <p className="text-sm text-[#77799b]">Coordina el pago directamente con el negocio.</p>
      ) : null}

      {sent ? (
        <div className="rounded-2xl bg-[#23956f]/10 p-4 text-center">
          <p className="font-bold text-[#23956f]">¡Gracias! Avisamos al negocio</p>
          <p className="mt-1 text-sm text-[#55577a]">Lo confirmará en cuanto verifique el pago.</p>
        </div>
      ) : claimOpen ? (
        <div className="space-y-3 rounded-2xl border border-[#ece9f7] p-4">
          <p className="text-[15px] font-semibold">Avisa que ya pagaste</p>
          <div className="flex flex-wrap gap-2">
            {(["yape", "plin", "transferencia", "otro"] as const).map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => setMethod(m)}
                className={`rounded-xl px-3 py-2 text-sm font-semibold capitalize ${method === m ? "bg-[#6a62e2] text-white" : "bg-[#f3f1fc] text-[#55577a]"}`}
              >
                {m}
              </button>
            ))}
          </div>
          <input className={input} inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="Monto pagado" />
          <input className={input} value={op} maxLength={40} onChange={(e) => setOp(e.target.value)} placeholder="N.º de operación (opcional)" />
          <input className={input} value={payer} maxLength={120} onChange={(e) => setPayer(e.target.value)} placeholder="Tu nombre (opcional)" />
          <div className="flex gap-2">
            <button onClick={() => setClaimOpen(false)} className="flex-1 rounded-2xl border border-[#ece9f7] py-3 font-semibold text-[#77799b]">
              Cancelar
            </button>
            <button disabled={busy} onClick={claim} className="flex-1 rounded-2xl bg-[#6a62e2] py-3 font-semibold text-white disabled:opacity-50">
              {busy ? "Enviando…" : "Enviar aviso"}
            </button>
          </div>
        </div>
      ) : (
        <button onClick={() => setClaimOpen(true)} className="w-full rounded-2xl border border-[#ece9f7] py-3.5 text-[15px] font-semibold text-[#6a62e2] transition active:scale-[0.98]">
          Ya pagué por Yape, Plin o transferencia
        </button>
      )}
      {error ? <p className="text-center text-sm font-medium text-[#d94a5e]">{error}</p> : null}
    </div>
  );
}
