"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { setOwnerPin, type FormResult } from "@/app/erp/actions";

const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;

/** «PIN del dueño»: set, change (needs the current PIN) or turn off. */
export function OwnerPinForm({ org, enabled }: { org: string; enabled: boolean }) {
  const [current, setCurrent] = useState("");
  const [pin, setPin] = useState("");
  const [again, setAgain] = useState("");
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  const digits = (v: string) => v.replace(/\D/g, "").slice(0, 8);
  async function save(off: boolean) {
    setM(null);
    if (!off && !/^\d{4,8}$/.test(pin)) { setM({ ok: false, message: "El PIN nuevo debe tener de 4 a 8 dígitos." }); return; }
    if (!off && pin !== again) { setM({ ok: false, message: "Los dos PIN nuevos no coinciden." }); return; }
    if (enabled && !current) { setM({ ok: false, message: "Escribe el PIN actual del dueño." }); return; }
    if (off && !window.confirm("¿Desactivar el PIN del dueño? Tu equipo podrá anular y borrar cobros sin pedirlo.")) return;
    setBusy(true);
    const r = await setOwnerPin(org, off ? null : pin, enabled ? current : null).catch(() => ({ ok: false, message: "Sin conexión." }));
    setBusy(false); setM(r);
    if (r.ok) { setCurrent(""); setPin(""); setAgain(""); router.refresh(); }
  }
  return <form className="fv-create fv-form fv-pin-form" onSubmit={e => { e.preventDefault(); void save(false); }}>
    <h3>{enabled ? "Cambiar el PIN del dueño" : "Activar el PIN del dueño"}</h3>
    {enabled && <label>PIN actual del dueño<input type="password" inputMode="numeric" autoComplete="off" value={current} onChange={e => setCurrent(digits(e.target.value))} /></label>}
    <div className="fv-two">
      <label>PIN nuevo (4 a 8 dígitos)<input type="password" inputMode="numeric" autoComplete="new-password" value={pin} onChange={e => setPin(digits(e.target.value))} /></label>
      <label>Repite el PIN nuevo<input type="password" inputMode="numeric" autoComplete="new-password" value={again} onChange={e => setAgain(digits(e.target.value))} /></label>
    </div>
    <div className="fv-actions">
      <button className="fv-button" disabled={busy}>{busy ? "Guardando…" : enabled ? "Cambiar PIN" : "Activar PIN"}</button>
      {enabled && <button type="button" className="fv-button secondary" disabled={busy} onClick={() => void save(true)}>Desactivar</button>}
    </div>
    <p className="fv-caption">¿Lo olvidaste? Entra a la app con el código que llega a tu correo y podrás crear uno nuevo sin el actual.</p>
    <Msg m={m} />
  </form>;
}

type Item = Record<string, unknown>;
export type AgentTask = { id: string; title: string; prompt: string; status: string; created_at: string; results: Item[]; summary: string | null };
const statusLabel: Record<string, string> = { proposed: "Por aprobar", approved: "Aprobada", done: "Hecha", rejected: "Rechazada", failed: "Falló" };
const money = (v: unknown) => `S/ ${(Number(v) || 0).toFixed(2)}`;

async function bearer(): Promise<Record<string, string>> {
  const { data } = await createClient().auth.getSession();
  return data.session ? { authorization: `Bearer ${data.session.access_token}` } : {};
}

/** «Tareas del Copiloto»: write what you want; it prepares it and nothing happens until you approve. */
export function AgentBoard({ org, tasks }: { org: string; tasks: AgentTask[] }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  async function ask() {
    if (!text.trim()) return;
    setBusy("new"); setM(null);
    try {
      const res = await fetch("/api/agent", { method: "POST", headers: { "content-type": "application/json", ...(await bearer()) }, body: JSON.stringify({ org_id: org, text: text.trim() }) });
      const j = await res.json().catch(() => ({}));
      if (!res.ok) { setM({ ok: false, message: j.error ?? "No pude preparar la tarea." }); return; }
      setText(""); setM({ ok: true, message: "Tarea preparada: revísala abajo y apruébala si está bien." }); router.refresh();
    } catch { setM({ ok: false, message: "Sin conexión." }); }
    finally { setBusy(null); }
  }
  async function decide(id: string, approve: boolean) {
    setBusy(id); setM(null);
    try {
      const res = await fetch("/api/agent/decide", { method: "POST", headers: { "content-type": "application/json", ...(await bearer()) }, body: JSON.stringify({ task_id: id, decision: approve ? "approve" : "reject" }) });
      const j = await res.json().catch(() => ({}));
      setM(res.ok ? { ok: true, message: approve ? "Tarea aprobada y hecha." : "Tarea rechazada." } : { ok: false, message: j.error ?? "No se pudo registrar tu decisión." });
      router.refresh();
    } catch { setM({ ok: false, message: "Sin conexión." }); }
    finally { setBusy(null); }
  }
  const examples = ["Prepara los mensajes de cobro de esta semana", "Arma la lista de lo que tengo que reponer", "Programa recordatorios para los que me deben", "Hazme el resumen de la semana"];
  return <section className="fv-board">
    <form className="fv-create fv-agent-ask" onSubmit={e => { e.preventDefault(); void ask(); }}>
      <label className="fv-search"><span>¿Qué quieres que prepare?</span><textarea rows={2} maxLength={800} value={text} onChange={e => setText(e.target.value)} placeholder="Ej.: prepara los mensajes para cobrarle a los que me deben" /></label>
      <div className="fv-chips">{examples.map(x => <button type="button" key={x} className="fv-chip" onClick={() => setText(x)}>{x}</button>)}</div>
      <button className="fv-button" disabled={busy === "new" || !text.trim()}>{busy === "new" ? "Preparando…" : "Encargar tarea"}</button>
      <p className="fv-caption">El Copiloto no envía nada a tus clientes ni mueve dinero: prepara la tarea y solo se hace cuando la apruebas.</p>
    </form>
    <Msg m={m} />
    {!tasks.length ? <div className="fv-empty"><h2>Aún no le encargaste tareas</h2><p>Prueba con uno de los ejemplos de arriba.</p></div>
      : <ul className="fv-agent-tasks">{tasks.map(t => <li key={t.id}>
        <header><strong>{t.title}</strong><span className={`fv-pill ${t.status === "proposed" ? "is-wait" : t.status === "done" || t.status === "approved" ? "is-ok" : "is-off"}`}>{statusLabel[t.status] ?? t.status}</span></header>
        <small>«{t.prompt}»</small>
        {t.results.map((r, i) => <AgentStep key={i} r={r} />)}
        {t.summary && <p className="fv-ok">{t.summary}</p>}
        {t.status === "proposed" && <div className="fv-actions">
          <button className="fv-button" disabled={busy === t.id} onClick={() => void decide(t.id, true)}>{busy === t.id ? "Haciendo…" : "Aprobar"}</button>
          <button className="fv-button secondary" disabled={busy === t.id} onClick={() => void decide(t.id, false)}>Rechazar</button>
          <small className="fv-muted">Al aprobar, solo se programan los recordatorios (si los hay). No se envía nada a tus clientes.</small>
        </div>}
      </li>)}</ul>}
  </section>;
}

function AgentStep({ r }: { r: Item }) {
  const items = Array.isArray(r.items) ? (r.items as Item[]) : [];
  const [copied, setCopied] = useState<number | null>(null);
  if (r.action === "cobranza") return <div className="fv-agent-step"><h4>Mensajes de cobro ({items.length})</h4>
    {!items.length ? <p className="fv-muted">Nadie tiene deuda pendiente.</p> : <ul className="fv-lines">{items.map((i, k) => <li key={k}><span><strong>{String(i.client ?? "")} · {money(i.balance)}</strong><small>{String(i.message ?? "")}</small></span>
      <button className="fv-button secondary" onClick={() => { void navigator.clipboard?.writeText(String(i.message ?? "")); setCopied(k); }}>{copied === k ? "Copiado" : "Copiar"}</button></li>)}</ul>}</div>;
  if (r.action === "reposicion") return <div className="fv-agent-step"><h4>Lista de compras ({items.length})</h4>
    {!items.length ? <p className="fv-muted">Nada está por acabarse.</p> : <ul>{items.map((i, k) => <li key={k}>{String(i.product ?? "")}: quedan {String(i.stock ?? "")}, sugiero pedir {String(i.suggested ?? "")}</li>)}</ul>}</div>;
  if (r.action === "recordatorios") return <div className="fv-agent-step"><h4>Recordatorios de cobro ({items.filter(i => i.client_id != null).length})</h4>
    <ul>{items.map((i, k) => <li key={k}>{i.client_id == null ? "⚠️ " : ""}{String(i.client ?? "")} · {money(i.balance)} · {String(i.due_on ?? "")}{i.client_id == null ? " (no lo programo: nombre repetido o sin ficha)" : ""}</li>)}</ul></div>;
  const lines = Array.isArray(r.lines) ? (r.lines as unknown[]) : [];
  return <div className="fv-agent-step"><h4>Resumen de la semana</h4><ul>{lines.map((l, k) => <li key={k}>{String(l)}</li>)}</ul></div>;
}
