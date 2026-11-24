"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { addWebhook, createApiKey, revokeApiKey, setWebhook, type FormResult } from "@/app/erp/actions";

const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;
export const scopeLabel: Record<string, string> = { "invoices:read": "Leer comprobantes", "clients:read": "Leer clientes", "products:read": "Leer productos", "orders:write": "Crear pedidos" };
export const eventLabel: Record<string, string> = { "invoice.created": "Comprobante creado", "invoice.updated": "Comprobante actualizado", "invoice.paid": "Comprobante pagado", "payment.created": "Cobro registrado", "order.created": "Pedido nuevo (tienda o API)" };

export type ApiKey = { id: string; name: string; prefix: string; scopes: string[]; created_at: string; last_used_at: string | null; revoked_at: string | null };
export type Hook = { id: string; url: string; events: string[]; active: boolean; last_status: number | null; secret: string | null };

/** «API y webhooks»: connect your website or another system. */
export function ApiBoard({ org, keys, hooks, base }: { org: string; keys: ApiKey[]; hooks: Hook[]; base: string }) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [scopes, setScopes] = useState<string[]>(["invoices:read", "clients:read", "orders:write"]);
  const [fresh, setFresh] = useState<string | null>(null);
  const [url, setUrl] = useState("");
  const [events, setEvents] = useState<string[]>(Object.keys(eventLabel));
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const toggle = (list: string[], v: string) => (list.includes(v) ? list.filter(x => x !== v) : [...list, v]);
  async function run(p: Promise<FormResult>) { setBusy(true); const r = await p.catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); setBusy(false); if (r.ok) router.refresh(); }
  return <section className="fv-board">
    <section className="fv-create fv-settings-card">
      <h3>Llaves de API</h3>
      <p className="fv-caption">Dirección base: <code>{base}</code>. Envía la llave en el encabezado <code>Authorization: Bearer …</code>.</p>
      <form className="fv-inline-form" onSubmit={async e => { e.preventDefault(); setBusy(true); setM(null); const r = await createApiKey(org, name, scopes).catch(() => ({ ok: false as const, message: "Sin conexión." })); setBusy(false);
        if (!r.ok) { setM(r); return; } setFresh(r.key); setName(""); router.refresh(); }}>
        <label className="fv-search"><span>Nombre</span><input value={name} maxLength={60} onChange={e => setName(e.target.value)} placeholder="Mi tienda web" /></label>
        {Object.entries(scopeLabel).map(([k, v]) => <label key={k} className="fv-check"><input type="checkbox" checked={scopes.includes(k)} onChange={() => setScopes(s => toggle(s, k))} /> {v}</label>)}
        <button className="fv-button" disabled={busy || !name.trim()}>Crear llave</button>
      </form>
      {fresh && <div className="fv-note-box" role="status"><strong>Copia tu llave ahora: no se vuelve a mostrar.</strong><div className="fv-secret"><code>{fresh}</code><button className="fv-button secondary" onClick={() => void navigator.clipboard?.writeText(fresh)}>Copiar</button></div></div>}
      {keys.length > 0 && <ul className="fv-lines">{keys.map(k => <li key={k.id}><span><strong>{k.name}</strong> <code>{k.prefix}…</code><small> {k.scopes.map(s => scopeLabel[s] ?? s).join(", ")}{k.last_used_at ? ` · último uso ${k.last_used_at.slice(0, 10)}` : " · sin usar"}</small></span>
        {k.revoked_at ? <span className="fv-pill is-off">Revocada</span> : <button className="fv-link fv-neg" disabled={busy} onClick={() => { if (window.confirm(`¿Revocar «${k.name}»? Lo que la use dejará de funcionar.`)) void run(revokeApiKey(org, k.id)); }}>Revocar</button>}</li>)}</ul>}
    </section>
    <section className="fv-create fv-settings-card">
      <h3>Webhooks</h3>
      <p className="fv-caption">Avisamos a tu sistema cuando pasa algo. Cada aviso va firmado con el secreto del webhook.</p>
      <form className="fv-inline-form" onSubmit={e => { e.preventDefault(); void run(addWebhook(org, url, events)).then(() => setUrl("")); }}>
        <label className="fv-search"><span>Dirección (https://…)</span><input type="url" value={url} onChange={e => setUrl(e.target.value)} placeholder="https://tusistema.pe/webhooks/facturavoz" /></label>
        {Object.entries(eventLabel).map(([k, v]) => <label key={k} className="fv-check"><input type="checkbox" checked={events.includes(k)} onChange={() => setEvents(s => toggle(s, k))} /> {v}</label>)}
        <button className="fv-button" disabled={busy || !url.trim()}>Agregar webhook</button>
      </form>
      {hooks.length > 0 && <ul className="fv-lines">{hooks.map(h => <li key={h.id}><span><strong>{h.url}</strong><small> {h.events.map(e => eventLabel[e] ?? e).join(", ")}{h.last_status != null ? ` · última respuesta ${h.last_status}` : ""}</small>
        {h.secret && <small> Secreto: <code>{h.secret.slice(0, 6)}…</code> <button className="fv-link" onClick={() => void navigator.clipboard?.writeText(h.secret ?? "")}>copiar</button></small>}</span>
        <span className="fv-actions"><button className="fv-link" disabled={busy} onClick={() => void run(setWebhook(org, h.id, h.active ? "off" : "on"))}>{h.active ? "Pausar" : "Activar"}</button>
          <button className="fv-link fv-neg" disabled={busy} onClick={() => { if (window.confirm("¿Eliminar este webhook?")) void run(setWebhook(org, h.id, "delete")); }}>Eliminar</button></span></li>)}</ul>}
    </section>
    <Msg m={m} />
  </section>;
}
