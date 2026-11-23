"use client";
import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { usePathname, useRouter } from "next/navigation";
import { createPortal } from "react-dom";
import { getReceipt, shareReceipt, type ReceiptDetail, type ReceiptShare } from "@/app/erp/actions";
import { waPhone } from "@/lib/erp/clients";
import {
  kindLabel, mailtoHref, matchesReceipt, parseRange, presetRange, receiptKind, shareMessage, receiptNumber, summarize, sunatLabel, sunatState, voidHint, voidWindow,
  type ReceiptKind, type ReceiptRow, type SunatState,
} from "@/lib/erp/receipts";

const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const day = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));

const stateTone: Record<SunatState, string> = {
  aceptado: "is-ok", pendiente: "is-wait", rechazado: "is-bad", error: "is-bad", anulado: "is-off", sin_envio: "is-off",
};

/** Every receipt of the company, the same rows the mobile app issues. */
export default function ReceiptsBoard({ org, rows, currency, range = null, capped = false }: { org: string; rows: ReceiptRow[]; currency: string; range?: { from: string; to: string } | null; capped?: boolean }) {
  const [q, setQ] = useState("");
  const [kind, setKind] = useState<ReceiptKind | "todos">("todos");
  const [sunat, setSunat] = useState<SunatState | "todos">("todos");
  const [openId, setOpenId] = useState<string | null>(null);
  const visible = useMemo(() => rows.filter(r => matchesReceipt(r, { q, kind, sunat })), [rows, q, kind, sunat]);
  const totals = summarize(visible);
  const open = rows.find(r => r.id === openId) ?? null;
  return <section className="fv-board">
    <div className="fv-kpis">
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Vendido en la lista</span><strong>{fmt(totals.total, currency)}</strong><small>{totals.count} {totals.count === 1 ? "comprobante" : "comprobantes"}</small></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Aceptados por SUNAT</span><strong>{totals.accepted}</strong><small>con CDR disponible</small></div>
      <div style={{ "--tone": totals.attention ? "#ff7a6e" : "#a98bff" } as React.CSSProperties}><span>Requieren atención</span><strong>{totals.attention}</strong><small>pendientes, rechazados o con error</small></div>
    </div>
    <div className="fv-board-tools">
      <label className="fv-search"><span>Buscar</span><input type="search" value={q} onChange={e => setQ(e.target.value)} placeholder="Número, cliente, DNI o RUC…" /></label>
      <div className="fv-segment" role="group" aria-label="Tipo de comprobante">
        {(["todos", "boleta", "factura", "nota_credito"] as const).map(k => <button key={k} aria-pressed={kind === k} onClick={() => setKind(k)}>{k === "todos" ? "Todos" : kindLabel[k]}</button>)}
      </div>
      <label className="fv-search fv-narrow"><span>Estado SUNAT</span>
        <select value={sunat} onChange={e => setSunat(e.target.value as SunatState | "todos")}>
          <option value="todos">Todos</option>
          {(Object.keys(sunatLabel) as SunatState[]).map(s => <option key={s} value={s}>{sunatLabel[s]}</option>)}
        </select>
      </label>
    </div>
    <DateRange range={range} />
    <p className="fv-caption" aria-live="polite">{visible.length} {visible.length === 1 ? "comprobante" : "comprobantes"}{range ? ` del ${day(range.from)} al ${day(range.to)}` : ""}{capped ? " · se muestran los 300 más recientes; acota las fechas para ver el resto" : ""}</p>
    <ul className="fv-receipts">
      {visible.map((r, i) => {
        const s = sunatState(r);
        return <li key={r.id} style={{ "--i": Math.min(i, 14) } as React.CSSProperties}>
          <button onClick={() => setOpenId(r.id)} aria-label={`${kindLabel[receiptKind(r)]} ${receiptNumber(r)}, ${r.client?.name || "Cliente varios"}, ${sunatLabel[s]}`}>
            <span className={`fv-doc-badge is-${receiptKind(r)}`}>{kindLabel[receiptKind(r)].slice(0, 1)}</span>
            <span className="fv-receipt-main">
              <strong>{receiptNumber(r)}</strong>
              <small>{r.client?.name || "Cliente varios"}{r.client?.tax_id ? ` · ${r.client.tax_id}` : ""}</small>
            </span>
            <span className="fv-receipt-date">{day(r.issue_date)}</span>
            <span className={`fv-pill ${stateTone[s]}`}>{sunatLabel[s]}</span>
            <span className="fv-receipt-total">{fmt(Number(r.amt_total ?? 0), r.currency || currency)}</span>
          </button>
        </li>;
      })}
    </ul>
    {!visible.length && <div className="fv-empty"><h2>{q || kind !== "todos" || sunat !== "todos" || range ? "Sin coincidencias" : "Todavía no hay comprobantes"}</h2><p>Las boletas y facturas emitidas en el móvil o aquí aparecen en esta lista.</p></div>}
    {open && <ReceiptSheet key={open.id} org={org} row={open} currency={currency} onClose={() => setOpenId(null)} />}
  </section>;
}

function ReceiptSheet({ org, row, currency, onClose }: { org: string; row: ReceiptRow; currency: string; onClose: () => void }) {
  const [detail, setDetail] = useState<ReceiptDetail | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let alive = true;
    getReceipt(org, row.id).then(d => { if (alive) setDetail(d); });
    panel.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => { alive = false; window.removeEventListener("keydown", onKey); };
  }, [org, row.id, onClose]);
  const s = sunatState(row);
  const hint = voidHint(voidWindow(row));
  const cur = row.currency || currency;
  const base = `/erp/${org}/comprobantes/${row.id}`;
  const root = typeof document === "undefined" ? null : document.querySelector(".fv-workspace");
  const sheet = <div className="fv-sheet-layer" onClick={onClose}>
    <div ref={panel} tabIndex={-1} className="fv-sheet" role="dialog" aria-modal="true" aria-labelledby="fv-receipt-title" onClick={e => e.stopPropagation()}>
      <header><div><small>{kindLabel[receiptKind(row)]}</small><h2 id="fv-receipt-title">{receiptNumber(row)}</h2></div>
        <button className="fv-icon-button" onClick={onClose} aria-label="Cerrar">✕</button></header>
      <div className={`fv-sunat ${stateTone[s]}`}>
        <strong>{sunatLabel[s]}</strong>
        {row.fiscal?.sunat_message && <span>{row.fiscal.sunat_message}</span>}
        {hint && <span>{hint}</span>}
      </div>
      <dl className="fv-mini">
        <div><dt>Cliente</dt><dd>{row.client?.name || "Cliente varios"}</dd></div>
        <div><dt>Documento</dt><dd>{row.client?.tax_id || "—"}</dd></div>
        <div><dt>Fecha</dt><dd>{day(row.issue_date)}</dd></div>
      </dl>
      {!detail ? <div className="fv-skeleton" aria-label="Cargando detalle"><i /><i /><i /></div>
        : !detail.ok ? <p role="alert" className="fv-error">{detail.message}</p>
        : <>
          <ul className="fv-lines">
            {detail.items.map((l, i) => <li key={i}><span>{l.quantity} × {l.description}</span><span>{fmt(l.quantity * l.unit_price, cur)}</span></li>)}
          </ul>
          <dl className="fv-sums">
            {detail.discount > 0 && <div><dt>Descuento</dt><dd>−{fmt(detail.discount, cur)}</dd></div>}
            <div><dt>Op. gravada</dt><dd>{fmt(detail.base, cur)}</dd></div>
            <div><dt>IGV</dt><dd>{fmt(detail.tax, cur)}</dd></div>
            <div className="is-total"><dt>Total</dt><dd>{fmt(detail.total, cur)}</dd></div>
          </dl>
        </>}
      <div className="fv-actions">
        <a className="fv-button" href={`${base}/imprimir`} target="_blank" rel="noopener">Ver e imprimir (A4)</a>
        <a className="fv-button secondary" href={`${base}/imprimir?formato=ticket`} target="_blank" rel="noopener">Ticket 80 mm</a>
        {s === "aceptado" && <>
          <a className="fv-button secondary" href={`${base}/archivo?k=xml`}>XML firmado</a>
          <a className="fv-button secondary" href={`${base}/archivo?k=cdr`}>CDR de SUNAT</a>
        </>}
      </div>
      <SendReceipt org={org} row={row} />
    </div>
  </div>;
  return root ? createPortal(sheet, root) : sheet;
}

/** Issue-date filter: read by the server from `?desde=&hasta=` so it covers every receipt, not just the loaded page. */
function DateRange({ range }: { range: { from: string; to: string } | null }) {
  const router = useRouter();
  const path = usePathname();
  const [pending, start] = useTransition();
  const [from, setFrom] = useState(range?.from ?? "");
  const [to, setTo] = useState(range?.to ?? "");
  const [error, setError] = useState("");
  const go = (r: { from: string; to: string } | null) => {
    setError("");
    setFrom(r?.from ?? ""); setTo(r?.to ?? "");
    start(() => router.replace(r ? `${path}?desde=${r.from}&hasta=${r.to}` : path, { scroll: false }));
  };
  const apply = (e: React.FormEvent) => {
    e.preventDefault();
    const r = parseRange(from, to || from);
    if (!r) { setError("Elige un rango válido de hasta 366 días (la fecha inicial no puede ser posterior a la final)."); return; }
    go(r);
  };
  const is = (p: "hoy" | "7dias" | "mes") => { const r = presetRange(p); return range?.from === r.from && range?.to === r.to; };
  return <form className="fv-board-tools" onSubmit={apply} aria-busy={pending}>
    <div className="fv-segment" role="group" aria-label="Rango rápido de fechas">
      <button type="button" aria-pressed={!range} onClick={() => go(null)}>Todo</button>
      <button type="button" aria-pressed={is("hoy")} onClick={() => go(presetRange("hoy"))}>Hoy</button>
      <button type="button" aria-pressed={is("7dias")} onClick={() => go(presetRange("7dias"))}>7 días</button>
      <button type="button" aria-pressed={is("mes")} onClick={() => go(presetRange("mes"))}>Este mes</button>
    </div>
    <label className="fv-search fv-narrow"><span>Desde</span><input type="date" value={from} onChange={e => setFrom(e.target.value)} required /></label>
    <label className="fv-search fv-narrow"><span>Hasta (incluido)</span><input type="date" value={to} min={from || undefined} onChange={e => setTo(e.target.value)} /></label>
    <button className="fv-button secondary" disabled={pending}>{pending ? "Filtrando…" : "Filtrar fechas"}</button>
    {error && <p role="alert" className="fv-error">{error}</p>}
  </form>;
}

/** Send the receipt's private link by WhatsApp or e-mail (the customer sees, prints and downloads it, no account). */
function SendReceipt({ org, row }: { org: string; row: ReceiptRow }) {
  const [share, setShare] = useState<ReceiptShare | null>(null);
  const [busy, setBusy] = useState(false);
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [copied, setCopied] = useState(false);
  const prepare = async () => {
    setBusy(true);
    const s = await shareReceipt(org, row.id).catch(() => ({ ok: false, message: "No se pudo crear el enlace. Inténtalo de nuevo." }) as const);
    setShare(s);
    if (s.ok) { setPhone(s.phone); setEmail(s.email); }
    setBusy(false);
  };
  if (!share || !share.ok) return <div className="fv-send">
    <button className="fv-button" onClick={prepare} disabled={busy}>{busy ? "Preparando enlace…" : "Enviar al cliente"}</button>
    {share && !share.ok && <p role="alert" className="fv-error">{share.message}</p>}
  </div>;
  const url = `${window.location.origin}${share.path}`;
  const message = shareMessage({ client: row.client?.name, number: receiptNumber(row), business: share.business, url });
  const wa = waPhone(phone);
  const copy = async () => { try { await navigator.clipboard.writeText(url); setCopied(true); } catch { setCopied(false); } };
  return <div className="fv-send" aria-label="Enviar al cliente">
    <p className="fv-caption">Enlace privado: tu cliente ve, imprime o descarga el comprobante (PDF, XML y CDR) sin crear cuenta.</p>
    <div className="fv-send-row">
      <label className="fv-search"><span>WhatsApp</span><input type="tel" inputMode="tel" value={phone} onChange={e => setPhone(e.target.value)} placeholder="9XX XXX XXX" /></label>
      {wa ? <a className="fv-button" href={`https://wa.me/${wa}?text=${encodeURIComponent(message)}`} target="_blank" rel="noopener">Enviar por WhatsApp</a>
        : <a className="fv-button secondary" href={`https://wa.me/?text=${encodeURIComponent(message)}`} target="_blank" rel="noopener">Elegir chat en WhatsApp</a>}
    </div>
    <div className="fv-send-row">
      <label className="fv-search"><span>Correo</span><input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="cliente@correo.com" /></label>
      <a className="fv-button secondary" href={mailtoHref({ to: email, number: receiptNumber(row), business: share.business, body: message })}>Enviar por correo</a>
    </div>
    <button className="fv-button secondary" onClick={copy}>{copied ? "Enlace copiado" : "Copiar enlace"}</button>
  </div>;
}
