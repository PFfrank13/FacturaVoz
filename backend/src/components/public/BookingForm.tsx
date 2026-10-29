"use client";

import { useMemo, useState } from "react";

/** Reserva de cita: servicio, día y hora (bloques de 30 min), nombre y celular. */
export default function BookingForm({ slug, business, services, hours, whatsapp }: { slug: string; business: string; services: string[]; hours: string; whatsapp: string }) {
  const days = useMemo(() => {
    const out: { iso: string; label: string }[] = [];
    const fmt = new Intl.DateTimeFormat("es-PE", { timeZone: "America/Lima", weekday: "short", day: "2-digit", month: "short" });
    const iso = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" });
    for (let i = 0; i < 14; i++) {
      const d = new Date(Date.now() + i * 864e5);
      out.push({ iso: iso.format(d), label: i === 0 ? "Hoy" : i === 1 ? "Mañana" : fmt.format(d) });
    }
    return out;
  }, []);
  const slots = useMemo(() => {
    const out: string[] = [];
    for (let h = 8; h <= 20; h++) for (const m of [0, 30]) out.push(`${String(h).padStart(2, "0")}:${m === 0 ? "00" : "30"}`);
    return out;
  }, []);
  const [service, setService] = useState(services[0] ?? "Cita");
  const [day, setDay] = useState(days[0].iso);
  const [time, setTime] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [note, setNote] = useState("");
  const [state, setState] = useState<"idle" | "busy" | "done">("idle");
  const [error, setError] = useState("");

  async function send() {
    setError("");
    if (!time) return setError("Elige una hora");
    setState("busy");
    const at = `${day}T${time}:00-05:00`;
    const r = await fetch("/api/public/book", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ slug, service, at, name, phone, note }) }).catch(() => null);
    const j = (await r?.json().catch(() => ({}))) as { error?: string };
    if (r?.ok) setState("done");
    else {
      setState("idle");
      setError(j?.error ?? "No se pudo reservar");
    }
  }
  if (state === "done") {
    const text = encodeURIComponent(`Hola ${business}, reservé ${service} para el ${day} a las ${time}. Soy ${name}.`);
    return (
      <div className="py-6 text-center">
        <p className="text-5xl">📅</p>
        <p className="mt-3 text-lg font-bold">¡Reserva enviada!</p>
        <p className="mt-1 text-sm text-[#77799b]">{business} te confirmará por WhatsApp.</p>
        {whatsapp ? <a className="mt-5 inline-block rounded-2xl bg-[#25d366] px-5 py-3 font-semibold text-white" href={`https://wa.me/51${whatsapp}?text=${text}`}>Escribir por WhatsApp</a> : null}
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {services.length > 1 ? (
        <div className="flex flex-wrap gap-2">
          {services.map((s) => (
            <button key={s} type="button" onClick={() => setService(s)} className={`rounded-full px-4 py-2 text-sm font-semibold ${service === s ? "bg-[#6a62e2] text-white" : "bg-[#f3f1fc] text-[#26254b]"}`}>{s}</button>
          ))}
        </div>
      ) : null}
      <div className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
        {days.map((d) => (
          <button key={d.iso} type="button" onClick={() => setDay(d.iso)} className={`shrink-0 rounded-2xl px-4 py-3 text-sm font-semibold ${day === d.iso ? "bg-[#6a62e2] text-white" : "bg-[#f3f1fc]"}`}>{d.label}</button>
        ))}
      </div>
      {hours ? <p className="text-[13px] text-[#77799b]">Horario: {hours}</p> : null}
      <div className="grid grid-cols-4 gap-2">
        {slots.map((s) => (
          <button key={s} type="button" onClick={() => setTime(s)} className={`rounded-xl py-2 text-sm tabular-nums ${time === s ? "bg-[#6a62e2] text-white" : "bg-[#f3f1fc]"}`}>{s}</button>
        ))}
      </div>
      <input value={name} onChange={(e) => setName(e.target.value.slice(0, 120))} placeholder="Tu nombre" className="w-full rounded-2xl border border-[#ece9f7] p-3 text-[15px]" />
      <input value={phone} onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 9))} inputMode="numeric" placeholder="Celular (9 dígitos)" className="w-full rounded-2xl border border-[#ece9f7] p-3 text-[15px]" />
      <input value={note} onChange={(e) => setNote(e.target.value.slice(0, 300))} placeholder="Comentario (opcional)" className="w-full rounded-2xl border border-[#ece9f7] p-3 text-[15px]" />
      {error ? <p className="text-sm text-[#d94a5e]">{error}</p> : null}
      <button type="button" disabled={state === "busy"} onClick={send} className="w-full rounded-2xl bg-[#6a62e2] py-4 text-[16px] font-semibold text-white disabled:opacity-50">{state === "busy" ? "Reservando…" : "Reservar"}</button>
    </div>
  );
}
