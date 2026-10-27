"use client";

import { useMemo, useState } from "react";
import type { PublicStore } from "@/lib/publicdata";

const SYMBOLS: Record<string, string> = { PEN: "S/", USD: "US$", EUR: "€" };
const fmt = (n: number, cur: string) => `${SYMBOLS[cur] ?? cur} ${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

type Done = { number: string; token: string; total: number; currency: string; business: string; whatsapp: string };

/** Tienda pública: catálogo + carrito + pedido (llega al negocio como cotización "Pedido web"). */
export default function StoreCart({ store }: { store: PublicStore }) {
  const [cart, setCart] = useState<Record<string, number>>({});
  const [q, setQ] = useState("");
  const [checkout, setCheckout] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState<Done | null>(null);

  const list = useMemo(() => {
    const s = q.trim().toLowerCase();
    return store.products.filter((p) => !s || p.name.toLowerCase().includes(s));
  }, [q, store.products]);

  const count = Object.values(cart).reduce((a, b) => a + b, 0);
  const total = Math.round(store.products.reduce((s, p) => s + (cart[p.id] ?? 0) * p.priceWithTax, 0) * 100) / 100;

  const add = (id: string, d: number) =>
    setCart((c) => {
      const v = Math.max(0, Math.min(999, (c[id] ?? 0) + d));
      const next = { ...c };
      if (v === 0) delete next[id];
      else next[id] = v;
      return next;
    });

  async function send() {
    setBusy(true);
    setError("");
    try {
      const res = await fetch("/api/public/order", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          slug: store.slug,
          name,
          phone,
          note,
          items: Object.entries(cart).map(([product_id, qty]) => ({ product_id, qty: String(qty) })),
        }),
      });
      const data = (await res.json().catch(() => ({}))) as Partial<Done> & { error?: string };
      if (!res.ok || !data.number) throw new Error(data.error ?? "No se pudo enviar el pedido");
      setDone(data as Done);
      setCart({});
      setCheckout(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo enviar el pedido");
    } finally {
      setBusy(false);
    }
  }

  const input = "w-full rounded-2xl border border-[#ece9f7] bg-white px-4 py-3 text-[15px] outline-none focus:border-[#6a62e2] focus:ring-2 focus:ring-[#6a62e2]/20";

  if (done) {
    const wa = done.whatsapp
      ? `https://wa.me/51${done.whatsapp}?text=${encodeURIComponent(`Hola ${done.business}, acabo de hacer el pedido ${done.number} por ${fmt(done.total, done.currency)}.`)}`
      : "";
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f8f6fd] p-5 text-[#26254b]">
        <div className="w-full max-w-md rounded-[28px] bg-white p-8 text-center shadow-[0_20px_60px_-20px_rgba(106,98,226,0.35)]">
          <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-[#6a62e2] to-[#b58bf5] text-4xl text-white">✓</div>
          <h1 className="mt-5 text-2xl font-bold">¡Pedido enviado!</h1>
          <p className="mt-2 text-[15px] text-[#55577a]">
            {done.business} recibió tu pedido <b>{done.number}</b> por <b>{fmt(done.total, done.currency)}</b> y te contactará para confirmarlo.
          </p>
          <div className="mt-6 space-y-3">
            {wa ? (
              <a href={wa} className="block w-full rounded-2xl bg-[#25D366] py-4 font-semibold text-white">
                Avisar por WhatsApp
              </a>
            ) : null}
            <a href={`/cotizacion/${done.token}`} className="block w-full rounded-2xl border border-[#ece9f7] py-3.5 font-semibold text-[#6a62e2]">
              Ver mi pedido
            </a>
            <button onClick={() => setDone(null)} className="w-full py-2 text-sm text-[#77799b]">
              Hacer otro pedido
            </button>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f8f6fd] pb-36 text-[#26254b]">
      <header className="bg-gradient-to-br from-[#6a62e2] via-[#8e7cf2] to-[#b58bf5] px-5 pb-16 pt-10 text-white">
        <div className="mx-auto max-w-2xl">
          <p className="text-[13px] font-medium opacity-85">Pedidos en línea</p>
          <h1 className="mt-1 text-[30px] font-bold leading-tight tracking-tight">{store.business}</h1>
          {store.headline ? <p className="mt-2 max-w-lg text-[15px] opacity-90">{store.headline}</p> : null}
        </div>
      </header>
      <div className="mx-auto -mt-10 max-w-2xl px-4">
        <input className={`${input} shadow-lg shadow-[#6a62e2]/10`} placeholder="Buscar producto" value={q} onChange={(e) => setQ(e.target.value)} />
        <ul className="mt-4 grid gap-3 sm:grid-cols-2">
          {list.map((p) => {
            const n = cart[p.id] ?? 0;
            return (
              <li key={p.id} className={`flex items-center gap-3 rounded-3xl bg-white p-4 shadow-[0_10px_30px_-18px_rgba(106,98,226,0.4)] transition ${n ? "ring-2 ring-[#6a62e2]/40" : ""}`}>
                <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-[#ebe9ff] text-xl">{p.service ? "🛠️" : "📦"}</div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[15px] font-semibold">{p.name}</p>
                  <p className="text-[14px] tabular-nums text-[#6a62e2]">{fmt(p.priceWithTax, store.currency)}</p>
                </div>
                {n === 0 ? (
                  <button onClick={() => add(p.id, 1)} className="rounded-2xl bg-[#6a62e2] px-4 py-2.5 text-sm font-semibold text-white transition active:scale-95">
                    Agregar
                  </button>
                ) : (
                  <div className="flex items-center gap-2">
                    <button onClick={() => add(p.id, -1)} aria-label="Quitar uno" className="h-9 w-9 rounded-xl bg-[#f3f1fc] text-lg font-bold text-[#6a62e2] active:scale-90">
                      −
                    </button>
                    <span className="w-6 text-center font-bold tabular-nums">{n}</span>
                    <button onClick={() => add(p.id, 1)} aria-label="Agregar uno" className="h-9 w-9 rounded-xl bg-[#6a62e2] text-lg font-bold text-white active:scale-90">
                      +
                    </button>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
        {list.length === 0 ? <p className="mt-10 text-center text-sm text-[#77799b]">No encontramos productos.</p> : null}
        <p className="mt-6 text-center text-xs text-[#8a8cab]">Precios con IGV · {store.taxId ? `RUC ${store.taxId} · ` : ""}Hecho con FacturaVoz</p>
      </div>

      {count > 0 && !checkout ? (
        <div className="fixed inset-x-0 bottom-0 p-4">
          <button
            onClick={() => setCheckout(true)}
            className="mx-auto flex w-full max-w-2xl items-center justify-between rounded-3xl bg-[#26254b] px-6 py-4 text-white shadow-2xl transition active:scale-[0.98]"
          >
            <span className="rounded-full bg-white/15 px-3 py-1 text-sm font-semibold">{count}</span>
            <span className="font-semibold">Hacer pedido</span>
            <span className="font-bold tabular-nums">{fmt(total, store.currency)}</span>
          </button>
        </div>
      ) : null}

      {checkout ? (
        <div className="fixed inset-0 z-10 flex items-end justify-center bg-black/40 sm:items-center" onClick={() => setCheckout(false)}>
          <div className="w-full max-w-md space-y-3 rounded-t-[28px] bg-white p-6 sm:rounded-[28px]" onClick={(e) => e.stopPropagation()}>
            <p className="text-xl font-bold">Tus datos</p>
            <p className="text-sm text-[#77799b]">
              {count} {count === 1 ? "producto" : "productos"} · <b className="text-[#26254b]">{fmt(total, store.currency)}</b>
            </p>
            <input className={input} placeholder="Tu nombre" value={name} maxLength={120} onChange={(e) => setName(e.target.value)} autoFocus />
            <input className={input} placeholder="Celular (9 dígitos)" inputMode="numeric" value={phone} maxLength={12} onChange={(e) => setPhone(e.target.value)} />
            <textarea className={input} rows={2} placeholder="Comentario: dirección, hora de entrega… (opcional)" value={note} maxLength={300} onChange={(e) => setNote(e.target.value)} />
            {error ? <p className="text-sm font-medium text-[#d94a5e]">{error}</p> : null}
            <button
              disabled={busy || name.trim().length < 2 || phone.replace(/\D/g, "").length < 9}
              onClick={send}
              className="w-full rounded-2xl bg-gradient-to-br from-[#6a62e2] to-[#b58bf5] py-4 font-semibold text-white disabled:opacity-50"
            >
              {busy ? "Enviando…" : "Enviar pedido"}
            </button>
            <p className="text-center text-xs text-[#8a8cab]">El negocio confirmará disponibilidad y forma de pago.</p>
          </div>
        </div>
      ) : null}
    </main>
  );
}
