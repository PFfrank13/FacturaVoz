"use client";
import { useActionState, useState } from "react";
import { addExpense, markAlertsRead, restoreTrash, verifyAudit, type FormResult } from "@/app/erp/actions";
import { expenseCategories } from "@/lib/erp/expenses";

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
