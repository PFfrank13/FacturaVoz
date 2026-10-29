"use client";

import { useState } from "react";

/** Encuesta de satisfacción (1 a 5) + comentario. */
export default function SurveyForm({ token, business }: { token: string; business: string }) {
  const [score, setScore] = useState(0);
  const [comment, setComment] = useState("");
  const [state, setState] = useState<"idle" | "busy" | "done" | "error">("idle");
  const [msg, setMsg] = useState("");
  async function send() {
    if (score < 1) return;
    setState("busy");
    const r = await fetch("/api/public/survey", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, score, comment }) }).catch(() => null);
    const j = (await r?.json().catch(() => ({}))) as { error?: string };
    if (r?.ok) setState("done");
    else {
      setState("error");
      setMsg(j?.error ?? "No se pudo enviar");
    }
  }
  if (state === "done")
    return (
      <div className="py-8 text-center">
        <p className="text-5xl">💜</p>
        <p className="mt-3 text-lg font-bold">¡Gracias por tu opinión!</p>
        <p className="mt-1 text-sm text-[#77799b]">{business} la leerá para atenderte mejor.</p>
      </div>
    );
  return (
    <div>
      <p className="text-[15px]">¿Cómo te atendió {business}?</p>
      <div className="mt-4 flex justify-between">
        {[1, 2, 3, 4, 5].map((n) => (
          <button key={n} type="button" aria-label={`${n} de 5`} onClick={() => setScore(n)} className={`h-14 w-14 rounded-2xl text-2xl transition ${score >= n ? "scale-105 bg-[#ffd36e]" : "bg-[#f3f1fc]"}`}>
            ★
          </button>
        ))}
      </div>
      <textarea value={comment} onChange={(e) => setComment(e.target.value.slice(0, 500))} placeholder="¿Algo que debamos mejorar? (opcional)" className="mt-4 h-24 w-full rounded-2xl border border-[#ece9f7] p-3 text-[15px]" />
      {state === "error" ? <p className="mt-2 text-sm text-[#d94a5e]">{msg}</p> : null}
      <button type="button" disabled={score < 1 || state === "busy"} onClick={send} className="mt-4 w-full rounded-2xl bg-[#6a62e2] py-4 text-[16px] font-semibold text-white disabled:opacity-50">
        {state === "busy" ? "Enviando…" : "Enviar"}
      </button>
    </div>
  );
}
