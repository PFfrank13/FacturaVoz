"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed, can, hasFeature } from "@/lib/erp/access";
import { lookupDocument, type LookupReply } from "@/lib/lookup";
import { docTypeOf } from "@/lib/erp/clients";
import { closeDay } from "@/lib/dayclose-core";
import { parseAmount } from "@/lib/erp/cash";

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
  unit_cost: z.union([z.literal(""), z.coerce.number().min(0).max(10_000_000)]).optional(),
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
  const { name: productName, unit_price, category, reorder_point, unit_cost, active } = parsed.data;
  const result = await ctx.c.db.from("products")
    .update({ name: productName, unit_price, category: category || null, reorder_point: reorder_point === "" ? null : reorder_point, active: active === "on",
      // Only touch the cost when the form sends it, so other editors never erase it.
      ...(unit_cost === undefined ? {} : { unit_cost: unit_cost === "" ? null : unit_cost }) })
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

export type ReceiptDetail = {
  ok: true;
  items: { description: string; quantity: number; unit_price: number }[];
  base: number; tax: number; discount: number; total: number; currency: string; notes: string | null;
} | { ok: false; message: string };

/** Line items and totals of one receipt, re-checking module rights on the server. */
export async function getReceipt(org: string, invoiceId: string): Promise<ReceiptDetail> {
  if (!uuid.safeParse(invoiceId).success) return { ok: false, message: "Comprobante no válido." };
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "comprobantes")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { ok: false, message: "Tus permisos han cambiado. Actualiza la página." };
  const [inv, items] = await Promise.all([
    c.db.from("invoices").select("id,currency,amt_base,amt_tax,amt_discount,amt_total,notes").eq("org_id", org).eq("id", invoiceId).maybeSingle(),
    c.db.from("invoice_items").select("description,quantity,unit_price").eq("invoice_id", invoiceId).order("position"),
  ]);
  if (inv.error || !inv.data || items.error) return { ok: false, message: "No se pudo cargar el comprobante." };
  return {
    ok: true,
    items: (items.data ?? []).map(i => ({ description: i.description, quantity: Number(i.quantity), unit_price: Number(i.unit_price) })),
    base: Number(inv.data.amt_base), tax: Number(inv.data.amt_tax), discount: Number(inv.data.amt_discount),
    total: Number(inv.data.amt_total), currency: inv.data.currency || "PEN", notes: inv.data.notes,
  };
}

/** Clients module context: module rights re-read on the server for every call. */
async function clientsContext(org: string) {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "clientes")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { c: null, error: "Tus permisos han cambiado. Actualiza la página." } as const;
  return { c, error: "" } as const;
}

/** DNI/RUC lookup for the web: same cache, daily limits and messages as the mobile app. */
export async function lookupClientDocument(org: string, number: string): Promise<LookupReply> {
  const ctx = await clientsContext(org);
  if (!ctx.c) return { ok: false, reason: "forbidden", message: ctx.error };
  const digits = String(number ?? "").replace(/\D/g, "").slice(0, 11);
  return (await lookupDocument(ctx.c.db, ctx.c.user.id, digits, org)).body;
}

const optional = (max: number) => z.string().trim().max(max);
const clientEditSchema = z.object({
  name,
  tax_id: optional(30).regex(/^[0-9A-Za-z-]*$/, "doc"),
  phone: optional(30),
  email: z.union([z.literal(""), z.email().max(200)]),
  address: optional(300),
  district: optional(80),
  notes: optional(2000),
  credit_limit: z.union([z.literal(""), z.coerce.number().min(0).max(100_000_000)]),
});

export type ClientSaveResult = FormResult & { id?: string };

/** Create or edit a client with the columns the mobile app reads (doc_type from the number itself). */
export async function saveClient(org: string, clientId: string | null, _previous: ClientSaveResult, form: FormData): Promise<ClientSaveResult> {
  if (clientId !== null && !uuid.safeParse(clientId).success) return { ok: false, message: "Cliente no válido." };
  const ctx = await clientsContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = clientEditSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) {
    const field = parsed.error.issues[0]?.path[0];
    const why: Record<string, string> = {
      name: "Escribe el nombre o la razón social.", tax_id: "El documento solo admite números y letras.",
      email: "Revisa el correo.", credit_limit: "El límite de fiado debe ser un importe válido.",
    };
    return { ok: false, message: why[String(field)] ?? "Revisa los datos del cliente." };
  }
  const d = parsed.data;
  const blank = (v: string) => (v ? v : null);
  const row = {
    name: d.name, tax_id: blank(d.tax_id), doc_type: d.tax_id ? docTypeOf(d.tax_id) ?? "0" : null, phone: blank(d.phone), email: blank(d.email),
    address: blank(d.address), district: blank(d.district), notes: blank(d.notes), credit_limit: d.credit_limit === "" ? null : d.credit_limit,
  };
  const { c } = ctx;
  if (d.tax_id) {
    const dup = await c.db.from("clients").select("id,name").eq("org_id", org).eq("tax_id", d.tax_id).limit(1).maybeSingle();
    if (dup.data && dup.data.id !== clientId) return { ok: false, message: `Ese documento ya es de «${dup.data.name}». Ábrelo desde la lista.` };
  }
  const result = clientId
    ? await c.db.from("clients").update(row).eq("org_id", org).eq("id", clientId).select("id").maybeSingle()
    : await c.db.from("clients").insert({ ...row, org_id: org, user_id: c.user.id, source: "tienda" }).select("id").maybeSingle();
  if (result.error || !result.data) return { ok: false, message: "No se pudo guardar el cliente. Revisa tus permisos." };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, id: result.data.id, message: clientId ? "Cliente actualizado. Ya se ve igual en el móvil." : "Cliente creado. Ya está disponible en el punto de venta." };
}

export type ClientFile = {
  ok: true;
  invoices: { id: string; number: string; issue_date: string; amt_total: number; status: string; currency: string }[];
  ledger: { id: string; kind: "cargo" | "abono"; amount: number; description: string | null; method: string | null; due_date: string | null; created_at: string }[];
  canCollect: boolean;
} | { ok: false; message: string };

/** Recent purchases and fiado movements of one client. */
export async function getClientFile(org: string, clientId: string): Promise<ClientFile> {
  if (!uuid.safeParse(clientId).success) return { ok: false, message: "Cliente no válido." };
  const ctx = await clientsContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const { c } = ctx;
  const [inv, led] = await Promise.all([
    c.db.from("invoices").select("id,number,issue_date,amt_total,status,currency,fiscal:fiscal_documents(series,correlative)").eq("org_id", org).eq("client_id", clientId).neq("status", "draft").order("issue_date", { ascending: false }).limit(8),
    c.db.from("credit_ledger").select("id,kind,amount,description,method,due_date,created_at").eq("org_id", org).eq("client_id", clientId).order("created_at", { ascending: false }).limit(12),
  ]);
  if (inv.error) return { ok: false, message: "No se pudo cargar la ficha del cliente." };
  return {
    ok: true,
    invoices: (inv.data ?? []).map(({ fiscal, ...i }) => {
      const f = (Array.isArray(fiscal) ? fiscal[0] : fiscal) as { series: string; correlative: number } | null | undefined;
      return { ...i, number: f ? `${f.series}-${String(f.correlative).padStart(8, "0")}` : i.number, amt_total: Number(i.amt_total ?? 0), currency: i.currency || "PEN" };
    }),
    ledger: (led.data ?? []).map(l => ({ ...l, kind: l.kind as "cargo" | "abono", amount: Number(l.amount) })),
    canCollect: can(c.access, "collect") && hasFeature(c.license, "fiados"),
  };
}

const creditMoveSchema = z.object({
  kind: z.enum(["cargo", "abono"]),
  amount: z.coerce.number().positive().max(10_000_000),
  method: z.union([z.literal(""), z.enum(["efectivo", "yape", "plin", "transferencia", "tarjeta", "otro"])]),
  description: optional(200),
  due_date: z.union([z.literal(""), z.iso.date()]),
});

/** Record a fiado (cargo) or a payment towards it (abono) in the same ledger the mobile «Libreta de fiados» uses. */
export async function addCreditMove(org: string, clientId: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  if (!uuid.safeParse(clientId).success) return { ok: false, message: "Cliente no válido." };
  const ctx = await clientsContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const { c } = ctx;
  if (!can(c.access, "collect") || !hasFeature(c.license, "fiados")) return { ok: false, message: "Tu plan o tu rol no permiten registrar fiados." };
  const parsed = creditMoveSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { ok: false, message: "Indica un importe mayor que cero." };
  const d = parsed.data;
  const result = await c.db.from("credit_ledger").insert({
    org_id: org, client_id: clientId, user_id: c.user.id, kind: d.kind, amount: Math.round(d.amount * 100) / 100,
    method: d.kind === "abono" ? d.method || "efectivo" : null, description: d.description || null,
    due_date: d.kind === "cargo" && d.due_date ? d.due_date : null,
  });
  if (result.error) return { ok: false, message: "No se pudo registrar. Revisa tus permisos." };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: d.kind === "abono" ? "Abono registrado. El saldo ya bajó también en el móvil." : "Fiado anotado en la libreta." };
}

/** Caja module context: module rights re-read on the server for every call. */
async function cashContext(org: string) {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "caja")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { c: null, error: "Tus permisos han cambiado. Actualiza la página." } as const;
  return { c, error: "" } as const;
}

const cashMoveSchema = z.object({
  kind: z.enum(["apertura", "ingreso", "egreso"]),
  amount: z.string().max(20),
  method: z.enum(["efectivo", "yape", "plin", "transferencia", "tarjeta", "otro"]),
  note: optional(200),
});

/** Opening, extra income or cash withdrawal for today, in the same table the mobile till uses. */
export async function addCashMove(org: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await cashContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = cashMoveSchema.safeParse(Object.fromEntries(form));
  const amount = parsed.success ? parseAmount(parsed.data.amount) : null;
  if (!parsed.success || amount === null || (amount <= 0 && parsed.data.kind !== "apertura")) return { ok: false, message: "Indica un importe válido, por ejemplo 150.50." };
  const d = parsed.data;
  if (d.kind === "egreso" && !d.note) return { ok: false, message: "Escribe para qué fue el retiro: queda en el reporte del dueño." };
  const { c } = ctx;
  const result = await c.db.from("cash_movements").insert({ org_id: org, user_id: c.user.id, kind: d.kind, amount, method: d.kind === "apertura" ? "efectivo" : d.method, note: d.note || null });
  if (result.error) return { ok: false, message: "No se pudo registrar. Revisa tus permisos." };
  revalidatePath(`/erp/${org}/caja`);
  return { ok: true, message: d.kind === "apertura" ? "Caja abierta. El móvil ya ve la apertura." : d.kind === "ingreso" ? "Ingreso registrado." : "Retiro registrado." };
}

const closeSchema = z.object({ day: z.iso.date(), counted: z.string().max(20), note: optional(300) });

/** Blind cash count: same rules as the mobile close (reason required for a difference, no overwrite). */
export async function closeCashDay(org: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await cashContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = closeSchema.safeParse(Object.fromEntries(form));
  const counted = parsed.success ? parseAmount(parsed.data.counted) : null;
  if (!parsed.success || counted === null) return { ok: false, message: "Escribe el efectivo que contaste en caja, por ejemplo 320.00." };
  const r = await closeDay(ctx.c.db, ctx.c.user.id, org, parsed.data.day, counted, parsed.data.note || null);
  if (r.status >= 400 || !r.body.ok) return { ok: false, message: r.body.error ?? "No se pudo cerrar la caja." };
  revalidatePath(`/erp/${org}/caja`);
  return { ok: true, message: r.body.emailed ? "Caja cerrada. Enviamos el reporte al dueño por correo." : "Caja cerrada y arqueo guardado." };
}
