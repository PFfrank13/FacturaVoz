"use client";

import { useEffect, useMemo, useState } from "react";
import type { PublicStore, StoreProduct } from "@/lib/publicdata";

const SYMBOLS: Record<string, string> = { PEN: "S/", USD: "US$", EUR: "€" };
const fmt = (n: number, cur: string) => `${SYMBOLS[cur] ?? cur} ${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

type Done = { number: string; token: string; total: number; currency: string; business: string; whatsapp: string };

/** Precio unitario con IGV según la cantidad (precio por mayor desde cierta cantidad). */
const unitPrice = (p: StoreProduct, qty: number) => (p.wholesalePrice != null && p.wholesaleMinQty != null && qty >= p.wholesaleMinQty ? p.wholesalePrice : p.priceWithTax);

/**
 * Tienda pública "al extremo": portada con logo, buscador, categorías, destacados, fotos, ficha de producto
 * compartible (/tienda/<slug>/p/<id>), carrito flotante, recojo/delivery o mesa (?mesa=4) y pedido por WhatsApp.
 * Los precios SIEMPRE los pone la base de datos al registrar el pedido (no el navegador).
 */
export default function StoreCart({ store, initialProduct = null, table = "" }: { store: PublicStore; initialProduct?: string | null; table?: string }) {
  const [cart, setCart] = useState<Record<string, number>>({});
  const [q, setQ] = useState("");
  const [cat, setCat] = useState("");
  const [open, setOpen] = useState<StoreProduct | null>(store.products.find((p) => p.id === initialProduct) ?? null);
  const [checkout, setCheckout] = useState(false);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [note, setNote] = useState("");
  const [ful, setFul] = useState<"recojo" | "delivery">(store.pickup || !store.delivery ? "recojo" : "delivery");
  const [address, setAddress] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState<Done | null>(null);
  const [copied, setCopied] = useState(false);
  const accent = store.color;
  const isMesa = !!table;

  // El carrito sobrevive a recargas en el mismo teléfono (no es estado compartido: solo comodidad).
  useEffect(() => {
    try {
      const raw = localStorage.getItem(`fv-cart-${store.slug}`);
      if (raw) setCart(JSON.parse(raw) as Record<string, number>);
    } catch {
      /* sin almacenamiento local */
    }
  }, [store.slug]);
  useEffect(() => {
    try {
      localStorage.setItem(`fv-cart-${store.slug}`, JSON.stringify(cart));
    } catch {
      /* sin almacenamiento local */
    }
  }, [cart, store.slug]);

  const list = useMemo(() => {
    const s = q.trim().toLowerCase();
    return store.products.filter((p) => (!cat || p.category === cat) && (!s || p.name.toLowerCase().includes(s) || p.description.toLowerCase().includes(s)));
  }, [q, cat, store.products]);
  const featured = useMemo(() => store.products.filter((p) => p.featured).slice(0, 10), [store.products]);

  const lines = store.products.filter((p) => cart[p.id]).map((p) => ({ p, qty: cart[p.id], unit: unitPrice(p, cart[p.id]) }));
  const count = lines.reduce((a, l) => a + l.qty, 0);
  const total = Math.round(lines.reduce((s, l) => s + l.qty * l.unit, 0) * 100) / 100;
  const belowMin = !isMesa && store.minOrder != null && total < store.minOrder;

  const add = (id: string, d: number) =>
    setCart((c) => {
      const v = Math.max(0, Math.min(999, (c[id] ?? 0) + d));
      const next = { ...c };
      if (v === 0) delete next[id];
      else next[id] = v;
      return next;
    });

  function waText(): string {
    const head = isMesa ? `Pedido mesa ${table}` : `Pedido de ${name || "un cliente"}`;
    const body = lines.map((l) => `• ${l.qty} × ${l.p.name} — ${fmt(l.qty * l.unit, store.currency)}`).join("\n");
    return `${head} en ${store.business}:\n${body}\nTotal: ${fmt(total, store.currency)}${note ? `\nNota: ${note}` : ""}`;
  }

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
          table: isMesa ? table : "",
          fulfillment: isMesa ? "mesa" : ful,
          address: ful === "delivery" ? address : "",
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

  async function share(p: StoreProduct) {
    const url = `${location.origin}/tienda/${store.slug}/p/${p.id}`;
    try {
      if (navigator.share) await navigator.share({ title: p.name, text: `${p.name} · ${fmt(p.priceWithTax, store.currency)}`, url });
      else {
        await navigator.clipboard.writeText(url);
        setCopied(true);
        setTimeout(() => setCopied(false), 1800);
      }
    } catch {
      /* el usuario canceló */
    }
  }

  const input = "w-full rounded-2xl border border-[#ece9f7] bg-white px-4 py-3 text-[15px] outline-none focus:ring-2";

  if (done) {
    const wa = done.whatsapp ? `https://wa.me/51${done.whatsapp}?text=${encodeURIComponent(`Hola ${done.business}, acabo de hacer el pedido ${done.number} por ${fmt(done.total, done.currency)}.`)}` : "";
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f8f6fd] p-5 text-[#26254b]">
        <div className="w-full max-w-md rounded-[28px] bg-white p-8 text-center shadow-[0_20px_60px_-20px_rgba(106,98,226,0.35)]">
          <div className="mx-auto flex h-20 w-20 animate-[pop_.5s_ease-out] items-center justify-center rounded-full text-4xl text-white" style={{ background: accent }}>✓</div>
          <h1 className="mt-5 text-2xl font-bold">{isMesa ? "¡Pedido enviado a cocina!" : "¡Pedido enviado!"}</h1>
          <p className="mt-2 text-[15px] text-[#55577a]">
            {done.business} recibió tu pedido <b>{done.number}</b> por <b>{fmt(done.total, done.currency)}</b>.
          </p>
          <div className="mt-6 space-y-3">
            {wa && !isMesa ? <a href={wa} className="block w-full rounded-2xl bg-[#25D366] py-4 font-semibold text-white">Avisar por WhatsApp</a> : null}
            <a href={`/cotizacion/${done.token}`} className="block w-full rounded-2xl border border-[#ece9f7] py-3.5 font-semibold" style={{ color: accent }}>Ver mi pedido</a>
            <button onClick={() => setDone(null)} className="w-full py-2 text-sm text-[#77799b]">Hacer otro pedido</button>
          </div>
        </div>
        <style>{"@keyframes pop{0%{transform:scale(.4);opacity:0}70%{transform:scale(1.08)}100%{transform:scale(1);opacity:1}}"}</style>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f8f6fd] pb-40 text-[#26254b]">
      <header className="px-5 pb-16 pt-9 text-white" style={{ background: `linear-gradient(135deg, ${accent}, ${accent}cc 55%, #b58bf5)` }}>
        <div className="mx-auto flex max-w-3xl items-center gap-4">
          {store.logo ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={store.logo} alt={store.business} className="h-16 w-16 rounded-2xl bg-white object-contain p-1.5 shadow-lg" />
          ) : (
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-white/20 text-3xl">{store.mode === "carta" ? "🍽️" : "🛍️"}</div>
          )}
          <div className="min-w-0">
            <p className="text-[13px] font-medium opacity-85">{isMesa ? `Mesa ${table} · Carta digital` : store.mode === "carta" ? "Carta digital" : "Pedidos en línea"}</p>
            <h1 className="truncate text-[28px] font-bold leading-tight tracking-tight">{store.business}</h1>
            {store.headline ? <p className="mt-1 text-[14.5px] opacity-90">{store.headline}</p> : null}
          </div>
        </div>
      </header>

      <div className="mx-auto -mt-10 max-w-3xl px-4">
        <input className={`${input} shadow-lg shadow-black/5`} placeholder="¿Qué buscas hoy?" value={q} onChange={(e) => setQ(e.target.value)} />
        {store.about ? <p className="mt-3 rounded-2xl bg-white px-4 py-3 text-[14px] text-[#55577a]">{store.about}</p> : null}
        {store.booking ? (
          <a href={`/reservar/${store.slug}`} className="mt-3 block rounded-2xl bg-white px-4 py-3 text-[14.5px] font-semibold shadow-sm" style={{ color: accent }}>📅 Reserva tu cita en línea →</a>
        ) : null}

        {store.categories.length > 1 ? (
          <div className="-mx-4 mt-4 flex gap-2 overflow-x-auto px-4 pb-1">
            {["", ...store.categories].map((c) => (
              <button key={c || "_all"} onClick={() => setCat(c)} className="shrink-0 rounded-full px-4 py-2 text-[14px] font-semibold transition" style={cat === c ? { background: accent, color: "#fff" } : { background: "#fff", color: "#26254b" }}>
                {c || "Todo"}
              </button>
            ))}
          </div>
        ) : null}

        {featured.length && !q && !cat ? (
          <section className="mt-5">
            <h2 className="mb-2 text-[15px] font-bold">⭐ Destacados</h2>
            <div className="-mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-2">
              {featured.map((p) => (
                <button key={p.id} onClick={() => setOpen(p)} className="w-40 shrink-0 snap-start overflow-hidden rounded-3xl bg-white text-left shadow-[0_10px_30px_-18px_rgba(0,0,0,0.35)]">
                  <Thumb p={p} h="h-28" />
                  <div className="p-3">
                    <p className="line-clamp-2 text-[14px] font-semibold">{p.name}</p>
                    <p className="mt-1 text-[14px] font-bold tabular-nums" style={{ color: accent }}>{fmt(p.priceWithTax, store.currency)}</p>
                  </div>
                </button>
              ))}
            </div>
          </section>
        ) : null}

        <ul className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
          {list.map((p) => {
            const n = cart[p.id] ?? 0;
            const out = p.stock != null && p.stock <= 0;
            return (
              <li key={p.id} className={`flex flex-col overflow-hidden rounded-3xl bg-white shadow-[0_10px_30px_-18px_rgba(0,0,0,0.35)] transition ${n ? "ring-2" : ""}`} style={n ? { boxShadow: `0 0 0 2px ${accent}66` } : undefined}>
                <button onClick={() => setOpen(p)} className="text-left">
                  <Thumb p={p} h="h-32" />
                  <div className="px-3 pt-3">
                    <p className="line-clamp-2 min-h-[2.5em] text-[14.5px] font-semibold leading-tight">{p.name}</p>
                    <p className="mt-1 text-[15px] font-bold tabular-nums" style={{ color: accent }}>{fmt(p.priceWithTax, store.currency)}</p>
                    {p.wholesalePrice != null && p.wholesaleMinQty != null ? <p className="text-[11.5px] text-[#23956f]">{fmt(p.wholesalePrice, store.currency)} desde {p.wholesaleMinQty}</p> : null}
                  </div>
                </button>
                <div className="mt-auto p-3">
                  {out ? (
                    <p className="text-center text-[13px] text-[#d94a5e]">Agotado</p>
                  ) : n === 0 ? (
                    <button onClick={() => add(p.id, 1)} className="w-full rounded-2xl py-2.5 text-sm font-semibold text-white transition active:scale-95" style={{ background: accent }}>Agregar</button>
                  ) : (
                    <div className="flex items-center justify-between">
                      <button onClick={() => add(p.id, -1)} aria-label="Quitar uno" className="h-9 w-9 rounded-xl bg-[#f3f1fc] text-lg font-bold active:scale-90" style={{ color: accent }}>−</button>
                      <span className="font-bold tabular-nums">{n}</span>
                      <button onClick={() => add(p.id, 1)} aria-label="Agregar uno" className="h-9 w-9 rounded-xl text-lg font-bold text-white active:scale-90" style={{ background: accent }}>+</button>
                    </div>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
        {list.length === 0 ? <p className="mt-10 text-center text-sm text-[#77799b]">No encontramos productos.</p> : null}
        <p className="mt-6 text-center text-xs text-[#8a8cab]">Precios con IGV · {store.taxId ? `RUC ${store.taxId} · ` : ""}Hecho con FacturaVoz</p>
      </div>

      {/* Ficha del producto */}
      {open ? (
        <div className="fixed inset-0 z-30 flex items-end justify-center bg-black/40 sm:items-center" onClick={() => setOpen(null)}>
          <div className="max-h-[92vh] w-full max-w-md overflow-y-auto rounded-t-[28px] bg-white sm:rounded-[28px]" onClick={(e) => e.stopPropagation()}>
            <Thumb p={open} h="h-64" />
            <div className="p-6">
              <h2 className="text-xl font-bold">{open.name}</h2>
              <p className="mt-1 text-lg font-bold" style={{ color: accent }}>{fmt(open.priceWithTax, store.currency)}</p>
              {open.description ? <p className="mt-3 whitespace-pre-line text-[14.5px] text-[#55577a]">{open.description}</p> : null}
              {open.wholesalePrice != null && open.wholesaleMinQty != null ? <p className="mt-2 text-[13.5px] text-[#23956f]">Por mayor: {fmt(open.wholesalePrice, store.currency)} c/u desde {open.wholesaleMinQty} unidades</p> : null}
              <div className="mt-5 flex gap-3">
                <button onClick={() => { add(open.id, 1); setOpen(null); }} className="flex-1 rounded-2xl py-3.5 font-semibold text-white" style={{ background: accent }}>Agregar al pedido</button>
                <button onClick={() => share(open)} className="rounded-2xl bg-[#f3f1fc] px-4 font-semibold" style={{ color: accent }}>{copied ? "¡Copiado!" : "Compartir"}</button>
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {/* Carrito flotante */}
      {count > 0 && !checkout ? (
        <div className="fixed inset-x-0 bottom-0 z-20 p-4">
          <button onClick={() => setCheckout(true)} className="mx-auto flex w-full max-w-3xl items-center justify-between rounded-3xl px-6 py-4 text-white shadow-2xl transition active:scale-[.98]" style={{ background: accent }}>
            <span className="rounded-full bg-white/25 px-3 py-1 text-sm font-bold">{count}</span>
            <span className="font-semibold">Ver mi pedido</span>
            <span className="font-bold tabular-nums">{fmt(total, store.currency)}</span>
          </button>
        </div>
      ) : null}

      {checkout ? (
        <div className="fixed inset-0 z-30 flex items-end justify-center bg-black/40 sm:items-center" onClick={() => setCheckout(false)}>
          <div className="max-h-[92vh] w-full max-w-md overflow-y-auto rounded-t-[28px] bg-white p-6 sm:rounded-[28px]" onClick={(e) => e.stopPropagation()}>
            <h2 className="text-xl font-bold">Tu pedido</h2>
            <ul className="mt-3 divide-y divide-[#ece9f7]">
              {lines.map((l) => (
                <li key={l.p.id} className="flex items-center justify-between gap-3 py-2.5">
                  <div className="min-w-0">
                    <p className="truncate text-[14.5px] font-medium">{l.p.name}</p>
                    <p className="text-[12.5px] text-[#77799b]">{l.qty} × {fmt(l.unit, store.currency)}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <button onClick={() => add(l.p.id, -1)} className="h-8 w-8 rounded-lg bg-[#f3f1fc] font-bold" style={{ color: accent }}>−</button>
                    <button onClick={() => add(l.p.id, 1)} className="h-8 w-8 rounded-lg font-bold text-white" style={{ background: accent }}>+</button>
                  </div>
                </li>
              ))}
            </ul>
            <p className="mt-3 flex justify-between text-lg font-bold"><span>Total</span><span className="tabular-nums">{fmt(total, store.currency)}</span></p>
            {belowMin ? <p className="mt-1 text-[13px] text-[#c57a12]">Pedido mínimo: {fmt(store.minOrder ?? 0, store.currency)}</p> : null}
            {!isMesa && store.pickup && store.delivery ? (
              <div className="mt-4 grid grid-cols-2 gap-2">
                {(["recojo", "delivery"] as const).map((f) => (
                  <button key={f} onClick={() => setFul(f)} className="rounded-2xl py-3 text-sm font-semibold" style={ful === f ? { background: accent, color: "#fff" } : { background: "#f3f1fc" }}>
                    {f === "recojo" ? "🏪 Recojo" : "🛵 Delivery"}
                  </button>
                ))}
              </div>
            ) : null}
            {!isMesa && ful === "delivery" && store.deliveryNote ? <p className="mt-2 text-[13px] text-[#77799b]">{store.deliveryNote}</p> : null}
            <div className="mt-4 space-y-3">
              <input className={input} placeholder="Tu nombre" value={name} onChange={(e) => setName(e.target.value.slice(0, 120))} autoComplete="name" />
              <input className={input} placeholder="Celular (9 dígitos)" inputMode="numeric" value={phone} onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 9))} autoComplete="tel" />
              {!isMesa && ful === "delivery" ? <input className={input} placeholder="Dirección de entrega" value={address} onChange={(e) => setAddress(e.target.value.slice(0, 200))} autoComplete="street-address" /> : null}
              <input className={input} placeholder={isMesa ? "Indicaciones para cocina (opcional)" : "Nota (opcional)"} value={note} onChange={(e) => setNote(e.target.value.slice(0, 300))} />
            </div>
            {error ? <p className="mt-3 text-sm text-[#d94a5e]">{error}</p> : null}
            <button disabled={busy || belowMin || !name.trim() || phone.length !== 9} onClick={send} className="mt-4 w-full rounded-2xl py-4 text-[16px] font-semibold text-white disabled:opacity-50" style={{ background: accent }}>
              {busy ? "Enviando…" : isMesa ? "Enviar a cocina" : "Enviar pedido"}
            </button>
            {store.whatsapp && !isMesa ? (
              <a href={`https://wa.me/51${store.whatsapp}?text=${encodeURIComponent(waText())}`} className="mt-3 block w-full rounded-2xl bg-[#25D366] py-3.5 text-center font-semibold text-white">Pedir por WhatsApp</a>
            ) : null}
            <button onClick={() => setCheckout(false)} className="mt-2 w-full py-2 text-sm text-[#77799b]">Seguir comprando</button>
          </div>
        </div>
      ) : null}
    </main>
  );
}

function Thumb({ p, h }: { p: StoreProduct; h: string }) {
  if (p.image) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={p.image} alt={p.name} loading="lazy" decoding="async" className={`${h} w-full object-cover`} />;
  }
  return <div className={`${h} flex w-full items-center justify-center bg-gradient-to-br from-[#ebe9ff] to-[#fbe7ef] text-4xl`}>{p.service ? "🛠️" : "📦"}</div>;
}
