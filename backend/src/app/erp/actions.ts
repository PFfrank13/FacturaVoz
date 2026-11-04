"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed, can } from "@/lib/erp/access";

export type FormResult = { ok: boolean; message: string };
const name = z.string().trim().min(1).max(120);
const clientSchema = z.object({ name, email: z.union([z.literal(""), z.email().max(200)]), phone: z.string().trim().max(30), tax_id: z.string().trim().max(20) });
const productSchema = z.object({ name, unit_price: z.coerce.number().min(0).max(10_000_000), unit: z.enum(["NIU", "ZZ"]) });
const jobSchema = z.object({ title: z.string().trim().min(1).max(140) });

/** All mutations re-read server rights, then execute with the user's RLS client. */
export async function createRecord(org: string, moduleId: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === moduleId);
  if (!entry || !moduleAllowed(entry, c.license, c.access, c.sector)) return { ok: false, message: "Tus permisos han cambiado. Actualiza la página." };
  const input = Object.fromEntries(form);
  let row: Record<string, unknown>;
  if (moduleId === "clientes") {
    const parsed = clientSchema.safeParse(input);
    if (!parsed.success) return { ok: false, message: "Revisa el nombre, documento, teléfono y correo del cliente." };
    row = { ...parsed.data, email: parsed.data.email || null, tax_id: parsed.data.tax_id || null, user_id: c.user.id };
  } else if (moduleId === "productos") {
    if (!can(c.access, "products_edit")) return { ok: false, message: "No tienes permiso para editar productos." };
    const parsed = productSchema.safeParse(input);
    if (!parsed.success) return { ok: false, message: "Indica un nombre y un precio válido." };
    row = { ...parsed.data, user_id: c.user.id, active: true };
  } else if (moduleId === "trabajos" || moduleId === "agenda") {
    const parsed = jobSchema.safeParse(input);
    if (!parsed.success) return { ok: false, message: "Indica un título de hasta 140 caracteres." };
    const scheduled = String(form.get("scheduled_at") ?? "");
    if (moduleId === "agenda" && (!scheduled || !Number.isFinite(Date.parse(scheduled)) || !/Z$/.test(scheduled))) return { ok: false, message: "Selecciona una fecha y hora válidas." };
    row = { ...parsed.data, kind: moduleId === "agenda" ? "cita" : "servicio", status: "nuevo", assigned_to: c.access.role === "tecnico" ? c.user.id : null,
      ...(moduleId === "agenda" ? { scheduled_at: scheduled, duration_min: 30 } : {}) };
  } else return { ok: false, message: "Operación no disponible." };
  const result = await c.db.from(entry.table!).insert({ ...row, org_id: org });
  if (result.error) return { ok: false, message: "No se pudo guardar. Revisa tus permisos y que el registro no exista ya." };
  revalidatePath(`/erp/${org}` , "layout");
  return { ok: true, message: "Registro guardado. Ya está disponible para tu empresa." };
}
