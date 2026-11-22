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

const uuid = z.uuid();
const productEditSchema = z.object({
  name,
  unit_price: z.coerce.number().min(0).max(10_000_000),
  category: z.string().trim().max(60),
  reorder_point: z.union([z.literal(""), z.coerce.number().min(0).max(10_000_000)]),
  active: z.enum(["on"]).optional(),
});

/** Product edits from the web: same table and columns the mobile app reads. */
async function productContext(org: string, productId: string) {
  if (!uuid.safeParse(productId).success) return { error: "Producto no válido." } as const;
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "productos")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { error: "Tus permisos han cambiado. Actualiza la página." } as const;
  if (!can(c.access, "products_edit")) return { error: "No tienes permiso para editar productos." } as const;
  return { c } as const;
}

export async function updateProduct(org: string, productId: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await productContext(org, productId);
  if ("error" in ctx) return { ok: false, message: ctx.error! };
  const parsed = productEditSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { ok: false, message: "Revisa el nombre, el precio y el stock mínimo." };
  const { name: productName, unit_price, category, reorder_point, active } = parsed.data;
  const result = await ctx.c.db.from("products")
    .update({ name: productName, unit_price, category: category || null, reorder_point: reorder_point === "" ? null : reorder_point, active: active === "on" })
    .eq("org_id", org).eq("id", productId).select("id").maybeSingle();
  if (result.error || !result.data) return { ok: false, message: "No se pudo guardar. El producto no existe o no tienes acceso." };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Cambios guardados. El móvil los verá al instante." };
}

const photoTypes = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" } as const;
/** Same Storage bucket and folder convention as the mobile app (org-media/{org}/productos/…). */
export async function uploadProductPhoto(org: string, productId: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await productContext(org, productId);
  if ("error" in ctx) return { ok: false, message: ctx.error! };
  const file = form.get("photo");
  if (!(file instanceof File) || file.size === 0) return { ok: false, message: "Elige una fotografía." };
  const ext = photoTypes[file.type as keyof typeof photoTypes];
  if (!ext) return { ok: false, message: "Usa una foto JPG, PNG o WebP." };
  if (file.size > 5 * 1024 * 1024) return { ok: false, message: "La foto debe pesar menos de 5 MB." };
  const path = `${org}/productos/${Date.now()}_${file.size}.${ext}`;
  const upload = await ctx.c.db.storage.from("org-media").upload(path, file, { contentType: file.type, upsert: false });
  if (upload.error) return { ok: false, message: "No se pudo subir la foto. Inténtalo de nuevo." };
  const result = await ctx.c.db.from("products").update({ image_path: path }).eq("org_id", org).eq("id", productId).select("id").maybeSingle();
  if (result.error || !result.data) {
    await ctx.c.db.storage.from("org-media").remove([path]);
    return { ok: false, message: "No se pudo asignar la foto al producto." };
  }
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Foto actualizada. Ya aparece en el móvil." };
}
