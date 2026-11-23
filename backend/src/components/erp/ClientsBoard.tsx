"use client";
import { useActionState, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useRouter } from "next/navigation";
import { addCreditMove, getClientFile, lookupClientDocument, saveClient, type ClientFile, type ClientSaveResult, type FormResult } from "@/app/erp/actions";
import { docLabel, matchesClient, summarizeClients, waPhone, type ClientFilter, type ClientView } from "@/lib/erp/clients";

const fmt = (value: number, currency: string) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(value);
const day = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", timeZone: "UTC" }).format(new Date(`${d.slice(0, 10)}T12:00:00Z`));
const ago = (days: number | null) => days === null ? "Sin compras" : days === 0 ? "Compró hoy" : days === 1 ? "Compró ayer" : `Compró hace ${days} días`;
const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase();

const filters: { id: ClientFilter; label: string }[] = [
  { id: "todos", label: "Todos" }, { id: "con_deuda", label: "Con fiado" },
  { id: "vencidos", label: "Vencidos o sobre límite" }, { id: "sin_volver", label: "No están volviendo" },
];

/** Customers shared with the mobile app: DNI/RUC lookup, purchases, fiado balance and payments. */
export default function ClientsBoard({ org, clients, currency, canFiado }: { org: string; clients: ClientView[]; currency: string; canFiado: boolean }) {
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState<ClientFilter>("todos");
  const [openId, setOpenId] = useState<string | "new" | null>(null);
  const visible = useMemo(() => clients.filter(c => matchesClient(c, q, filter)), [clients, q, filter]);
  const s = summarizeClients(clients);
  const open = openId === "new" ? null : clients.find(c => c.id === openId) ?? null;
  return <section className="fv-board">
    <div className="fv-kpis">
      <div style={{ "--tone": "#6fb7ff" } as React.CSSProperties}><span>Clientes</span><strong>{s.count}</strong><small>compartidos con el móvil</small></div>
      <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Por cobrar en fiados</span><strong>{fmt(s.receivable, currency)}</strong><small>{s.debtors} {s.debtors === 1 ? "cliente debe" : "clientes deben"}</small></div>
      <div style={{ "--tone": s.attention ? "#ff7a6e" : "#a98bff" } as React.CSSProperties}><span>Requieren atención</span><strong>{s.attention}</strong><small>fiado vencido o sobre su límite</small></div>
    </div>
    <div className="fv-board-tools">
      <label className="fv-search"><span>Buscar</span><input type="search" value={q} onChange={e => setQ(e.target.value)} placeholder="Nombre, DNI, RUC o teléfono…" /></label>
      <div className="fv-segment" role="group" aria-label="Filtrar clientes">
        {filters.map(f => <button key={f.id} aria-pressed={filter === f.id} onClick={() => setFilter(f.id)}>{f.label}</button>)}
      </div>
      <button className="fv-button" onClick={() => setOpenId("new")}>Nuevo cliente</button>
    </div>
    <p className="fv-caption" aria-live="polite">{visible.length} {visible.length === 1 ? "cliente" : "clientes"}</p>
    <ul className="fv-receipts fv-clients">
      {visible.map((c, i) => <li key={c.id} style={{ "--i": Math.min(i, 14) } as React.CSSProperties}>
        <button onClick={() => setOpenId(c.id)} aria-label={`${c.name}${c.balance > 0 ? `, debe ${fmt(c.balance, currency)}` : ""}`}>
          <span className="fv-avatar" aria-hidden="true">{initials(c.name) || "?"}</span>
          <span className="fv-receipt-main">
            <strong>{c.name}</strong>
            <small>{[c.tax_id ? `${docLabel(c)} ${c.tax_id}` : "", c.phone ?? ""].filter(Boolean).join(" · ") || "Sin documento"}</small>
          </span>
          <span className="fv-receipt-date">{ago(c.daysSince)}</span>
          {c.balance > 0
            ? <span className={`fv-pill ${c.overdue || c.overLimit ? "is-bad" : "is-wait"}`}>{c.overLimit ? "Sobre su límite" : c.overdue ? "Fiado vencido" : "Con fiado"}</span>
            : <span className="fv-pill is-ok">Al día</span>}
          <span className="fv-receipt-total">{c.balance > 0 ? fmt(c.balance, currency) : c.purchases ? `${c.purchases} compras` : "—"}</span>
        </button>
      </li>)}
    </ul>
    {!visible.length && <div className="fv-empty"><h2>{q || filter !== "todos" ? "Sin coincidencias" : "Todavía no hay clientes"}</h2><p>Crea clientes aquí o desde el punto de venta del móvil: con el DNI o RUC se completan solos.</p>
      {!q && filter === "todos" && <button className="fv-button" onClick={() => setOpenId("new")}>Crear el primero</button>}</div>}
    {openId && <ClientSheet key={openId} org={org} client={open} currency={currency} canFiado={canFiado} onClose={() => setOpenId(null)} onCreated={id => setOpenId(id)} />}
  </section>;
}

function ClientSheet({ org, client, currency, canFiado, onClose, onCreated }: {
  org: string; client: ClientView | null; currency: string; canFiado: boolean; onClose: () => void; onCreated: (id: string) => void;
}) {
  const panel = useRef<HTMLDivElement>(null);
  const [file, setFile] = useState<ClientFile | null>(null);
  const [editing, setEditing] = useState(client === null);
  const clientId = client?.id ?? null;
  const reload = () => { if (clientId) getClientFile(org, clientId).then(setFile); };
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    let alive = true;
    if (clientId) getClientFile(org, clientId).then(f => { if (alive) setFile(f); });
    return () => { alive = false; };
  }, [org, clientId]);
  useEffect(() => {
    panel.current?.focus();
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") close.current(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  const root = typeof document === "undefined" ? null : document.querySelector(".fv-workspace");
  const wa = client ? waPhone(client.phone) : "";
  const reminder = client && client.balance > 0
    ? `Hola ${client.name.split(" ")[0]}, te escribimos para recordarte tu saldo pendiente de ${fmt(client.balance, currency)}. ¡Gracias por tu preferencia!`
    : `Hola${client ? ` ${client.name.split(" ")[0]}` : ""}, te saludamos de la tienda. ¡Gracias por tu preferencia!`;
  const sheet = <div className="fv-sheet-layer" onClick={onClose}>
    <div ref={panel} tabIndex={-1} className="fv-sheet fv-client-sheet" role="dialog" aria-modal="true" aria-labelledby="fv-client-title" onClick={e => e.stopPropagation()}>
      <header><div><small>{client ? (client.tax_id ? `${docLabel(client)} ${client.tax_id}` : "Cliente") : "Nuevo cliente"}</small><h2 id="fv-client-title">{client?.name ?? "Registrar cliente"}</h2></div>
        <button className="fv-icon-button" onClick={onClose} aria-label="Cerrar">✕</button></header>

      {client && !editing && <>
        <dl className="fv-mini fv-client-stats">
          <div><dt>Compras</dt><dd>{client.purchases}</dd></div>
          <div><dt>Total comprado</dt><dd>{fmt(client.spent, currency)}</dd></div>
          <div><dt>Vuelve cada</dt><dd>{client.avgGap ? `${Math.round(client.avgGap)} días` : "—"}</dd></div>
        </dl>
        <div className="fv-actions">
          <button className="fv-button secondary" onClick={() => setEditing(true)}>Editar datos</button>
          {wa && <a className="fv-button secondary" href={`https://wa.me/${wa}?text=${encodeURIComponent(reminder)}`} target="_blank" rel="noopener">{client.balance > 0 ? "Recordar saldo por WhatsApp" : "Escribir por WhatsApp"}</a>}
        </div>
        <Fiado org={org} client={client} currency={currency} file={file} canFiado={canFiado} onSaved={reload} />
        <section className="fv-client-block">
          <h3>Últimas compras</h3>
          {!file ? <div className="fv-skeleton" aria-label="Cargando compras"><i /><i /></div>
            : !file.ok ? <p role="alert" className="fv-error">{file.message}</p>
            : !file.invoices.length ? <p className="fv-muted">Aún no tiene comprobantes a su nombre.</p>
            : <ul className="fv-lines">{file.invoices.map(i => <li key={i.id}>
                <a href={`/erp/${org}/comprobantes/${i.id}/imprimir`} target="_blank" rel="noopener">{i.number} · {day(i.issue_date)}</a>
                <span>{fmt(i.amt_total, i.currency)}</span>
              </li>)}</ul>}
        </section>
      </>}

      {editing && <ClientForm org={org} client={client} onSaved={id => { setEditing(false); if (!client) onCreated(id); }} onCancel={client ? () => setEditing(false) : onClose} />}
    </div>
  </div>;
  return root ? createPortal(sheet, root) : sheet;
}

function ClientForm({ org, client, onSaved, onCancel }: { org: string; client: ClientView | null; onSaved: (id: string) => void; onCancel: () => void }) {
  const router = useRouter();
  const [state, action, pending] = useActionState<ClientSaveResult, FormData>(saveClient.bind(null, org, client?.id ?? null), { ok: false, message: "" });
  const [doc, setDoc] = useState(client?.tax_id ?? "");
  const [nameV, setNameV] = useState(client?.name ?? "");
  const [address, setAddress] = useState(client?.address ?? "");
  const [district, setDistrict] = useState(client?.district ?? "");
  const [lookup, setLookup] = useState<{ busy: boolean; note: string; warn: string }>({ busy: false, note: "", warn: "" });
  const digits = doc.replace(/\D/g, "");
  const canLookup = digits.length === 8 || digits.length === 11;
  const done = useRef(state);
  const after = useRef(onSaved);
  after.current = onSaved;
  useEffect(() => {
    if (state === done.current || !state.ok || !state.id) return;
    done.current = state;
    router.refresh();
    after.current(state.id);
  }, [state, router]);

  async function consult() {
    if (!canLookup || lookup.busy) return;
    setLookup({ busy: true, note: "", warn: "" });
    const r = await lookupClientDocument(org, digits).catch(() => null);
    if (!r?.ok || !r.data) return setLookup({ busy: false, note: r?.message ?? "No se pudo consultar. Escribe los datos a mano.", warn: "" });
    setNameV(r.data.name);
    if (r.data.address) setAddress(r.data.address);
    if (r.data.district) setDistrict(r.data.district);
    setLookup({ busy: false, note: `Datos de ${r.data.kind === "ruc" ? "SUNAT" : "RENIEC"}${r.cached ? " (guardados)" : ""}. Revísalos antes de guardar.`, warn: r.data.warning });
  }

  return <form action={action} className="fv-form fv-client-form">
    <div className="fv-lookup">
      <label><span>DNI o RUC</span>
        <input name="tax_id" inputMode="numeric" autoComplete="off" maxLength={30} value={doc} onChange={e => setDoc(e.target.value)} onKeyDown={e => { if (e.key === "Enter" && canLookup) { e.preventDefault(); void consult(); } }} placeholder="8 u 11 dígitos" />
      </label>
      <button type="button" className="fv-button secondary" disabled={!canLookup || lookup.busy} onClick={consult}>{lookup.busy ? "Consultando…" : "Consultar"}</button>
    </div>
    {lookup.note && <p className="fv-hint" aria-live="polite">{lookup.note}</p>}
    {lookup.warn && <p className="fv-error" role="alert">{lookup.warn}</p>}
    <label><span>Nombre o razón social</span><input name="name" required maxLength={120} value={nameV} onChange={e => setNameV(e.target.value)} /></label>
    <div className="fv-form-row">
      <label><span>Celular</span><input name="phone" inputMode="tel" maxLength={30} defaultValue={client?.phone ?? ""} placeholder="9XX XXX XXX" /></label>
      <label><span>Correo</span><input name="email" type="email" maxLength={200} defaultValue={client?.email ?? ""} /></label>
    </div>
    <label><span>Dirección</span><input name="address" maxLength={300} value={address} onChange={e => setAddress(e.target.value)} /></label>
    <div className="fv-form-row">
      <label><span>Distrito</span><input name="district" maxLength={80} value={district} onChange={e => setDistrict(e.target.value)} /></label>
      <label><span>Límite de fiado</span><input name="credit_limit" type="number" min="0" step="0.01" inputMode="decimal" defaultValue={client?.limit ?? ""} placeholder="Sin límite" /></label>
    </div>
    <label><span>Notas</span><textarea name="notes" maxLength={2000} rows={2} defaultValue={client?.notes ?? ""} /></label>
    {state.message && !state.ok && <p className="fv-error" role="alert">{state.message}</p>}
    <div className="fv-actions">
      <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : client ? "Guardar cambios" : "Crear cliente"}</button>
      <button type="button" className="fv-button secondary" onClick={onCancel}>Cancelar</button>
    </div>
  </form>;
}

function Fiado({ org, client, currency, file, canFiado, onSaved }: { org: string; client: ClientView; currency: string; file: ClientFile | null; canFiado: boolean; onSaved: () => void }) {
  const router = useRouter();
  const [kind, setKind] = useState<"abono" | "cargo">("abono");
  const [state, action, pending] = useActionState<FormResult, FormData>(addCreditMove.bind(null, org, client.id), { ok: false, message: "" });
  const form = useRef<HTMLFormElement>(null);
  const done = useRef(state);
  const after = useRef(onSaved);
  after.current = onSaved;
  useEffect(() => {
    if (state === done.current || !state.ok) return;
    done.current = state;
    form.current?.reset();
    router.refresh();
    after.current();
  }, [state, router]);
  const used = client.limit ? Math.min(100, Math.round((client.balance / client.limit) * 100)) : null;
  const allowed = canFiado && file?.ok && file.canCollect;
  return <section className="fv-client-block">
    <h3>Libreta de fiado</h3>
    <div className={`fv-sunat ${client.overdue || client.overLimit ? "is-bad" : client.balance > 0 ? "is-wait" : "is-ok"}`}>
      <strong>{client.balance > 0 ? `Debe ${fmt(client.balance, currency)}` : "No tiene deuda"}</strong>
      {client.limit ? <span>Límite {fmt(client.limit, currency)}{used !== null ? ` · usado ${used} %` : ""}</span> : <span>Sin límite definido: puedes fijarlo en «Editar datos».</span>}
      {client.oldestDue && <span>{client.overdue ? "Venció" : "Vence"} el {day(client.oldestDue)}.</span>}
      {used !== null && <i className="fv-meter" style={{ "--used": `${used}%` } as React.CSSProperties} aria-hidden="true" />}
    </div>
    {allowed && <form ref={form} action={action} className="fv-fiado-form">
      <div className="fv-segment" role="group" aria-label="Tipo de movimiento">
        <button type="button" aria-pressed={kind === "abono"} onClick={() => setKind("abono")}>Registrar abono</button>
        <button type="button" aria-pressed={kind === "cargo"} onClick={() => setKind("cargo")}>Anotar fiado</button>
      </div>
      <input type="hidden" name="kind" value={kind} />
      <label><span>Importe</span><input name="amount" type="number" min="0.01" step="0.01" inputMode="decimal" required placeholder="0.00" /></label>
      {kind === "abono"
        ? <label><span>Medio</span><select name="method" defaultValue="efectivo">{["efectivo", "yape", "plin", "transferencia", "tarjeta", "otro"].map(m => <option key={m} value={m}>{m[0].toUpperCase() + m.slice(1)}</option>)}</select></label>
        : <label><span>Vence</span><input name="due_date" type="date" /></label>}
      <input type="hidden" name={kind === "abono" ? "due_date" : "method"} value="" />
      <label className="fv-grow"><span>Detalle</span><input name="description" maxLength={200} placeholder={kind === "abono" ? "Opcional" : "Qué se llevó"} /></label>
      <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : kind === "abono" ? "Guardar abono" : "Anotar"}</button>
      {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
    </form>}
    {file?.ok && file.ledger.length > 0 && <ul className="fv-lines fv-ledger">{file.ledger.map(l => <li key={l.id}>
      <span><b className={l.kind === "abono" ? "is-in" : "is-out"}>{l.kind === "abono" ? "Abono" : "Fiado"}</b> {day(l.created_at)}{l.method ? ` · ${l.method}` : ""}{l.description ? ` · ${l.description}` : ""}</span>
      <span>{l.kind === "abono" ? "−" : "+"}{fmt(l.amount, currency)}</span>
    </li>)}</ul>}
  </section>;
}
