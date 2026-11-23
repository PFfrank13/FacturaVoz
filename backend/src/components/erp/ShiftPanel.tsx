"use client";
import { useActionState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { closeShift, openShift, type FormResult } from "@/app/erp/actions";
import { cashDifference } from "@/lib/erp/cash";

export type ShiftRow = {
  id: string; name: string; opened_at: string; closed_at: string | null; opening_float: number; cash_sales: number; digital_sales: number;
  cash_in: number; cash_out: number; expected_cash: number; counted_cash: number | null; difference: number | null; note: string | null;
};

const empty: FormResult = { ok: false, message: "" };
const hour = (iso: string) => new Intl.DateTimeFormat("es-PE", { hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));

function useDone(state: FormResult) {
  const router = useRouter();
  const done = useRef(state);
  useEffect(() => {
    if (state === done.current || !state.ok) return;
    done.current = state;
    router.refresh();
  }, [state, router]);
}

/** My shift (open with a float, blind close) and, for finance, everyone's shifts of the day with their difference. */
export default function ShiftPanel({ org, mine, shifts, currency, isToday }: { org: string; mine: { opened_at: string; opening_float: number } | null; shifts: ShiftRow[] | null; currency: string; isToday: boolean }) {
  const fmt = (v: number) => new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(v);
  const [openState, open, opening] = useActionState(openShift.bind(null, org), empty);
  const [closeState, close, closing] = useActionState(closeShift.bind(null, org), empty);
  useDone(openState);
  useDone(closeState);
  return <section className="fv-create fv-cash-card">
    <h3>Turnos por cajero</h3>
    {isToday && (mine ? <form action={close} className="fv-fiado-form">
      <p className="fv-muted fv-grow">Tu turno empezó a las {hour(mine.opened_at)} con {fmt(mine.opening_float)} de fondo. Al terminar, cuenta tu cajón y escribe el total: es un cierre ciego.</p>
      <label><span>Efectivo contado</span><input name="counted" inputMode="decimal" required autoComplete="off" placeholder="0.00" /></label>
      <label className="fv-grow"><span>Nota</span><input name="note" maxLength={300} placeholder="Opcional" /></label>
      <button className="fv-button" disabled={closing}>{closing ? "Cerrando…" : "Cerrar mi turno"}</button>
      {closeState.message && <p className={closeState.ok ? "fv-ok" : "fv-error"} role={closeState.ok ? "status" : "alert"}>{closeState.message}</p>}
    </form> : <form action={open} className="fv-fiado-form">
      <p className="fv-muted fv-grow">Si en la tienda trabajan varios cajeros, cada uno abre su turno con su fondo y lo cierra contando su cajón.</p>
      <label><span>Fondo inicial</span><input name="float" inputMode="decimal" required autoComplete="off" placeholder="50.00" /></label>
      <button className="fv-button secondary" disabled={opening}>{opening ? "Abriendo…" : "Abrir mi turno"}</button>
      {(openState.message || closeState.message) && <p className={(openState.message ? openState.ok : closeState.ok) ? "fv-ok" : "fv-error"} role="status">{openState.message || closeState.message}</p>}
    </form>)}
    {shifts && (shifts.length ? <ul className="fv-lines fv-ledger">{shifts.map(s => {
      const d = s.counted_cash == null ? null : cashDifference(s.expected_cash, s.counted_cash);
      return <li key={s.id}>
        <span><b>{s.name}</b> {hour(s.opened_at)}–{s.closed_at ? hour(s.closed_at) : "abierto"} · fondo {fmt(s.opening_float)} · efectivo {fmt(s.cash_sales)} · digital {fmt(s.digital_sales)}{s.cash_out ? ` · retiros ${fmt(s.cash_out)}` : ""}{s.note ? ` · ${s.note}` : ""}</span>
        <span>{d == null ? `debe tener ${fmt(s.expected_cash)}` : d.kind === "cuadra" ? <b className="is-in">Cuadró</b> : <b className="is-out">{d.kind === "sobra" ? "Sobró" : "Faltó"} {fmt(d.amount)}</b>}</span>
      </li>;
    })}</ul> : <p className="fv-muted">Ningún turno este día.</p>)}
  </section>;
}
