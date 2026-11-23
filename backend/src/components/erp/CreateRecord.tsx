"use client";
import { useActionState } from "react";
import { createRecord } from "@/app/erp/actions";

export default function CreateRecord({ org, moduleId }: { org: string; moduleId: string }) {
  const [state, action, pending] = useActionState(createRecord.bind(null, org, moduleId), { ok: false, message: "" });
  return <details className="fv-create"><summary className="fv-button secondary">Añadir registro</summary><form className="fv-form" action={action}>
    <label>{moduleId === "agenda" ? "Motivo administrativo de la cita" : moduleId === "trabajos" ? "Trabajo" : "Nombre"}<input name={moduleId === "agenda" || moduleId === "trabajos" ? "title" : "name"} required maxLength={120} /></label>
    {moduleId === "clientes" && <><label>Documento<input name="tax_id" maxLength={20} /></label><label>Correo<input name="email" type="email" maxLength={200} /></label><label>Teléfono<input name="phone" type="tel" maxLength={30} /></label></>}
    {moduleId === "productos" && <><label>Tipo<select name="unit"><option value="NIU">Producto</option><option value="KGM">Producto por kilo</option><option value="ZZ">Servicio</option></select></label><label>Precio unitario sin impuesto<input name="unit_price" type="number" min="0" max="10000000" step="0.01" required /></label></>}
    {moduleId === "agenda" && <label>Fecha y hora (zona horaria de este dispositivo)<input type="datetime-local" required onChange={e => { const target = e.currentTarget.form?.elements.namedItem("scheduled_at") as HTMLInputElement | null; if (target) target.value = e.target.value && Number.isFinite(Date.parse(e.target.value)) ? new Date(e.target.value).toISOString() : ""; }} /><input type="hidden" name="scheduled_at" /></label>}
    <button className="fv-button" disabled={pending}>{pending ? "Guardando…" : "Guardar registro"}</button>
    {state.message && <p role={state.ok ? "status" : "alert"}>{state.message}</p>}
  </form></details>;
}
