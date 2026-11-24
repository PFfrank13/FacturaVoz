"use client";
import { useActionState, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  addJobMaterial, addJobPhoto, addMilestone, addPackage, addPrivateNote, addServiceReminder, clientNotice, createKitchenOrder, deleteJob, deletePrivateNote,
  doneServiceReminder, recordConsent, registerVehicle, saveJob, setExpenseJob, setJobStatus, setKitchenStatus, spendPackageSession, type FormResult,
} from "@/app/erp/actions";
import { jobKinds, splitEven, type JobStatus } from "@/lib/erp/rubros";

const idle: FormResult = { ok: false, message: "" };
const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;
export type Opt = { id: string; name: string };

/** A button that runs a server action, asks first if needed, shows the answer and refreshes. */
export function Act({ label, run, confirm, primary = false, link = false }: { label: string; run: () => Promise<FormResult>; confirm?: string; primary?: boolean; link?: boolean }) {
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  return <span className="fv-inline-action">
    <button type="button" className={link ? "fv-link" : primary ? "fv-button" : "fv-button secondary"} disabled={busy} onClick={async () => {
      if (confirm && !window.confirm(confirm)) return;
      setBusy(true); const r = await run().catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); setBusy(false); if (r.ok) router.refresh();
    }}>{busy ? "…" : label}</button>
    <Msg m={m} />
  </span>;
}

/** WhatsApp message that also records the notice date on the server. */
export function NoticeLink({ org, mod, clientId, label, phone, text }: { org: string; mod: "corte" | "morosidad"; clientId: string; label: string; phone: string; text: string }) {
  const router = useRouter();
  return <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/${phone}?text=${encodeURIComponent(text)}`}
    onClick={() => { void clientNotice(org, mod, clientId, "aviso").then(r => { if (r.ok) router.refresh(); }); }}>{label}</a>;
}

export type JobValues = { id: string | null; title: string; client_id: string; kind: string; status: string; assigned_to: string; scheduled_at: string; duration_min: string; address: string; contact_phone: string; notes: string; tech_note: string; amount: string };
export const emptyJob = (kind: string, status: string, at = ""): JobValues => ({ id: null, title: "", client_id: "", kind, status, assigned_to: "", scheduled_at: at, duration_min: kind === "cita" ? "60" : "", address: "", contact_phone: "", notes: "", tech_note: "", amount: "" });

/** New or edit job / appointment. */
export function JobForm({ org, v, statuses, clients, team, appointment, onDone, title }: { org: string; v: JobValues; statuses: JobStatus[]; clients: Opt[]; team: Opt[]; appointment: boolean; onDone?: () => void; title: string }) {
  const [state, action, pending] = useActionState(async (p: FormResult, f: FormData) => { const r = await saveJob(org, v.id, p, f); if (r.ok) onDone?.(); return r; }, idle);
  return <form action={action} className="fv-create fv-form fv-settings-card" key={state.ok && !v.id ? state.message : "j"}>
    <h3>{title}</h3>
    <div className="fv-two"><label>{appointment ? "Servicio o motivo" : "Trabajo"}<input name="title" defaultValue={v.title} maxLength={160} required placeholder={appointment ? "Ej.: corte y barba" : "Ej.: instalación de cámaras"} /></label>
      <label>Cliente<select name="client_id" defaultValue={v.client_id}><option value="">Sin cliente</option>{clients.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label></div>
    <div className="fv-three">
      {appointment ? <input type="hidden" name="kind" value="cita" /> : <label>Tipo<select name="kind" defaultValue={v.kind}>{Object.entries(jobKinds).filter(([k]) => k !== "cita").map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>}
      <label>Estado<select name="status" defaultValue={v.status}>{statuses.map(s => <option key={s.key} value={s.key}>{s.label}</option>)}</select></label>
      <label>{appointment ? "Atiende" : "Técnico"}<select name="assigned_to" defaultValue={v.assigned_to}><option value="">Sin asignar</option>{team.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}</select></label>
    </div>
    <div className="fv-three">
      <label>{appointment ? "Fecha y hora" : "Programado para"}<input type="datetime-local" name="scheduled_at" defaultValue={v.scheduled_at} required={appointment} /></label>
      {appointment ? <label>Duración (min)<input name="duration_min" inputMode="numeric" defaultValue={v.duration_min} /></label> : <label>Monto acordado<input name="amount" inputMode="decimal" defaultValue={v.amount} /></label>}
      <label>Celular de contacto<input name="contact_phone" inputMode="tel" maxLength={20} defaultValue={v.contact_phone} /></label>
    </div>
    {!appointment && <label>Dirección<input name="address" maxLength={250} defaultValue={v.address} /></label>}
    <label>Notas<textarea name="notes" rows={2} maxLength={2000} defaultValue={v.notes} /></label>
    {v.id && !appointment && <label>Nota técnica (interna)<textarea name="tech_note" rows={2} maxLength={2000} defaultValue={v.tech_note} /></label>}
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : v.id ? "Guardar cambios" : appointment ? "Agendar" : "Crear trabajo"}</button>
    <Msg m={state} />
  </form>;
}

export function NewJob(props: Omit<Parameters<typeof JobForm>[0], "onDone">) {
  const [open, setOpen] = useState(false);
  if (!open) return <button className="fv-button" onClick={() => setOpen(true)}>+ {props.appointment ? "Nueva cita" : "Nuevo trabajo"}</button>;
  return <div><JobForm {...props} onDone={() => setOpen(false)} /><button className="fv-link" onClick={() => setOpen(false)}>Cerrar</button></div>;
}

export function StatusPicker({ org, id, current, statuses }: { org: string; id: string; current: string; statuses: JobStatus[] }) {
  const [v, setV] = useState(current);
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  return <span className="fv-inline-action"><select aria-label="Estado" className="fv-status-select" value={v} onChange={async e => { const next = e.target.value; setV(next); const r = await setJobStatus(org, id, next).catch(() => ({ ok: false, message: "Sin conexión." })); if (!r.ok) { setV(current); setM(r); } else router.refresh(); }}>
    {statuses.map(s => <option key={s.key} value={s.key}>{s.label}</option>)}</select><Msg m={m} /></span>;
}

export const DeleteJob = ({ org, id, back }: { org: string; id: string; back: string }) => {
  const router = useRouter();
  return <button className="fv-link fv-neg" onClick={async () => { if (!window.confirm("¿Borrar este trabajo? No se puede deshacer.")) return; const r = await deleteJob(org, id).catch(() => null); if (r?.ok) router.push(back); }}>Borrar</button>;
};

export function MaterialForm({ org, jobId, products }: { org: string; jobId: string; products: Opt[] }) {
  const [state, action, pending] = useActionState(addJobMaterial.bind(null, org, jobId), idle);
  return <form action={action} className="fv-inline-form" key={state.ok ? state.message + Date.now() : "m"}>
    <label className="fv-search"><span>Producto</span><select name="product_id" defaultValue=""><option value="">Otro (escribe abajo)</option>{products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
    <label className="fv-search"><span>Material</span><input name="description" maxLength={200} /></label>
    <label className="fv-search fv-narrow"><span>Cant.</span><input name="quantity" inputMode="decimal" defaultValue="1" /></label>
    <label className="fv-search fv-narrow"><span>Precio</span><input name="unit_price" inputMode="decimal" placeholder="del catálogo" /></label>
    <button className="fv-button secondary" disabled={pending}>Agregar</button><Msg m={state} />
  </form>;
}

export function MilestoneForm({ org, jobId, position }: { org: string; jobId: string; position: number }) {
  const [state, action, pending] = useActionState(addMilestone.bind(null, org, jobId), idle);
  return <form action={action} className="fv-inline-form" key={state.ok ? state.message + position : "h"}>
    <input type="hidden" name="position" value={position} />
    <label className="fv-search"><span>Hito</span><input name="title" maxLength={160} placeholder="Ej.: adelanto 50 %" /></label>
    <label className="fv-search fv-narrow"><span>Monto</span><input name="amount" inputMode="decimal" /></label>
    <label className="fv-search"><span>Vence</span><input type="date" name="due_date" /></label>
    <button className="fv-button secondary" disabled={pending}>Agregar hito</button><Msg m={state} />
  </form>;
}

export function PhotoForm({ org, jobId, clientId }: { org: string; jobId: string; clientId: string | null }) {
  const [state, action, pending] = useActionState(addJobPhoto.bind(null, org, jobId, clientId), idle);
  const ref = useRef<HTMLFormElement>(null);
  return <form ref={ref} action={action} className="fv-inline-form">
    <label className="fv-search"><span>Momento</span><select name="kind" defaultValue="foto"><option value="antes">Antes</option><option value="despues">Después</option><option value="foto">Otra</option></select></label>
    <label className="fv-search"><span>Nota</span><input name="caption" maxLength={200} /></label>
    <label className="fv-button secondary fv-file">{pending ? "Subiendo…" : "Subir foto"}<input type="file" name="photo" hidden accept="image/jpeg,image/png,image/webp" onChange={() => ref.current?.requestSubmit()} /></label>
    <Msg m={state} />
  </form>;
}

export const UseSession = ({ org, id }: { org: string; id: string }) => <Act label="Usar 1" primary run={() => spendPackageSession(org, id)} />;

export function PackageForm({ org, clients }: { org: string; clients: Opt[] }) {
  const [state, action, pending] = useActionState(addPackage.bind(null, org), idle);
  return <form action={action} className="fv-create fv-form fv-settings-card" key={state.ok ? state.message : "p"}>
    <h3>Nuevo paquete</h3>
    <div className="fv-two"><label>Cliente<select name="client_id" required defaultValue=""><option value="" disabled>Elige…</option>{clients.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
      <label>Paquete<input name="name" maxLength={120} required placeholder="Ej.: 10 sesiones de masaje" /></label></div>
    <div className="fv-three"><label>Sesiones<input name="sessions" type="number" min={1} max={500} defaultValue={10} required /></label><label>Precio (opcional)<input name="price" inputMode="decimal" /></label><label>Vence (opcional)<input type="date" name="expires_on" /></label></div>
    <button className="fv-button" disabled={pending}>Guardar paquete</button><Msg m={state} />
  </form>;
}

export function ReminderForm({ org, clients }: { org: string; clients: Opt[] }) {
  const [state, action, pending] = useActionState(addServiceReminder.bind(null, org), idle);
  return <form action={action} className="fv-create fv-form fv-settings-card" key={state.ok ? state.message : "r"}>
    <h3>Recordar a un cliente</h3>
    <div className="fv-three"><label>Cliente<select name="client_id" required defaultValue=""><option value="" disabled>Elige…</option>{clients.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
      <label>¿Qué le toca?<input name="title" maxLength={120} required placeholder="Ej.: cambio de aceite" /></label>
      <label>¿En cuántos días?<input name="days" type="number" min={1} max={730} defaultValue={30} required /></label></div>
    <label>Nota (opcional)<input name="note" maxLength={300} /></label>
    <button className="fv-button" disabled={pending}>Guardar</button><Msg m={state} />
  </form>;
}
export const DoneReminder = ({ org, id }: { org: string; id: string }) => <Act label="Hecho" run={() => doneServiceReminder(org, id)} />;

export function PrivateNoteForm({ org, clientId }: { org: string; clientId: string }) {
  const [state, action, pending] = useActionState(addPrivateNote.bind(null, org, clientId), idle);
  return <form action={action} className="fv-form" key={state.ok ? state.message + Date.now() : "n"}>
    <label>Nueva nota<textarea name="body" rows={4} maxLength={5000} required /></label>
    <button className="fv-button" disabled={pending}>Guardar nota</button><Msg m={state} />
  </form>;
}
export const ConsentButton = ({ org, clientId }: { org: string; clientId: string }) =>
  <Act label="Registrar consentimiento firmado" primary confirm={"Los datos de salud son sensibles (Ley 29733). Antes de guardar notas necesitas el consentimiento POR ESCRITO del paciente. ¿El paciente ya firmó?"} run={() => recordConsent(org, clientId)} />;
export const DeleteNote = ({ org, id }: { org: string; id: string }) => <Act label="Borrar" link confirm="¿Borrar esta nota?" run={() => deletePrivateNote(org, id)} />;

export function VehicleForm({ org, clients, plate }: { org: string; clients: Opt[]; plate: string }) {
  const [state, action, pending] = useActionState(registerVehicle.bind(null, org), idle);
  return <form action={action} className="fv-create fv-form fv-settings-card">
    <h3>Registrar vehículo {plate}</h3>
    <input type="hidden" name="plate" value={plate} />
    <div className="fv-three"><label>Dueño<select name="client_id" required defaultValue=""><option value="" disabled>Elige…</option>{clients.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
      <label>Vehículo<input name="name" maxLength={80} placeholder="Ej.: Toyota Yaris" /></label><label>Modelo / año<input name="model" maxLength={80} /></label></div>
    <button className="fv-button" disabled={pending}>Registrar</button><Msg m={state} />
  </form>;
}

export const NoticeAction = ({ org, mod, clientId, action, label }: { org: string; mod: "corte" | "morosidad"; clientId: string; action: "cortado" | "activo"; label: string }) =>
  <Act label={label} confirm={action === "cortado" ? "¿Registrar el corte del servicio?" : undefined} run={() => clientNotice(org, mod, clientId, action)} />;

export function AssignExpense({ org, jobs, expenses }: { org: string; jobs: Opt[]; expenses: { id: string; label: string }[] }) {
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  if (!expenses.length) return <p className="fv-muted">No hay gastos sin obra en los últimos 120 días. Regístralos en Gastos o Escanear comprobante.</p>;
  return <><ul className="fv-lines">{expenses.map(e => <li key={e.id}><span>{e.label}</span>
    <select aria-label="Asignar a la obra" defaultValue="" onChange={async ev => { if (!ev.target.value) return; const r = await setExpenseJob(org, e.id, ev.target.value).catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); if (r.ok) router.refresh(); }}>
      <option value="">Asignar a…</option>{jobs.map(j => <option key={j.id} value={j.id}>{j.name}</option>)}</select></li>)}</ul><Msg m={m} /></>;
}

// ── Cocina y mesas ──
export type KitchenOrder = { id: string; number: string; table: string | null; fulfillment: string | null; status: string; notes: string; created_at: string; client: string; items: { description: string; quantity: number; note: string }[] };
const flow = ["nuevo", "preparando", "listo", "entregado"] as const;
const flowLabel: Record<string, string> = { nuevo: "Nuevos", preparando: "Preparando", listo: "Listos" };
const nextLabel: Record<string, string> = { nuevo: "Empezar", preparando: "Listo", listo: "Entregado" };

export function KitchenBoard({ org, orders, products }: { org: string; orders: KitchenOrder[]; products: (Opt & { price: number })[] }) {
  const [view, setView] = useState<"comandas" | "mesas" | "pedido">("comandas");
  const router = useRouter();
  const mins = (iso: string) => Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60000));
  const tables = useMemo(() => {
    const m = new Map<string, { orders: number; items: number }>();
    for (const o of orders) if (o.table) { const t = m.get(o.table) ?? { orders: 0, items: 0 }; t.orders++; t.items += o.items.reduce((s, i) => s + i.quantity, 0); m.set(o.table, t); }
    return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0], "es", { numeric: true }));
  }, [orders]);
  return <section className="fv-board">
    <div className="fv-segment" role="group" aria-label="Vista">
      {(["comandas", "mesas", "pedido"] as const).map(v => <button key={v} aria-pressed={view === v} onClick={() => setView(v)}>{v === "comandas" ? "Comandas" : v === "mesas" ? "Mesas" : "Tomar pedido"}</button>)}
    </div>
    {view === "pedido" ? <TakeOrder org={org} products={products} onDone={() => { setView("comandas"); router.refresh(); }} />
      : view === "mesas" ? (!tables.length ? <div className="fv-empty"><h2>Ninguna mesa con pedidos</h2><p>Cuando pidan desde el QR de la mesa o tomes un pedido, aparecerán aquí.</p></div>
        : <ul className="fv-tables">{tables.map(([t, v]) => <li key={t}><strong>Mesa {t}</strong><small>{v.items} {v.items === 1 ? "plato" : "platos"} · {v.orders} {v.orders === 1 ? "pedido" : "pedidos"}</small></li>)}</ul>)
      : !orders.length ? <div className="fv-empty"><h2>Cocina libre</h2><p>Los pedidos de las mesas (QR), de la tienda y los que tomes aquí aparecen al instante.</p></div>
      : <div className="fv-kitchen">{flow.slice(0, 3).map(s => <section key={s} className={`fv-kitchen-col k-${s}`}><h3>{flowLabel[s]} ({orders.filter(o => o.status === s).length})</h3>
        {orders.filter(o => o.status === s).map(o => <article key={o.id} className="fv-ticket">
          <header><strong>{o.table ? `Mesa ${o.table}` : o.fulfillment === "delivery" ? "Delivery" : "Para llevar"}</strong><small>{o.number} · hace {mins(o.created_at)} min</small></header>
          <ul>{o.items.map((i, k) => <li key={k}><b>{Number.isInteger(i.quantity) ? i.quantity : i.quantity.toFixed(2)} ×</b> {i.description}{i.note && <small>Nota: {i.note}</small>}</li>)}</ul>
          {o.notes && <p className="fv-muted">📝 {o.notes}</p>}
          <Act label={nextLabel[s]} primary run={() => setKitchenStatus(org, o.id, flow[flow.indexOf(s) + 1] as "preparando" | "listo" | "entregado")} />
        </article>)}</section>)}</div>}
  </section>;
}

function TakeOrder({ org, products, onDone }: { org: string; products: (Opt & { price: number })[]; onDone: () => void }) {
  const [table, setTable] = useState("");
  const [q, setQ] = useState("");
  const [lines, setLines] = useState<{ id: string; name: string; qty: number; note: string }[]>([]);
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const req = useRef(crypto.randomUUID());
  const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const list = products.filter(p => !q || norm(p.name).includes(norm(q))).slice(0, 40);
  const add = (p: Opt) => setLines(l => l.some(x => x.id === p.id) ? l.map(x => x.id === p.id ? { ...x, qty: x.qty + 1 } : x) : [...l, { id: p.id, name: p.name, qty: 1, note: "" }]);
  async function send() {
    setBusy(true); setM(null);
    const r = await createKitchenOrder(org, { request_id: req.current, table: table.trim(), items: lines.map(l => ({ product_id: l.id, quantity: l.qty, note: l.note || undefined })) }).catch(() => ({ ok: false, message: "Sin conexión. Vuelve a enviar: no se duplicará." }));
    setBusy(false); setM(r);
    if (r.ok) { req.current = crypto.randomUUID(); setLines([]); setTable(""); onDone(); }
  }
  return <div className="fv-take-order">
    <section className="fv-create" style={{ padding: 16 }}>
      <label className="fv-search"><span>Buscar plato</span><input value={q} onChange={e => setQ(e.target.value)} /></label>
      <div className="fv-chips">{list.map(p => <button key={p.id} className="fv-chip" onClick={() => add(p)}>{p.name}</button>)}</div>
    </section>
    <aside className="fv-create" style={{ padding: 16 }}>
      <label className="fv-search"><span>Mesa (vacío = para llevar)</span><input value={table} maxLength={12} onChange={e => setTable(e.target.value)} /></label>
      {!lines.length ? <p className="fv-muted">Toca los platos para agregarlos.</p> : <ul className="fv-lines">{lines.map(l => <li key={l.id}>
        <span><strong>{l.name}</strong><input aria-label={`Nota para ${l.name}`} placeholder="Nota (sin ají, término medio…)" value={l.note} maxLength={200} onChange={e => setLines(x => x.map(y => y.id === l.id ? { ...y, note: e.target.value } : y))} /></span>
        <span className="fv-pos-qty"><button onClick={() => setLines(x => x.flatMap(y => y.id === l.id ? (y.qty > 1 ? [{ ...y, qty: y.qty - 1 }] : []) : [y]))}>−</button><b>{l.qty}</b><button onClick={() => setLines(x => x.map(y => y.id === l.id ? { ...y, qty: y.qty + 1 } : y))}>+</button></span></li>)}</ul>}
      <button className="fv-button" disabled={busy || !lines.length} onClick={() => void send()}>{busy ? "Enviando…" : "Enviar a cocina"}</button>
      <Msg m={m} />
    </aside>
  </div>;
}

/** Split the bill with an optional tip (the tip is for the team, not on the receipt). */
export function SplitBill({ currency, business }: { currency: string; business: string }) {
  const [total, setTotal] = useState("");
  const [people, setPeople] = useState(2);
  const [tip, setTip] = useState(0);
  const sym = currency === "USD" ? "US$" : "S/";
  const t = Number(total.replace(",", ".")) || 0;
  const tipAmount = Math.round(t * tip) / 100;
  const parts = splitEven(t + tipAmount, people);
  const text = `Cuenta en ${business}: ${sym} ${t.toFixed(2)}${tipAmount > 0 ? ` + propina ${sym} ${tipAmount.toFixed(2)}` : ""}. Entre ${people}: ${parts.map(p => `${sym} ${p.toFixed(2)}`).join(", ")}.`;
  return <section className="fv-create fv-form fv-settings-card">
    <h3>Dividir la cuenta</h3>
    <div className="fv-two"><label>Total de la cuenta<input inputMode="decimal" value={total} onChange={e => setTotal(e.target.value)} placeholder="0.00" /></label>
      <label>¿Entre cuántos?<span className="fv-pos-qty"><button type="button" onClick={() => setPeople(p => Math.max(1, p - 1))}>−</button><b>{people}</b><button type="button" onClick={() => setPeople(p => Math.min(50, p + 1))}>+</button></span></label></div>
    <div className="fv-chips">{[0, 5, 10, 15].map(p => <button type="button" key={p} className="fv-chip" aria-pressed={tip === p} onClick={() => setTip(p)}>{p ? `${p} % de propina` : "Sin propina"}</button>)}</div>
    {t > 0 && <><ul className="fv-lines">{parts.map((p, i) => <li key={i}><span>Persona {i + 1}</span><b>{sym} {p.toFixed(2)}</b></li>)}</ul>
      <a className="fv-button secondary" target="_blank" rel="noreferrer" href={`https://wa.me/?text=${encodeURIComponent(text)}`}>Mandar el detalle por WhatsApp</a></>}
    <p className="fv-caption">La propina es voluntaria y va para el equipo: no entra al comprobante.</p>
  </section>;
}
