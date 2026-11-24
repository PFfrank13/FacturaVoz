"use client";
import { useActionState } from "react";
import { saveBooking, type FormResult } from "@/app/erp/actions";

const idle: FormResult = { ok: false, message: "" };

/** «Reservas en línea»: your clients book from /reservar/<tu-dirección> and the appointment lands in the Agenda. */
export function BookingForm({ org, slug, enabled, services, hours }: { org: string; slug: string | null; enabled: boolean; services: string[]; hours: string }) {
  const [state, action, pending] = useActionState(saveBooking.bind(null, org), idle);
  if (!slug) return <section className="fv-create fv-settings-card"><h3>Reservas en línea</h3><p className="fv-muted">Primero crea la dirección de tu negocio en Tienda en línea; con ella tus clientes reservan desde su celular.</p></section>;
  return <form action={action} className="fv-create fv-form fv-settings-card">
    <h3>Reservas en línea</h3>
    <p className="fv-caption">Tus clientes reservan en <a className="fv-link" href={`/reservar/${slug}`} target="_blank" rel="noreferrer">/reservar/{slug}</a> y la cita aparece aquí por confirmar.</p>
    <label className="fv-check"><input type="checkbox" name="booking" defaultChecked={enabled} /> Aceptar reservas en línea</label>
    <label>Servicios que se pueden reservar (uno por línea)<textarea name="services" rows={4} defaultValue={services.join("\n")} placeholder={"Corte de cabello\nManicure"} /></label>
    <label>Horario de atención<input name="hours" maxLength={200} defaultValue={hours} placeholder="Lun a sáb de 9:00 a 19:00" /></label>
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar reservas"}</button>
    {state.message && <p className={state.ok ? "fv-ok" : "fv-error"} role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form>;
}

export const PrintButton = () => <button type="button" className="fv-button" onClick={() => window.print()}>Imprimir</button>;
