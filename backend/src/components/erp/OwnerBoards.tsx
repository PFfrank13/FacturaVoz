"use client";
import { useActionState, useState } from "react";
import { addExpense, markAlertsRead, restoreTrash, verifyAudit, type FormResult } from "@/app/erp/actions";
import { expenseCategories } from "@/lib/erp/expenses";
import { createClient } from "@/lib/supabase/client";

const idle: FormResult = { ok: false, message: "" };

/** New expense (same table and categories as the mobile app). */
export function ExpenseForm({ org, today }: { org: string; today: string }) {
  const [state, action, pending] = useActionState(addExpense.bind(null, org), idle);
  return <details className="fv-create" open={false}>
    <summary className="fv-button">+ Registrar gasto</summary>
    <form action={action} className="fv-form" key={state.ok ? state.message : "f"}>
      <div className="fv-two">
        <label>Fecha<input type="date" name="spent_on" defaultValue={today} max={today} required /></label>
        <label>Importe<input name="total" inputMode="decimal" placeholder="0.00" required /></label>
      </div>
      <div className="fv-two">
        <label>Categoría<select name="category" defaultValue="mercaderia">{Object.entries(expenseCategories).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
        <label>Proveedor (opcional)<input name="supplier_name" maxLength={160} /></label>
      </div>
      <div className="fv-two">
        <label>Detalle<input name="description" maxLength={200} placeholder="Ej.: recibo de luz de noviembre" /></label>
        <label>N.º de comprobante (opcional)<input name="doc_number" maxLength={40} /></label>
      </div>
      <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar gasto"}</button>
      {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
    </form>
  </details>;
}

export function MarkAlertsRead({ org, unread }: { org: string; unread: number }) {
  const [msg, setMsg] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  if (!unread) return null;
  return <div className="fv-actions-row">
    <button className="fv-button secondary" disabled={busy} onClick={async () => { setBusy(true); setMsg(await markAlertsRead(org)); setBusy(false); }}>Marcar {unread} como vistas</button>
    {msg && <p className={msg.ok ? "fv-ok" : "fv-error"}>{msg.message}</p>}
  </div>;
}

export function RestoreButton({ org, id }: { org: string; id: string }) {
  const [msg, setMsg] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  if (msg?.ok) return <span className="fv-pill is-ok">Recuperado</span>;
  return <span><button className="fv-button secondary" disabled={busy} onClick={async () => { setBusy(true); setMsg(await restoreTrash(org, id)); setBusy(false); }}>{busy ? "Recuperando…" : "Recuperar"}</button>
    {msg && !msg.ok && <small className="fv-error">{msg.message}</small>}</span>;
}

export function VerifyAudit({ org }: { org: string }) {
  const [msg, setMsg] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  return <div className="fv-actions-row">
    <button className="fv-button secondary" disabled={busy} onClick={async () => { setBusy(true); setMsg(await verifyAudit(org)); setBusy(false); }}>{busy ? "Verificando…" : "Verificar que nadie la alteró"}</button>
    {msg && <p className={msg.ok ? "fv-ok" : "fv-error"} role="status">{msg.message}</p>}
  </div>;
}

type Scanned = { doc_type: string; supplier_name: string; supplier_tax_id: string; doc_number: string; issue_date: string; currency: string; tax: number | null; total: number; category: string; items: { description: string }[] };

/** «Escanear comprobante»: photo of the supplier's factura → the expense filled in (with its IGV), reviewed before saving. */
export function ScanExpense({ org, today }: { org: string; today: string }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  const [doc, setDoc] = useState<Scanned | null>(null);
  const [n, setN] = useState(0);
  const [state, action, pending] = useActionState(addExpense.bind(null, org), idle);
  async function read(f: File) {
    setErr(""); setDoc(null);
    if (f.size > 3_000_000) { setErr("La foto pesa más de 3 MB. Tómala con menos resolución o recórtala."); return; }
    setBusy(true);
    try {
      const fd = new FormData(); fd.append("image", f, f.name); fd.append("kind", "document");
      const { data } = await createClient().auth.getSession();
      const res = await fetch("/api/scan", { method: "POST", body: fd, headers: data.session ? { authorization: `Bearer ${data.session.access_token}` } : {} });
      const j = await res.json().catch(() => ({}));
      if (!res.ok || !j.document) { setErr(j.error ?? "No pude leer la foto."); return; }
      setDoc(j.document as Scanned); setN(x => x + 1);
    } catch { setErr("Sin conexión."); }
    finally { setBusy(false); }
  }
  const valid = (d: string) => /^\d{4}-\d{2}-\d{2}$/.test(d) && d <= today ? d : today;
  return <div className="fv-create" style={{ padding: 18 }}>
    <h3>Foto de la factura o boleta de tu proveedor</h3>
    <p className="fv-caption">Leemos proveedor, RUC, número, fecha, total e IGV. Revisa y guarda: queda como gasto (y el IGV de las facturas suma a tu crédito fiscal).</p>
    <label className="fv-button fv-file">{busy ? "Leyendo la foto…" : "Elegir o tomar foto"}<input type="file" hidden accept="image/jpeg,image/png,image/webp" capture="environment" disabled={busy} onChange={e => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void read(f); }} /></label>
    {err && <p className="fv-error" role="alert">{err}</p>}
    {doc && <form action={action} className="fv-form" key={n} style={{ marginTop: 14 }}>
      <input type="hidden" name="source" value="scan" />
      {doc.currency === "USD" && <p className="fv-note-box">El comprobante está en dólares: escribe el importe en tu moneda antes de guardar.</p>}
      <div className="fv-two">
        <label>Proveedor<input name="supplier_name" maxLength={160} defaultValue={doc.supplier_name} /></label>
        <label>RUC del proveedor<input name="supplier_tax_id" inputMode="numeric" maxLength={11} defaultValue={/^(\d{8}|\d{11})$/.test(doc.supplier_tax_id) ? doc.supplier_tax_id : ""} /></label>
      </div>
      <div className="fv-two">
        <label>N.º de comprobante<input name="doc_number" maxLength={40} defaultValue={doc.doc_number} /></label>
        <label>Fecha<input type="date" name="spent_on" defaultValue={valid(doc.issue_date)} max={today} required /></label>
      </div>
      <div className="fv-two">
        <label>Total<input name="total" inputMode="decimal" defaultValue={doc.total ? doc.total.toFixed(2) : ""} required /></label>
        <label>IGV (si es factura)<input name="tax" inputMode="decimal" defaultValue={doc.doc_type === "factura" && doc.tax ? doc.tax.toFixed(2) : ""} /></label>
      </div>
      <div className="fv-two">
        <label>Categoría<select name="category" defaultValue={doc.category in expenseCategories ? doc.category : "otros"}>{Object.entries(expenseCategories).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
        <label>Detalle<input name="description" maxLength={200} defaultValue={doc.items.slice(0, 3).map(i => i.description).join(", ").slice(0, 200)} /></label>
      </div>
      <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar gasto"}</button>
    </form>}
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </div>;
}
