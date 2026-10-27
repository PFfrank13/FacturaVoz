"use client";

import { useState } from "react";

type Props = { token: string; initialStatus: string; expired: boolean };

/** Aceptar / rechazar la cotización (cliente final). */
export default function QuoteActions({ token, initialStatus, expired }: Props) {
  const [status, setStatus] = useState(initialStatus);
  const [mode, setMode] = useState<"idle" | "accept" | "reject">("idle");
  const [name, setName] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function send(action: "accept" | "reject") {
    setBusy(true);
    setError("");
    try {
      const res = await fetch("/api/public/quote", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, action, name, note }),
      });
      const data = (await res.json().catch(() => ({}))) as { status?: string; error?: string };
      if (!res.ok) throw new Error(data.error ?? "No se pudo enviar tu respuesta");
      setStatus(data.status ?? status);
      setMode("idle");
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo enviar tu respuesta");
    } finally {
      setBusy(false);
    }
  }

  if (status === "accepted" || status === "converted") {
    return (
      <div className="mt-6 rounded-2xl bg-[#23956f]/10 p-5 text-center">
        <p className="text-3xl">🎉</p>
        <p className="mt-2 text-lg font-bold text-[#23956f]">Cotización aceptada</p>
        <p className="mt-1 text-sm text-[#55577a]">Gracias. El negocio ya fue avisado y te enviará tu comprobante.</p>
      </div>
    );
  }
  if (status === "rejected") {
    return (
      <div className="mt-6 rounded-2xl bg-[#d94a5e]/10 p-5 text-center">
        <p className="text-lg font-bold text-[#d94a5e]">Cotización rechazada</p>
        <p className="mt-1 text-sm text-[#55577a]">Registramos tu respuesta. Si cambias de opinión, pide una nueva cotización.</p>
      </div>
    );
  }
  if (expired) {
    return <p className="mt-6 rounded-2xl bg-[#c57a12]/10 p-4 text-center text-sm font-medium text-[#c57a12]">Esta cotización venció. Pide una actualizada al negocio.</p>;
  }

  const input = "w-full rounded-2xl border border-[#ece9f7] bg-white px-4 py-3 text-[15px] outline-none focus:border-[#6a62e2] focus:ring-2 focus:ring-[#6a62e2]/20";
  return (
    <div className="mt-6 space-y-3">
      {mode === "idle" ? (
        <>
          <button
            onClick={() => setMode("accept")}
            className="w-full rounded-2xl bg-gradient-to-br from-[#6a62e2] to-[#b58bf5] py-4 text-base font-semibold text-white shadow-lg shadow-[#6a62e2]/30 transition active:scale-[0.98]"
          >
            ✓ Aceptar cotización
          </button>
          <button onClick={() => setMode("reject")} className="w-full rounded-2xl border border-[#ece9f7] py-3.5 text-[15px] font-semibold text-[#77799b] transition active:scale-[0.98]">
            No, gracias
          </button>
        </>
      ) : (
        <div className="space-y-3 rounded-2xl bg-[#f3f1fc] p-4">
          <p className="text-[15px] font-semibold">{mode === "accept" ? "Confirma tu aceptación" : "¿Nos cuentas por qué? (opcional)"}</p>
          {mode === "accept" ? (
            <input className={input} placeholder="Tu nombre" value={name} maxLength={120} onChange={(e) => setName(e.target.value)} autoFocus />
          ) : null}
          <textarea className={input} rows={2} placeholder={mode === "accept" ? "Comentario (opcional)" : "Motivo (opcional)"} value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
          <div className="flex gap-2">
            <button onClick={() => setMode("idle")} className="flex-1 rounded-2xl border border-[#ece9f7] bg-white py-3 font-semibold text-[#77799b]">
              Volver
            </button>
            <button
              disabled={busy || (mode === "accept" && name.trim().length < 3)}
              onClick={() => send(mode === "accept" ? "accept" : "reject")}
              className={`flex-1 rounded-2xl py-3 font-semibold text-white disabled:opacity-50 ${mode === "accept" ? "bg-[#6a62e2]" : "bg-[#d94a5e]"}`}
            >
              {busy ? "Enviando…" : mode === "accept" ? "Aceptar" : "Rechazar"}
            </button>
          </div>
        </div>
      )}
      {error ? <p className="text-center text-sm font-medium text-[#d94a5e]">{error}</p> : null}
    </div>
  );
}
