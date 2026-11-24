"use client";
import { useActionState, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { fiadoMove, resolveNotice, saveNotice, type FormResult } from "@/app/erp/actions";
import { noticeMatches, parsePaymentNotice, type ParsedNotice } from "@/lib/erp/notices";

const idle: FormResult = { ok: false, message: "" };
const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;
const appName: Record<string, string> = { yape: "Yape", plin: "Plin", banco: "Banco", otro: "Otro" };

export type OpenInvoice = { id: string; number: string; client: string; balance: number };
export type NoticeRow = { id: string; app: string; amount: number; payer: string | null; operation_code: string | null; received_at: string; status: string; invoice: string | null };

/** «Avisos de Yape y Plin»: paste the notification, check it and register the payment; full history with filters. */
export function NoticesBoard({ org, rows, open, currency }: { org: string; rows: NoticeRow[]; open: OpenInvoice[]; currency: string }) {
  const sym = currency === "USD" ? "US$" : "S/";
  const fmt = (n: number) => `${sym} ${n.toFixed(2)}`;
  const [text, setText] = useState("");
  const [p, setP] = useState<ParsedNotice | null>(null);
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [filter, setFilter] = useState<"todos" | "nuevo" | "aplicado" | "descartado">("todos");
  const [q, setQ] = useState("");
  const router = useRouter();
  const matches = useMemo(() => (p ? noticeMatches(p.amount, open, p.payer).slice(0, 5) : []), [p, open]);
  async function run(task: Promise<FormResult>, clear = false) {
    setBusy(true); setM(null);
    const r = await task.catch(() => ({ ok: false, message: "Sin conexión." }));
    setBusy(false); setM(r);
    if (r.ok) { if (clear) { setText(""); setP(null); } router.refresh(); }
  }
  const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  const shown = rows.filter(r => (filter === "todos" || r.status === filter) && (!q || norm(`${r.payer ?? ""} ${r.operation_code ?? ""} ${r.amount}`).includes(norm(q))));
  const time = (iso: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));
  return <section className="fv-board">
    <section className="fv-create fv-settings-card">
      <h3>Registrar un aviso</h3>
      <p className="fv-caption">Copia la notificación de Yape, Plin o tu banco y pégala aquí. Leemos el monto, quién pagó y la operación.</p>
      <textarea rows={3} value={text} maxLength={600} onChange={e => { setText(e.target.value); setP(parsePaymentNotice(e.target.value)); setM(null); }}
        placeholder="¡Yape! JUAN PEREZ te envió un pago por S/ 25.50. El cód. de seguridad es: 123" aria-label="Texto del aviso" />
      {text && !p && <p className="fv-error">No encuentro el monto. Debe decir algo como «S/ 25.50».</p>}
      {p && <div className="fv-notice-preview">
        <span className={`fv-app-badge a-${p.app}`}>{appName[p.app]}</span><b>{fmt(p.amount)}</b><span>{p.payer || "Pagador sin nombre"}</span>{p.operation && <small>Op. {p.operation}</small>}
      </div>}
      {p && <>{matches.length > 0 ? <><p className="fv-caption">Comprobantes por cobrar con ese monto:</p><ul className="fv-lines">{matches.map(i => <li key={i.id}><span>{i.number} · {i.client}</span>
        <button className="fv-button" disabled={busy} onClick={() => void run(saveNotice(org, p, i.id), true)}>Registrar cobro aquí</button></li>)}</ul></> : <p className="fv-caption">No hay comprobantes por cobrar con ese monto exacto (si fue una venta al contado, solo guarda el aviso).</p>}
        <button className="fv-button secondary" disabled={busy} onClick={() => void run(saveNotice(org, p, null), true)}>Solo guardar el aviso</button></>}
      <Msg m={m} />
    </section>
    <div className="fv-board-tools">
      <div className="fv-chips">{(["todos", "nuevo", "aplicado", "descartado"] as const).map(f => <button key={f} className="fv-chip" aria-pressed={filter === f} onClick={() => setFilter(f)}>
        {f === "todos" ? "Todos" : f === "nuevo" ? "Sin asociar" : f === "aplicado" ? "Con cobro" : "Descartados"} ({f === "todos" ? rows.length : rows.filter(r => r.status === f).length})</button>)}</div>
      <label className="fv-search"><span>Buscar</span><input value={q} onChange={e => setQ(e.target.value)} placeholder="Nombre, operación o monto" /></label>
    </div>
    {!shown.length ? <div className="fv-empty"><h2>{rows.length ? "Nada con ese filtro" : "Aún no hay avisos"}</h2><p>{rows.length ? "Prueba otro filtro." : "Pega aquí arriba el primer aviso, o activa en el móvil la lectura automática de notificaciones."}</p></div>
      : <ul className="fv-collect">{shown.map(r => { const cand = r.status === "nuevo" ? noticeMatches(r.amount, open, r.payer ?? "").slice(0, 3) : [];
        return <li key={r.id}><div className="fv-collect-main"><strong><span className={`fv-app-badge a-${r.app}`}>{appName[r.app] ?? r.app}</span> {r.payer || "Sin nombre"}</strong>
          <small>{time(r.received_at)}{r.operation_code ? ` · op. ${r.operation_code}` : ""}{r.invoice ? ` · cobro en ${r.invoice}` : ""}</small></div>
          <div className="fv-collect-amount"><b>{fmt(r.amount)}</b><span className={`fv-pill ${r.status === "aplicado" ? "is-ok" : r.status === "descartado" ? "is-off" : "is-wait"}`}>{r.status === "aplicado" ? "Con cobro" : r.status === "descartado" ? "Descartado" : "Sin asociar"}</span></div>
          {r.status === "nuevo" && <div className="fv-actions">{cand.map(i => <button key={i.id} className="fv-button secondary" disabled={busy} onClick={() => void run(resolveNotice(org, r.id, i.id))}>Cobrar {i.number}</button>)}
            <button className="fv-link" disabled={busy} onClick={() => void run(resolveNotice(org, r.id, null))}>Descartar</button></div>}</li>; })}</ul>}
  </section>;
}

export type Debtor = { client_id: string; name: string; phone: string; balance: number; limit: number | null; oldest_due: string | null; moves: { id: string; kind: string; amount: number; description: string | null; created_at: string; method: string | null }[] };

/** «Libreta de fiados»: note a fiado or a payment (also for a new customer), see each customer's account and send it by WhatsApp. */
export function FiadosBoard({ org, debtors, clients, currency, business, today }: { org: string; debtors: Debtor[]; clients: { id: string; name: string }[]; currency: string; business: string; today: string }) {
  const sym = currency === "USD" ? "US$" : "S/";
  const fmt = (n: number) => `${sym} ${n.toFixed(2)}`;
  const [kind, setKind] = useState<"cargo" | "abono">("cargo");
  const [isNew, setIsNew] = useState(false);
  const [state, action, pending] = useActionState(fiadoMove.bind(null, org), idle);
  const [openId, setOpenId] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const norm = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  const shown = debtors.filter(d => !q || norm(d.name).includes(norm(q)));
  const date = (iso: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "America/Lima" }).format(new Date(iso));
  const statement = (d: Debtor) => {
    const lines = [...d.moves].reverse().slice(-12).map(x => `${date(x.created_at)} ${x.kind === "cargo" ? "Fiado" : "Abono"}${x.description ? ` (${x.description})` : ""}: ${x.kind === "cargo" ? "" : "-"}${fmt(x.amount)}`);
    return `Hola ${d.name.split(" ")[0]}, te saluda ${business}. Tu cuenta:\n${lines.join("\n")}\nSaldo: ${fmt(d.balance)}. ¡Gracias!`;
  };
  return <section className="fv-board">
    <form action={action} className="fv-create fv-form fv-settings-card" key={state.ok ? state.message : "f"}>
      <div className="fv-segment" role="group" aria-label="Tipo"><button type="button" aria-pressed={kind === "cargo"} onClick={() => setKind("cargo")}>Anotar fiado</button><button type="button" aria-pressed={kind === "abono"} onClick={() => { setKind("abono"); setIsNew(false); }}>Registrar abono</button></div>
      <input type="hidden" name="kind" value={kind} />
      {isNew ? <div className="fv-two"><label>Nombre del cliente nuevo<input name="new_name" maxLength={120} required /></label><label>Celular (para avisarle)<input name="new_phone" inputMode="tel" maxLength={20} /></label></div>
        : <label>Cliente<select name="client_id" required defaultValue=""><option value="" disabled>Elige…</option>{(kind === "abono" ? debtors.map(d => ({ id: d.client_id, name: `${d.name} · debe ${fmt(d.balance)}` })) : clients).map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>}
      {kind === "cargo" && <button type="button" className="fv-link" onClick={() => setIsNew(v => !v)}>{isNew ? "Elegir un cliente que ya existe" : "+ Es un cliente nuevo"}</button>}
      <div className="fv-three"><label>Importe<input name="amount" inputMode="decimal" required placeholder="0.00" /></label>
        {kind === "cargo" ? <label>Paga el (opcional)<input type="date" name="due_date" min={today} /></label>
          : <label>Medio<select name="method" defaultValue="efectivo"><option value="efectivo">Efectivo</option><option value="yape">Yape</option><option value="plin">Plin</option><option value="transferencia">Transferencia</option><option value="tarjeta">Tarjeta</option></select></label>}
        <label>Detalle (opcional)<input name="description" maxLength={200} placeholder={kind === "cargo" ? "Ej.: arroz y aceite" : "Ej.: pagó la mitad"} /></label></div>
      <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : kind === "cargo" ? "Anotar fiado" : "Registrar abono"}</button>
      <Msg m={state} />
    </form>
    {debtors.length > 0 && <label className="fv-search"><span>Buscar cliente</span><input value={q} onChange={e => setQ(e.target.value)} /></label>}
    {!debtors.length ? <div className="fv-empty"><h2>Nadie te debe</h2><p>Anota el primer fiado arriba; también aparecen los que anotas en el móvil.</p></div>
      : <ul className="fv-collect">{shown.map(d => { const late = !!d.oldest_due && d.oldest_due < today; const over = d.limit != null && d.limit > 0 && d.balance > d.limit;
        return <li key={d.client_id} className={late || over ? "is-late" : ""}>
          <div className="fv-collect-main"><strong>{d.name}</strong><small>{d.phone || "Sin celular"}{d.oldest_due ? ` · paga el ${d.oldest_due.slice(8, 10)}/${d.oldest_due.slice(5, 7)}` : ""}{over ? ` · pasó su límite de ${fmt(d.limit!)}` : d.limit ? ` · límite ${fmt(d.limit)}` : ""}</small></div>
          <div className="fv-collect-amount"><b>{fmt(d.balance)}</b>{late && <span className="fv-pill is-off">Vencido</span>}</div>
          <div className="fv-actions"><button className="fv-button secondary" onClick={() => setOpenId(openId === d.client_id ? null : d.client_id)}>{openId === d.client_id ? "Ocultar cuenta" : "Ver cuenta"}</button>
            {d.phone && <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/${d.phone}?text=${encodeURIComponent(statement(d))}`}>Enviar estado de cuenta</a>}</div>
          {openId === d.client_id && <ul className="fv-lines fv-span">{d.moves.map(x => <li key={x.id}><span>{date(x.created_at)} · {x.kind === "cargo" ? "Fiado" : `Abono${x.method ? ` (${x.method})` : ""}`}{x.description ? ` · ${x.description}` : ""}</span><b className={x.kind === "abono" ? "fv-up" : ""}>{x.kind === "abono" ? "−" : "+"}{fmt(x.amount)}</b></li>)}</ul>}
        </li>; })}</ul>}
  </section>;
}
