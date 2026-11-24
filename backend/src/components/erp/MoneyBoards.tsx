"use client";
import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { logReminder, payLink, registerPayment, resolveClaim, setCreditLimit, type FormResult } from "@/app/erp/actions";
import { reminderText, daysBetween, type Receivable } from "@/lib/erp/insights";

const idle: FormResult = { ok: false, message: "" };
const Msg = ({ m }: { m: FormResult | null }) => m?.message ? <p className={m.ok ? "fv-ok" : "fv-error"} role={m.ok ? "status" : "alert"}>{m.message}</p> : null;

/** WhatsApp reminder with the pay link (the mobile «Recordar»): logs it so you know who was already reminded. */
export function RemindButton({ org, row, business, phone, today }: { org: string; row: Receivable; business: string; phone: string; today: string }) {
  const [busy, setBusy] = useState(false);
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  return <span className="fv-inline-action">
    <button className="fv-button secondary" disabled={busy} onClick={async () => {
      // Open the tab first (popup blockers), then fill it once the link is ready.
      const tab = window.open("", "_blank");
      setBusy(true); setM(null);
      const link = await payLink(org, row.id).catch(() => null);
      const url = link?.ok ? `${window.location.origin}${link.path}` : null;
      const text = reminderText(row, business, today, url);
      const wa = `https://wa.me/${phone}?text=${encodeURIComponent(text)}`;
      if (tab) tab.location.href = wa; else window.open(wa, "_blank");
      await logReminder(org, row.id, row.due_date ? daysBetween(row.due_date, today) : 0).catch(() => null);
      setBusy(false); router.refresh();
      if (!link?.ok) setM({ ok: false, message: "Se envió sin enlace de pago (configura tus medios de cobro)." });
    }}>{busy ? "Preparando…" : "Recordar por WhatsApp"}</button>
    <Msg m={m} />
  </span>;
}

/** Register a payment or partial payment against one receivable. */
export function PayForm({ org, row, today }: { org: string; row: Receivable; today: string }) {
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState(registerPayment.bind(null, org, row.id, row.balance), idle);
  if (!open) return <button className="fv-button secondary" onClick={() => setOpen(true)}>Registrar cobro</button>;
  return <form action={action} className="fv-inline-form fv-pay-form">
    <label className="fv-search"><span>Importe</span><input name="amount" inputMode="decimal" defaultValue={row.balance.toFixed(2)} required /></label>
    <label className="fv-search"><span>Medio</span><select name="method" defaultValue="efectivo"><option value="efectivo">Efectivo</option><option value="yape">Yape</option><option value="plin">Plin</option><option value="transferencia">Transferencia</option><option value="tarjeta">Tarjeta</option></select></label>
    <label className="fv-search"><span>Fecha</span><input type="date" name="paid_on" defaultValue={today} max={today} required /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar"}</button>
    <button type="button" className="fv-link" onClick={() => setOpen(false)}>Cancelar</button>
    <Msg m={state} />
  </form>;
}

/** «Ya pagué» reported from the pay page: confirm or reject. */
export function ClaimActions({ org, id }: { org: string; id: string }) {
  const [busy, setBusy] = useState(false);
  const [m, setM] = useState<FormResult | null>(null);
  const router = useRouter();
  const run = async (accept: boolean) => {
    if (!accept && !window.confirm("¿Rechazar este aviso de pago?")) return;
    setBusy(true); const r = await resolveClaim(org, id, accept).catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); setBusy(false); if (r.ok) router.refresh();
  };
  return <span className="fv-actions">
    <button className="fv-button" disabled={busy} onClick={() => void run(true)}>Confirmar pago</button>
    <button className="fv-button secondary" disabled={busy} onClick={() => void run(false)}>Rechazar</button>
    <Msg m={m} />
  </span>;
}

/** Set or change the credit limit of a client. */
export function CreditLimit({ org, clientId, limit }: { org: string; clientId: string; limit: number }) {
  const [open, setOpen] = useState(false);
  const [v, setV] = useState(limit > 0 ? String(limit) : "");
  const [m, setM] = useState<FormResult | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  if (!open) return <button className="fv-link" onClick={() => setOpen(true)}>{limit > 0 ? "Cambiar límite" : "Fijar límite"}</button>;
  return <form className="fv-inline-form" onSubmit={async e => {
    e.preventDefault();
    const n = v.trim() ? Number(v.replace(",", ".")) : null;
    if (n != null && !Number.isFinite(n)) { setM({ ok: false, message: "Escribe un número." }); return; }
    setBusy(true); const r = await setCreditLimit(org, clientId, n).catch(() => ({ ok: false, message: "Sin conexión." })); setM(r); setBusy(false);
    if (r.ok) { setOpen(false); router.refresh(); }
  }}>
    <label className="fv-search"><span>Límite (vacío = sin límite)</span><input inputMode="decimal" value={v} onChange={e => setV(e.target.value)} autoFocus /></label>
    <button className="fv-button" disabled={busy}>Guardar</button>
    <button type="button" className="fv-link" onClick={() => setOpen(false)}>Cancelar</button>
    <Msg m={m} />
  </form>;
}
