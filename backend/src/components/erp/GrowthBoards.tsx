"use client";
import type React from "react";
import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { confirmBankMatch, deleteRecurring, ignoreBankLine, importBankLines, runRecurringNow, saveRecurring, saveStore, setInStore, setSurveyAuto, setTaxRegime, toggleRecurring, type FormResult } from "@/app/erp/actions";
import { fingerprint, parseBankTable, parseCsv } from "@/lib/erp/bank";

const idle: FormResult = { ok: false, message: "" };
const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;

/** Small helper: a button that runs a server action and shows its answer. */
function ActionButton({ label, busyLabel, run, secondary = true, confirm }: { label: string; busyLabel?: string; run: () => Promise<FormResult>; secondary?: boolean; confirm?: string }) {
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  return <span className="fv-inline-action">
    <button className={secondary ? "fv-button secondary" : "fv-button"} disabled={busy} onClick={async () => {
      if (confirm && !window.confirm(confirm)) return;
      setBusy(true); const r = await run().catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); setBusy(false); if (r.ok) router.refresh();
    }}>{busy ? busyLabel ?? "…" : label}</button>
    <Msg m={m} />
  </span>;
}

// ── ¿Cuánto me queda? ──
const regimes = [["nrus", "Nuevo RUS"], ["rer", "RER"], ["rmt", "MYPE Tributario"], ["general", "General"]] as const;
export function RegimePicker({ org, current, canSave }: { org: string; current: string | null; canSave: boolean }) {
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  return <div className="fv-board-tools"><div className="fv-segment" role="group" aria-label="Tu régimen tributario">
    {regimes.map(([id, label]) => <button key={id} aria-pressed={current === id} disabled={!canSave} onClick={async () => { const r = await setTaxRegime(org, id); setM(r); if (r.ok) router.refresh(); }}>{label}</button>)}
  </div>{!canSave && <small className="fv-muted">Solo el dueño o un administrador cambia el régimen.</small>}<Msg m={m} /></div>;
}

// ── Facturación recurrente ──
export function RecurringForm({ org, currency }: { org: string; currency: string }) {
  const [state, action, pending] = useActionState(saveRecurring.bind(null, org), idle);
  return <details className="fv-create">
    <summary className="fv-button">+ Nueva mensualidad</summary>
    <form action={action} className="fv-form" key={state.ok ? state.message : "f"}>
      <div className="fv-two"><label>Cliente<input name="client_name" required maxLength={120} /></label><label>DNI o RUC (opcional)<input name="client_tax_id" maxLength={15} inputMode="numeric" /></label></div>
      <div className="fv-two"><label>Concepto<input name="description" required maxLength={200} placeholder="Alquiler, mensualidad, pensión…" /></label><label>Importe con IGV ({currency})<input name="amount" required inputMode="decimal" placeholder="0.00" /></label></div>
      <div className="fv-two"><label>Día del mes en que se factura<input name="day_of_month" type="number" min={1} max={31} defaultValue={1} required /></label><label>Días para pagar<input name="due_days" type="number" min={0} max={90} defaultValue={7} /></label></div>
      <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar mensualidad"}</button>
      <Msg m={state} />
    </form>
  </details>;
}
export const RecurringRun = ({ org }: { org: string }) => <ActionButton label="Generar las de hoy ahora" busyLabel="Generando…" run={() => runRecurringNow(org)} />;
export function RecurringActions({ org, id, active }: { org: string; id: string; active: boolean }) {
  return <span className="fv-actions">
    <ActionButton label={active ? "Pausar" : "Activar"} run={() => toggleRecurring(org, id, !active)} />
    <ActionButton label="Borrar" run={() => deleteRecurring(org, id)} confirm="¿Borrar esta mensualidad? Los comprobantes ya generados se quedan." />
  </span>;
}

// ── Tienda en línea ──
export function StoreForm({ org, slug, enabled, headline, whatsapp, base }: { org: string; slug: string; enabled: boolean; headline: string; whatsapp: string; base: string }) {
  const [state, action, pending] = useActionState(saveStore.bind(null, org), idle);
  const [s, setS] = useState(slug);
  return <form action={action} className="fv-form fv-create" style={{ padding: 18 }}>
    <label>Dirección de tu tienda<span className="fv-store-url"><small>{base}/tienda/</small><input name="slug" value={s} onChange={e => setS(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, ""))} required minLength={3} maxLength={41} /></span></label>
    <label>Frase de bienvenida<input name="headline" defaultValue={headline} maxLength={140} placeholder="Todo para tu casa, a un mensaje de distancia" /></label>
    <label>WhatsApp donde llegan los pedidos<input name="whatsapp" defaultValue={whatsapp} inputMode="tel" maxLength={20} placeholder="987654321" /></label>
    <label className="fv-check"><input type="checkbox" name="enabled" defaultChecked={enabled} /> Tienda publicada (visible para tus clientes)</label>
    <div className="fv-actions"><button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar tienda"}</button>
      {s.length >= 3 && <a className="fv-button secondary" href={`/tienda/${s}`} target="_blank" rel="noopener noreferrer">Ver mi tienda</a>}</div>
    <Msg m={state} />
  </form>;
}
export function InStoreToggle({ org, id, on }: { org: string; id: string; on: boolean }) {
  const [v, setV] = useState(on);
  const [busy, setBusy] = useState(false);
  return <label className="fv-check"><input type="checkbox" checked={v} disabled={busy} onChange={async e => { const next = e.target.checked; setBusy(true); setV(next); const r = await setInStore(org, id, next); if (!r.ok) setV(!next); setBusy(false); }} /> {v ? "En la tienda" : "Oculto"}</label>;
}

// ── Encuestas ──
export function SurveyToggle({ org, on, canSave }: { org: string; on: boolean; canSave: boolean }) {
  const [v, setV] = useState(on);
  const [m, setM] = useState<FormResult | null>(null);
  return <div className="fv-board-tools"><label className="fv-check"><input type="checkbox" checked={v} disabled={!canSave} onChange={async e => { const next = e.target.checked; setV(next); const r = await setSurveyAuto(org, next); setM(r); if (!r.ok) setV(!next); }} /> Enviar la encuesta sola después de cada venta con correo</label><Msg m={m} /></div>;
}

// ── Conciliación bancaria ──
export function BankImport({ org }: { org: string }) {
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  return <div className="fv-create" style={{ padding: 18 }}>
    <h3>Sube el extracto de tu banco</h3>
    <p className="fv-caption">Descárgalo de tu banca por internet (BCP, Interbank, BBVA, Scotiabank…) como CSV y súbelo aquí. Detectamos fecha, detalle, monto y operación; lo repetido no se vuelve a cargar.</p>
    <input type="file" accept=".csv,text/csv,.txt" disabled={busy} onChange={async e => {
      const f = e.target.files?.[0]; if (!f) return;
      setBusy(true); setM(null);
      try {
        const text = await f.text();
        const lines = parseBankTable(parseCsv(text));
        if (!lines.length) { setM({ ok: false, message: "No encontré movimientos. Revisa que el archivo tenga columnas de fecha y monto (o abono/cargo)." }); return; }
        const r = await importBankLines(org, lines.map(l => ({ ...l, description: l.description.slice(0, 300), reference: l.reference.slice(0, 80), fingerprint: fingerprint(l) })), f.name);
        setM(r); if (r.ok) router.refresh();
      } catch { setM({ ok: false, message: "No pude leer el archivo." }); }
      finally { setBusy(false); e.target.value = ""; }
    }} />
    {busy && <p className="fv-caption">Leyendo el extracto…</p>}
    <Msg m={m} />
  </div>;
}
export function BankMatch({ org, lineId, invoiceId, label }: { org: string; lineId: string; invoiceId: string | null; label: string }) {
  return <span className="fv-actions">
    {invoiceId && <ActionButton label={label} secondary={false} run={() => confirmBankMatch(org, lineId, invoiceId)} />}
    <ActionButton label="No es un cobro" run={() => ignoreBankLine(org, lineId)} />
  </span>;
}

// ── Importar desde Excel ──
type Preview = { counts?: Record<string, number>; totals?: { net?: Record<string, number> }; sheets?: { name: string; role: string; rows: number }[]; warnings?: { message?: string }[] };
type Analysis = { preview: Preview; payload: { clients?: unknown[]; products?: unknown[]; docs?: unknown[] }; file: string };
const chunks = <T,>(l: T[], n: number) => Array.from({ length: Math.ceil(l.length / n) }, (_, i) => l.slice(i * n, i * n + n));

export function ImportBoard({ org, taxRate }: { org: string; taxRate: number }) {
  const [a, setA] = useState<Analysis | null>(null);
  const [step, setStep] = useState("");
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  async function analyze(f: File) {
    setM(null); setA(null); setStep("Leyendo el archivo…");
    try {
      const { data } = await createClient().auth.getSession();
      const res = await fetch(`/api/import/workbook?rate=${taxRate}`, { method: "POST", headers: { "content-type": "application/octet-stream", ...(data.session ? { authorization: `Bearer ${data.session.access_token}` } : {}) }, body: await f.arrayBuffer() });
      const j = await res.json().catch(() => ({}));
      if (!res.ok) { setM({ ok: false, message: j.error ?? "No pude leer el Excel." }); return; }
      setA({ preview: j.preview, payload: j.payload, file: f.name });
    } catch { setM({ ok: false, message: "Sin conexión." }); }
    finally { setStep(""); }
  }
  async function run() {
    if (!a) return;
    const db = createClient();
    try {
      setStep("Preparando…");
      const counts = a.preview.counts ?? {};
      const { data: job, error } = await db.rpc("wb_import_begin", { p_org: org, p_file: a.file.slice(0, 200), p_expected: { ...counts, net: a.preview.totals?.net ?? {} }, p_warnings: a.preview.warnings ?? [] });
      if (error || !job) throw new Error(error?.message);
      const clients = a.payload.clients ?? [], products = a.payload.products ?? [], docs = a.payload.docs ?? [];
      let done = 0;
      for (const c of chunks(clients, 1000)) { const r = await db.rpc("wb_import_clients", { p_job: job, p_rows: c }); if (r.error) throw new Error(r.error.message); done += c.length; setStep(`Clientes ${done}/${clients.length}`); }
      done = 0;
      for (const c of chunks(products, 500)) { const r = await db.rpc("wb_import_products", { p_job: job, p_rows: c }); if (r.error) throw new Error(r.error.message); done += c.length; setStep(`Productos ${done}/${products.length}`); }
      done = 0;
      for (const c of chunks(docs, 200)) { const r = await db.rpc("wb_import_docs", { p_job: job, p_docs: c }); if (r.error) throw new Error(r.error.message); done += c.length; setStep(`Comprobantes ${done}/${docs.length}`); }
      const fin = await db.rpc("wb_import_finish", { p_job: job });
      if (fin.error) throw new Error(fin.error.message);
      setA(null); setM({ ok: true, message: "Importación terminada. Si algo salió mal, puedes deshacerla desde el móvil (Importar → Historial)." }); router.refresh();
    } catch { setM({ ok: false, message: "La importación se detuvo. Revisa tu conexión y vuelve a intentarlo: lo ya importado no se duplica." }); }
    finally { setStep(""); }
  }
  const c = a?.preview.counts ?? {};
  return <div className="fv-create" style={{ padding: 18 }}>
    <h3>Trae tu información desde Excel</h3>
    <p className="fv-caption">Clientes, productos y comprobantes de tu sistema anterior (.xlsx, hasta 4 MB). Primero ves qué encontramos; nada se guarda hasta que confirmas.</p>
    <input type="file" accept=".xlsx" disabled={!!step} onChange={e => { const f = e.target.files?.[0]; if (f) void analyze(f); e.target.value = ""; }} />
    {a && <div className="fv-kpis" style={{ marginTop: 14 }}>
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Clientes</span><strong>{c.clients ?? 0}</strong></div>
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Productos</span><strong>{c.products ?? 0}</strong></div>
      <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Comprobantes</span><strong>{c.documents ?? 0}</strong></div>
    </div>}
    {a?.preview.warnings?.slice(0, 5).map((w, i) => <p key={i} className="fv-note-box">{w.message}</p>)}
    {a && <button className="fv-button" disabled={!!step} onClick={() => void run()}>Importar ahora</button>}
    {step && <p className="fv-caption" aria-live="polite">{step}</p>}
    <Msg m={m} />
  </div>;
}
