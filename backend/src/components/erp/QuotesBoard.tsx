"use client";
import type React from "react";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { convertQuote, deleteQuote, setQuoteStatus, type FormResult } from "@/app/erp/actions";

export type QuoteRow = {
  id: string; number: string; status: string; issue_date: string; valid_until: string | null; currency: string; total: number;
  client: string; token: string | null; invoice_id: string | null; responder: string | null; response_note: string | null; responded_at: string | null;
  from_store: boolean; contact_phone: string | null;
};

const label: Record<string, string> = { draft: "Borrador", sent: "Enviada", accepted: "Aceptada", rejected: "Rechazada", converted: "Facturada" };
const tone: Record<string, string> = { draft: "is-wait", sent: "is-wait", accepted: "is-ok", rejected: "is-off", converted: "is-ok" };
const tabs = [["open", "Abiertas"], ["store", "Pedidos de la tienda"], ["accepted", "Aceptadas"], ["converted", "Facturadas"], ["closed", "Cerradas"]] as const;
type Tab = (typeof tabs)[number][0];

/** The mobile «Cotizaciones y pedidos»: send the link, see who accepted, and turn it into a sale. */
export default function QuotesBoard({ org, rows, today, canSell }: { org: string; rows: QuoteRow[]; today: string; canSell: boolean }) {
  const [tab, setTab] = useState<Tab>("open");
  const expired = (q: QuoteRow) => !!q.valid_until && q.valid_until < today && (q.status === "draft" || q.status === "sent");
  const match = (t: Tab, q: QuoteRow) => t === "open" ? (q.status === "draft" || q.status === "sent") && !expired(q)
    : t === "store" ? q.from_store && q.status !== "converted" && q.status !== "rejected"
    : t === "accepted" ? q.status === "accepted"
    : t === "converted" ? q.status === "converted"
    : q.status === "rejected" || expired(q);
  const fmt = (n: number, cur: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency: cur || "PEN" }).format(n);
  const open = rows.filter(q => (q.status === "draft" || q.status === "sent" || q.status === "accepted") && !expired(q));
  const decided = rows.filter(q => ["accepted", "converted", "rejected"].includes(q.status)).length;
  const won = rows.filter(q => q.status === "accepted" || q.status === "converted").length;
  const list = rows.filter(q => match(tab, q));
  return <section className="fv-board">
    <div className="fv-kpis">
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Por cerrar</span><strong>{fmt(open.reduce((a, q) => a + q.total, 0), rows[0]?.currency ?? "PEN")}</strong><small>{open.length} {open.length === 1 ? "cotización abierta" : "cotizaciones abiertas"}</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Aceptadas</span><strong>{decided ? `${Math.round((won / decided) * 100)} %` : "—"}</strong><small>{decided ? `${won} de ${decided} respondidas` : "aún sin respuestas"}</small></div>
      <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Listas para facturar</span><strong>{rows.filter(q => q.status === "accepted").length}</strong><small>aceptadas por el cliente</small></div>
    </div>
    <div className="fv-chips" role="tablist">{tabs.map(([id, t]) => <button key={id} role="tab" className="fv-chip" aria-pressed={tab === id} onClick={() => setTab(id)}>{t} ({rows.filter(q => match(id, q)).length})</button>)}</div>
    {!list.length ? <div className="fv-empty"><h2>Nada por aquí</h2><p>{tab === "open" ? "Crea una cotización arriba y envíale el enlace a tu cliente." : "Cuando haya cotizaciones en este estado aparecerán aquí."}</p></div>
      : <ul className="fv-quotes">{list.map(q => <QuoteCard key={q.id} org={org} q={q} expired={expired(q)} canSell={canSell} fmt={fmt} />)}</ul>}
  </section>;
}

function QuoteCard({ org, q, expired, canSell, fmt }: { org: string; q: QuoteRow; expired: boolean; canSell: boolean; fmt: (n: number, c: string) => string }) {
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [due, setDue] = useState("");
  const [asking, setAsking] = useState(false);
  const router = useRouter();
  const url = q.token && typeof window !== "undefined" ? `${window.location.origin}/cotizacion/${q.token}` : "";
  async function act(run: () => Promise<FormResult>, confirm?: string) {
    if (confirm && !window.confirm(confirm)) return;
    setBusy(true); const r = await run().catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); setBusy(false); if (r.ok) router.refresh();
  }
  const markSent = () => { if (q.status === "draft") void setQuoteStatus(org, q.id, "sent").then(() => router.refresh()); };
  const wa = q.contact_phone ? q.contact_phone.replace(/\D/g, "") : "";
  const text = `Hola${q.client && q.client !== "Cliente varios" ? ` ${q.client}` : ""}, te envío la cotización ${q.number}: ${url}`;
  return <li className="fv-quote">
    <div className="fv-quote-main">
      <div><strong>{q.number}</strong> <span className={`fv-pill ${expired ? "is-off" : tone[q.status] ?? "is-wait"}`}>{expired ? "Vencida" : label[q.status] ?? q.status}</span>{q.from_store && <span className="fv-pill is-wait">Tienda</span>}</div>
      <span>{q.client || "Cliente varios"}</span>
      <small>Emitida {q.issue_date}{q.valid_until ? ` · válida hasta ${q.valid_until}` : ""}</small>
      {q.responded_at && <small className={q.status === "rejected" ? "fv-neg" : ""}>{q.status === "rejected" ? "Rechazada" : "Aceptada"} por {q.responder || "el cliente"}{q.response_note ? `: «${q.response_note}»` : ""}</small>}
    </div>
    <b className="fv-quote-total">{fmt(q.total, q.currency)}</b>
    <div className="fv-actions">
      {q.status === "converted" && q.invoice_id ? <Link className="fv-button secondary" href={`/erp/${org}/comprobantes`}>Ver venta</Link> : <>
        {q.status !== "rejected" && url && <>
          <button className="fv-button secondary" onClick={() => { void navigator.clipboard?.writeText(url); setM({ ok: true, message: "Enlace copiado." }); markSent(); }}>Copiar enlace</button>
          <a className="fv-button secondary" href={`https://wa.me/${wa}?text=${encodeURIComponent(text)}`} target="_blank" rel="noreferrer" onClick={markSent}>WhatsApp</a>
        </>}
        {(q.status === "draft" || q.status === "sent") && <>
          <button className="fv-button secondary" disabled={busy} onClick={() => void act(() => setQuoteStatus(org, q.id, "accepted"))}>Aceptada</button>
          <button className="fv-button secondary" disabled={busy} onClick={() => void act(() => setQuoteStatus(org, q.id, "rejected"), "¿Marcarla como rechazada?")}>Rechazada</button>
        </>}
        {canSell && q.status !== "rejected" && (asking
          ? <span className="fv-inline-form"><label className="fv-search"><span>Vence el pago (opcional)</span><input type="date" value={due} onChange={e => setDue(e.target.value)} /></label>
              <button className="fv-button" disabled={busy} onClick={() => void act(() => convertQuote(org, q.id, due || null))}>{busy ? "Convirtiendo…" : "Convertir"}</button></span>
          : <button className={q.status === "accepted" ? "fv-button" : "fv-button secondary"} onClick={() => setAsking(true)}>{q.status === "accepted" ? "Convertir en venta" : "Convertir ya"}</button>)}
        {(q.status === "draft" || q.status === "rejected") && <button className="fv-link" disabled={busy} onClick={() => void act(() => deleteQuote(org, q.id), "¿Eliminar esta cotización?")}>Eliminar</button>}
      </>}
    </div>
    {m?.message && <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p>}
  </li>;
}
