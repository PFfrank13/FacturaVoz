"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { workspaceContext } from "@/lib/erp/context";
import { modules, moduleAllowed, can, hasFeature } from "@/lib/erp/access";
import { lookupDocument, type LookupReply } from "@/lib/lookup";
import { docTypeOf } from "@/lib/erp/clients";
import { closeDay } from "@/lib/dayclose-core";
import { parseAmount } from "@/lib/erp/cash";
import { purchaseProblem, toCents, type PurchaseLine } from "@/lib/erp/purchases";
import { mergeKardex, type KardexEntry } from "@/lib/erp/kardex";
import { lossProblem, type LotStatus } from "@/lib/erp/lots";
import { couponProblem, promoProblem } from "@/lib/erp/loyalty";
import { newShelfPrice, pricingProblem, withTax, withoutTax, type PriceMode } from "@/lib/erp/pricing";

export type FormResult = { ok: boolean; message: string };
const name = z.string().trim().min(1).max(120);
const clientSchema = z.object({ name, email: z.union([z.literal(""), z.email().max(200)]), phone: z.string().trim().max(30), tax_id: z.string().trim().max(20) });
const productSchema = z.object({ name, unit_price: z.coerce.number().min(0).max(10_000_000), unit: z.enum(["NIU", "ZZ", "KGM"]) });
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
  icbper: z.enum(["on"]).optional(),
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
  const { name: productName, unit_price, category, reorder_point, unit_cost, active, icbper } = parsed.data;
  const result = await ctx.c.db.from("products")
    .update({ name: productName, unit_price, category: category || null, reorder_point: reorder_point === "" ? null : reorder_point, active: active === "on",
      // Only touch the cost when the form sends it, so other editors never erase it.
      ...(unit_cost === undefined ? {} : { unit_cost: unit_cost === "" ? null : unit_cost }),
      // The bag checkbox is only rendered for unit products; its hidden marker says the form carried it.
      ...(form.get("icbper_shown") === "1" ? { icbper: icbper === "on" } : {}) })
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

export type ReceiptShare =
  | { ok: true; path: string; phone: string; email: string; business: string }
  | { ok: false; message: string };

/**
 * Private link of one receipt for its customer (the same `doc_links` token the
 * mobile «Enlace» shares, created by `invoice_portal_link` under the user's RLS),
 * plus the customer's phone and e-mail to send it by WhatsApp or mail.
 */
export async function shareReceipt(org: string, invoiceId: string): Promise<ReceiptShare> {
  if (!uuid.safeParse(invoiceId).success) return { ok: false, message: "Comprobante no válido." };
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "comprobantes")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { ok: false, message: "Tus permisos han cambiado. Actualiza la página." };
  const inv = await c.db.from("invoices").select("id,client:clients(phone,email)").eq("org_id", org).eq("id", invoiceId).maybeSingle();
  if (inv.error || !inv.data) return { ok: false, message: "No encontramos ese comprobante." };
  const link = await c.db.rpc("invoice_portal_link", { p_invoice: invoiceId });
  if (link.error || typeof link.data !== "string" || !/^[A-Za-z0-9_-]{20,80}$/.test(link.data)) return { ok: false, message: "No se pudo crear el enlace. Inténtalo de nuevo." };
  const raw = (inv.data as { client: unknown }).client;
  const client = (Array.isArray(raw) ? raw[0] : raw) as { phone?: string | null; email?: string | null } | null;
  return { ok: true, path: `/comprobante/${link.data}`, phone: client?.phone ?? "", email: client?.email ?? "", business: c.organization?.name ?? "" };
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

/** Compras context: only the owner or an administrator receives and pays purchases (the database enforces it too). */
async function purchasesContext(org: string) {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "compras")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { c: null, error: "Tus permisos han cambiado. Actualiza la página." } as const;
  if (!c.access.is_admin) return { c: null, error: "Solo el dueño o un administrador registra compras." } as const;
  return { c, error: "" } as const;
}

const purchaseSchema = z.object({
  request_id: uuid,
  supplier: z.string().max(120),
  reference: z.string().max(40),
  payment_method: z.enum(["pendiente", "efectivo", "yape", "plin", "transferencia", "tarjeta"]),
  lines: z.array(z.object({ product_id: uuid, quantity: z.number(), unit_cost: z.number(), expires_on: z.union([z.literal(""), z.iso.date()]).optional() })).min(1).max(50),
});

const dbMessage = (message: string | undefined, fallback: string) =>
  message && /^[A-ZÁÉÍÓÚÑ][^\n]{5,160}$/.test(message) && !/violates|syntax|relation|column/i.test(message) ? message : fallback;

/**
 * Receive goods: stock, unit cost, kardex, expense and (if paid in cash) the till withdrawal happen in one
 * database transaction (retail_receive). The request id makes a retried submit safe: it never doubles stock.
 */
export async function receivePurchase(org: string, input: { request_id: string; supplier: string; reference: string; payment_method: string; lines: PurchaseLine[] }): Promise<FormResult & { id?: string }> {
  const ctx = await purchasesContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = purchaseSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Revisa el proveedor, el medio de pago y los productos." };
  const d = parsed.data;
  const problem = purchaseProblem(d.supplier, d.reference, d.lines);
  if (problem) return { ok: false, message: problem };
  const { data, error } = await ctx.c.db.rpc("retail_receive", {
    p_org: org, p_request_id: d.request_id, p_supplier: d.supplier.trim(), p_reference: d.reference.trim(), p_payment_method: d.payment_method,
    p_items: d.lines.map(l => ({ product_id: l.product_id, quantity: Math.round(l.quantity * 100) / 100, unit_cost_cents: toCents(l.unit_cost) })),
  });
  const row = Array.isArray(data) ? data[0] as { receipt_id?: string; reused?: boolean } | undefined : undefined;
  if (error || !row?.receipt_id) return { ok: false, message: dbMessage(error?.message, "No se pudo registrar la compra. Inténtalo de nuevo: no se duplicará.") };
  // Expiry dates go right after the receipt (retail_set_lots replaces the lots of that receipt, so a retry is safe).
  const lots = d.lines.filter(l => l.expires_on).map(l => ({ product_id: l.product_id, expires_on: l.expires_on, quantity: Math.round(l.quantity * 100) / 100 }));
  let lotNote = "";
  if (lots.length) {
    const set = await ctx.c.db.rpc("retail_set_lots", { p_org: org, p_receipt: row.receipt_id, p_lots: lots });
    lotNote = set.error ? " No se guardaron las fechas de vencimiento: añádelas desde la ficha del producto." : ` Se ${lots.length === 1 ? "guardó una fecha" : `guardaron ${lots.length} fechas`} de vencimiento.`;
  }
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, id: row.receipt_id, message: (row.reused ? "Esta compra ya estaba registrada; no se duplicó el stock." : "Compra recibida: el stock y el costo ya se actualizaron en el móvil.") + lotNote };
}

const settleSchema = z.object({ receipt: uuid, request_id: uuid, method: z.enum(["efectivo", "yape", "plin", "transferencia", "tarjeta"]), evidence: z.string().trim().max(200) });

/** Pay a purchase that was received as «por pagar» (one payment per purchase, idempotent). */
export async function settlePurchase(org: string, input: { receipt: string; request_id: string; method: string; evidence: string }): Promise<FormResult> {
  const ctx = await purchasesContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = settleSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Elige el medio de pago." };
  const d = parsed.data;
  const { error } = await ctx.c.db.rpc("retail_settle", { p_org: org, p_receipt: d.receipt, p_request_id: d.request_id, p_method: d.method, p_evidence: d.evidence });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo registrar el pago.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: d.method === "efectivo" ? "Pago registrado y descontado de la caja de hoy." : "Pago registrado." };
}

/** Stock movements of one product (purchases and sales), for the owner or an administrator. */
export async function getKardex(org: string, productId: string): Promise<{ ok: true; rows: KardexEntry[] } | { ok: false; message: string }> {
  if (!uuid.safeParse(productId).success) return { ok: false, message: "Producto no válido." };
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "inventario")!;
  const catalog = modules.find(m => m.id === "productos")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector) && !moduleAllowed(catalog, c.license, c.access, c.sector)) return { ok: false, message: "Tus permisos han cambiado. Actualiza la página." };
  if (!c.access.is_admin) return { ok: false, message: "El kardex lo ve el dueño o un administrador." };
  const [buys, sales, losses] = await Promise.all([
    c.db.from("retail_inventory_events").select("created_at,quantity_delta,stock_before,stock_after,receipt:retail_receipts(supplier_name,document_ref)").eq("org_id", org).eq("product_id", productId).order("created_at", { ascending: false }).limit(30),
    c.db.from("retail_sale_stock_events").select("created_at,quantity_delta,stock_before,stock_after,invoice:invoices(number)").eq("org_id", org).eq("product_id", productId).order("created_at", { ascending: false }).limit(30),
    c.db.from("stock_losses").select("created_at,quantity,stock_before,stock_after,reason,note").eq("org_id", org).eq("product_id", productId).order("created_at", { ascending: false }).limit(30),
  ]);
  if (buys.error || sales.error) return { ok: false, message: "No se pudo cargar el kardex." };
  return { ok: true, rows: mergeKardex(buys.data ?? [], sales.data ?? [], 30, losses.data ?? []) };
}

/** Inventory context: lots and shrinkage move stock, so only roles with products_edit (owner, admin, finance). */
async function inventoryContext(org: string) {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "inventario")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { c: null, error: "Tus permisos han cambiado. Actualiza la página." } as const;
  if (!can(c.access, "products_edit")) return { c: null, error: "Las mermas y los lotes los registra el dueño, un administrador o finanzas." } as const;
  return { c, error: "" } as const;
}

const lossSchema = z.object({
  request_id: uuid, product_id: uuid, quantity: z.string().max(20), reason: z.string().max(20),
  lot_id: z.union([z.literal(""), uuid]).default(""), note: optional(200).default(""),
});

/** Shrinkage with a reason: lowers stock and records who, how much, why and at what cost (record_loss, idempotent). */
export async function recordLoss(org: string, stock: number | null, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await inventoryContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = lossSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { ok: false, message: "Revisa la cantidad y el motivo." };
  const d = parsed.data;
  const quantity = parseAmount(d.quantity);
  const problem = lossProblem(quantity, d.reason, d.note, stock);
  if (problem) return { ok: false, message: problem };
  const { error } = await ctx.c.db.rpc("record_loss", {
    p_org: org, p_request_id: d.request_id, p_product: d.product_id, p_quantity: Math.round(quantity! * 100) / 100,
    p_reason: d.reason, p_lot: d.lot_id || null, p_note: d.note || null,
  });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo registrar la merma. Inténtalo de nuevo: no se duplicará.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Merma registrada: el stock ya bajó también en el móvil." };
}

const lotSchema = z.object({ expires_on: z.iso.date(), quantity: z.string().max(20), lot_code: optional(40).default("") });

/** Expiry date for stock already on the shelf (no purchase recorded). */
export async function addLot(org: string, productId: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  if (!uuid.safeParse(productId).success) return { ok: false, message: "Producto no válido." };
  const ctx = await inventoryContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = lotSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { ok: false, message: "Elige la fecha de vencimiento." };
  const quantity = parseAmount(parsed.data.quantity);
  if (quantity == null || !(quantity > 0)) return { ok: false, message: "Escribe cuántas unidades vencen en esa fecha." };
  const { error } = await ctx.c.db.rpc("product_lot_add", { p_org: org, p_product: productId, p_expires: parsed.data.expires_on, p_quantity: Math.round(quantity * 100) / 100, p_code: parsed.data.lot_code || null });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo guardar el lote.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Fecha de vencimiento guardada." };
}

export async function removeLot(org: string, lotId: string): Promise<FormResult> {
  if (!uuid.safeParse(lotId).success) return { ok: false, message: "Lote no válido." };
  const ctx = await inventoryContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const { error } = await ctx.c.db.rpc("product_lot_remove", { p_org: org, p_lot: lotId });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo quitar el lote.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Lote quitado." };
}

/** Lots of one product with what is left of each (FEFO), for its sheet. */
export async function getProductLots(org: string, productId: string): Promise<{ ok: true; lots: LotStatus[] } | { ok: false; message: string }> {
  if (!uuid.safeParse(productId).success) return { ok: false, message: "Producto no válido." };
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "inventario")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { ok: false, message: "Tus permisos han cambiado. Actualiza la página." };
  const { data, error } = await c.db.rpc("lot_status", { p_org: org });
  if (error) return { ok: false, message: "No se pudieron cargar los vencimientos." };
  const lots = ((data ?? []) as LotStatus[]).filter(l => l.product_id === productId)
    .map(l => ({ ...l, quantity: Number(l.quantity), remaining: Number(l.remaining), days_left: Number(l.days_left) }))
    .sort((a, b) => a.expires_on.localeCompare(b.expires_on));
  return { ok: true, lots };
}

/** Promotions and coupons: products_edit rights and the «precios» feature, like the mobile «Precios y promociones». */
async function promosContext(org: string, coupons = false) {
  const c = await workspaceContext(org);
  const allowed = (id: string) => moduleAllowed(modules.find(m => m.id === id)!, c.license, c.access, c.sector);
  // Coupons also come with «Puntos» (fidelizacion, plan Pro de bodega, v3.8a); changing them needs products_edit.
  const ok = allowed("promociones") || (coupons && allowed("puntos") && can(c.access, "products_edit"));
  if (!ok) return { c: null, error: "Tus permisos han cambiado. Actualiza la página." } as const;
  return { c, error: "" } as const;
}

const optionalDate = z.union([z.literal(""), z.iso.date()]).default("");
const promoSchema = z.object({ name: z.string().max(80), kind: z.string().max(20), value: z.string().max(20), min_qty: z.string().max(20).default(""), starts_on: optionalDate, ends_on: optionalDate });

export async function savePromotion(org: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await promosContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = promoSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { ok: false, message: "Revisa el nombre, el descuento y las fechas." };
  const d = parsed.data;
  const value = parseAmount(d.value);
  const minQty = d.min_qty ? parseAmount(d.min_qty) : null;
  const problem = promoProblem({ name: d.name, kind: d.kind, value, minQty, startsOn: d.starts_on, endsOn: d.ends_on });
  if (problem) return { ok: false, message: problem };
  const { error } = await ctx.c.db.from("promotions").insert({
    org_id: org, name: d.name.trim(), kind: d.kind, value, product_ids: [], min_qty: d.kind === "volumen" ? minQty : null,
    starts_on: d.starts_on || null, ends_on: d.ends_on || null, active: true,
  });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo crear la promoción.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Promoción creada: el punto de venta la aplica sola en sus fechas." };
}

export async function togglePromotion(org: string, id: string, active: boolean): Promise<FormResult> {
  if (!uuid.safeParse(id).success) return { ok: false, message: "Promoción no válida." };
  const ctx = await promosContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const { error } = await ctx.c.db.from("promotions").update({ active }).eq("org_id", org).eq("id", id);
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo cambiar la promoción.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: active ? "Promoción reanudada." : "Promoción pausada." };
}

const couponSchema = z.object({ code: z.string().max(20), kind: z.string().max(20), value: z.string().max(20), max_uses: z.string().max(10).default(""), expires_on: optionalDate });

export async function createCoupon(org: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await promosContext(org, true);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = couponSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return { ok: false, message: "Revisa el código y el descuento." };
  const d = parsed.data;
  const value = parseAmount(d.value);
  const maxUses = d.max_uses.trim() ? Number(d.max_uses) : null;
  const problem = couponProblem({ code: d.code, kind: d.kind, value, maxUses });
  if (problem) return { ok: false, message: problem };
  const { error } = await ctx.c.db.from("coupons").insert({ org_id: org, code: d.code.trim().toUpperCase(), kind: d.kind, value, max_uses: maxUses, expires_on: d.expires_on || null });
  if (error) return { ok: false, message: /duplicate|unique/i.test(error.message) ? "Ya existe un cupón con ese código." : dbMessage(error.message, "No se pudo crear el cupón.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Cupón creado: se canjea escribiendo el código al cobrar en el móvil." };
}

export async function toggleCoupon(org: string, id: string, active: boolean): Promise<FormResult> {
  if (!uuid.safeParse(id).success) return { ok: false, message: "Cupón no válido." };
  const ctx = await promosContext(org, true);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const { error } = await ctx.c.db.from("coupons").update({ active }).eq("org_id", org).eq("id", id);
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo cambiar el cupón.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: active ? "Cupón reanudado." : "Cupón pausado." };
}

/** Points program: the «fidelizacion» feature; the rate is a company setting (settings rights). */
async function pointsContext(org: string) {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "puntos")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { c: null, error: "Tus permisos han cambiado. Actualiza la página." } as const;
  return { c, error: "" } as const;
}

export async function setLoyaltyRate(org: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await pointsContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  if (!can(ctx.c.access, "settings")) return { ok: false, message: "El programa de puntos lo configura el dueño o un administrador." };
  const rate = parseAmount(String(form.get("rate") ?? "0") || "0");
  if (rate == null || rate < 0 || rate > 100) return { ok: false, message: "Escribe cuántos puntos da cada sol (0 a 100)." };
  const { error } = await ctx.c.db.from("org_settings").update({ loyalty_rate: Math.round(rate * 10000) / 10000 }).eq("org_id", org);
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo guardar el programa de puntos.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: rate > 0 ? `Listo: cada sol cobrado suma ${rate} ${rate === 1 ? "punto" : "puntos"}.` : "Programa de puntos apagado." };
}

export async function redeemPoints(org: string, clientId: string, balance: number, _previous: FormResult, form: FormData): Promise<FormResult> {
  if (!uuid.safeParse(clientId).success) return { ok: false, message: "Cliente no válido." };
  const ctx = await pointsContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  if (!can(ctx.c.access, "collect")) return { ok: false, message: "Tu rol no puede canjear puntos." };
  const points = Number(String(form.get("points") ?? "").trim());
  if (!Number.isInteger(points) || points <= 0) return { ok: false, message: "Escribe cuántos puntos canjea (número entero)." };
  if (points > balance) return { ok: false, message: `Solo tiene ${balance} puntos.` };
  const reason = String(form.get("reason") ?? "").trim().slice(0, 120) || "Canje";
  const { error } = await ctx.c.db.from("loyalty_ledger").insert({ org_id: org, client_id: clientId, points: -points, reason });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo canjear.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: `Canjeados ${points} puntos.` };
}

/** Cashier shifts (v3.8c): any role that collects opens its own shift; the database closes it blind. */
export async function openShift(org: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await cashContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const amount = parseAmount(String(form.get("float") ?? ""));
  if (amount == null) return { ok: false, message: "Escribe el fondo inicial, por ejemplo 50.00." };
  const { error } = await ctx.c.db.rpc("shift_open", { p_org: org, p_float: amount });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo abrir el turno.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Turno abierto. Ciérralo al terminar contando tu cajón." };
}

export async function closeShift(org: string, _previous: FormResult, form: FormData): Promise<FormResult> {
  const ctx = await cashContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const counted = parseAmount(String(form.get("counted") ?? ""));
  if (counted == null) return { ok: false, message: "Escribe el efectivo que contaste." };
  const note = String(form.get("note") ?? "").trim().slice(0, 300);
  const { data, error } = await ctx.c.db.rpc("shift_close", { p_org: org, p_counted: counted, p_note: note || null });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo cerrar el turno.") };
  revalidatePath(`/erp/${org}`, "layout");
  const diff = (data as { difference?: number } | null)?.difference;
  if (diff === undefined) return { ok: true, message: "Turno cerrado. El dueño revisará el cuadre." };
  const d = Math.round(Number(diff) * 100) / 100;
  return { ok: true, message: Math.abs(d) <= 0.01 ? "Turno cerrado: cuadró exacto." : `Turno cerrado: ${d > 0 ? "sobraron" : "faltaron"} S/ ${Math.abs(d).toFixed(2)}.` };
}

const transferSchema = z.object({ request_id: uuid, to_org: uuid, from_product: uuid, to_product: uuid, quantity: z.number(), note: z.string().max(200) });

/** Moves goods from this store to another one of the same owner (stock_transfer, idempotent, plan Empresa). */
export async function transferStock(org: string, input: { request_id: string; to_org: string; from_product: string; to_product: string; quantity: number; note: string }): Promise<FormResult> {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "sucursales")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { ok: false, message: "Tus permisos han cambiado. Actualiza la página." };
  if (!c.access.is_admin) return { ok: false, message: "Los traslados los hace el dueño o un administrador." };
  const parsed = transferSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Revisa los productos y la cantidad." };
  const d = parsed.data;
  if (!(d.quantity > 0) || Math.abs(d.quantity * 100 - Math.round(d.quantity * 100)) > 1e-6) return { ok: false, message: "La cantidad debe ser mayor que cero, con hasta 2 decimales." };
  const { data, error } = await c.db.rpc("stock_transfer", { p_request_id: d.request_id, p_from_org: org, p_to_org: d.to_org, p_from_product: d.from_product, p_to_product: d.to_product, p_quantity: d.quantity, p_note: d.note.trim() || null });
  if (error) return { ok: false, message: dbMessage(error.message, "No se pudo trasladar. Inténtalo de nuevo: no se duplicará.") };
  const row = Array.isArray(data) ? data[0] as { from_stock?: number; to_stock?: number; reused?: boolean } | undefined : undefined;
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: row?.reused ? "Ese traslado ya estaba registrado." : `Trasladado. Aquí quedan ${Number(row?.from_stock ?? 0)}; en el destino hay ${Number(row?.to_stock ?? 0)}.` };
}

const countSchema = z.object({ request_id: uuid, lines: z.array(z.object({ product_id: uuid, expected: z.number(), counted: z.number().min(0).max(10_000_000) })).min(1).max(300) });

/**
 * Applies an inventory count. A shortage is shrinkage («Diferencia de conteo», record_loss: idempotent per line);
 * a surplus sets the stock to what was counted only if it still has the value that was on screen (no double add).
 */
export async function applyCount(org: string, input: { request_id: string; lines: { product_id: string; expected: number; counted: number }[] }): Promise<FormResult> {
  const ctx = await inventoryContext(org);
  if (!ctx.c) return { ok: false, message: ctx.error };
  const parsed = countSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Revisa las cantidades contadas." };
  const { request_id, lines } = parsed.data;
  let shortages = 0, surpluses = 0, changed = 0;
  for (const [i, l] of lines.entries()) {
    const counted = Math.round(l.counted * 100) / 100;
    const diff = Math.round((counted - l.expected) * 100) / 100;
    if (diff === 0) continue;
    if (diff < 0) {
      // Deterministic id per count and line: a retried click never records the same shortage twice.
      const lineId = `${request_id.slice(0, 24)}${(i + 1).toString(16).padStart(12, "0")}`;
      const { error } = await ctx.c.db.rpc("record_loss", { p_org: org, p_request_id: lineId, p_product: l.product_id, p_quantity: -diff, p_reason: "otro", p_lot: null, p_note: "Diferencia de conteo" });
      if (error) { changed++; continue; }
      shortages++;
    } else {
      const { data, error } = await ctx.c.db.from("products").update({ stock: counted }).eq("org_id", org).eq("id", l.product_id).eq("stock", l.expected).select("id");
      if (error || !data?.length) { changed++; continue; }
      surpluses++;
    }
  }
  revalidatePath(`/erp/${org}`, "layout");
  const done = shortages + surpluses;
  if (!done) return { ok: false, message: changed ? "El stock cambió mientras contabas (hubo ventas). Vuelve a abrir el conteo." : "No había diferencias que aplicar." };
  return { ok: true, message: `Conteo aplicado: ${shortages} ${shortages === 1 ? "faltante registrado" : "faltantes registrados"} como merma y ${surpluses} ${surpluses === 1 ? "sobrante sumado" : "sobrantes sumados"}.${changed ? ` ${changed} no se aplicaron porque su stock cambió mientras contabas.` : ""}` };
}

const bulkSchema = z.object({ ids: z.array(uuid).min(1).max(500), mode: z.string().max(20), value: z.number() });

/** Changes shelf prices (with IGV) of many products at once, rounded to 0.10; stored back without IGV. */
export async function applyBulkPrices(org: string, input: { ids: string[]; mode: string; value: number }): Promise<FormResult> {
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "productos")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector) || !can(c.access, "products_edit")) return { ok: false, message: "Los precios los cambia el dueño, un administrador o finanzas." };
  const parsed = bulkSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Elige los productos y el cambio." };
  const { ids, mode, value } = parsed.data;
  const problem = pricingProblem(mode, value);
  if (problem) return { ok: false, message: problem };
  const rate = Number(c.organization.default_tax_rate ?? 18);
  const { data, error } = await c.db.from("products").select("id,unit_price").eq("org_id", org).in("id", ids);
  if (error) return { ok: false, message: "No se pudieron leer los productos." };
  let changed = 0, failed = 0;
  for (const p of (data ?? []) as { id: string; unit_price: number | string }[]) {
    const shelf = withTax(Number(p.unit_price), rate);
    const base = withoutTax(newShelfPrice(shelf, mode as PriceMode, value), rate);
    if (base === Number(p.unit_price)) continue;
    const r = await c.db.from("products").update({ unit_price: base }).eq("org_id", org).eq("id", p.id);
    if (r.error) failed++; else changed++;
  }
  revalidatePath(`/erp/${org}`, "layout");
  if (!changed) return { ok: failed === 0, message: failed ? "No se pudieron cambiar los precios." : "Los precios ya estaban así." };
  return { ok: true, message: `Precios cambiados en ${changed} ${changed === 1 ? "producto" : "productos"}${failed ? ` (${failed} sin cambiar)` : ""}. Imprime las etiquetas nuevas.` };
}

const codeRe = /^[0-9A-Za-z.-]{4,40}$/;

/** Main and extra barcodes of a product (v3.9). */
export async function getProductCodes(org: string, productId: string): Promise<{ ok: true; main: string | null; extra: { id: string; code: string }[] } | { ok: false; message: string }> {
  if (!uuid.safeParse(productId).success) return { ok: false, message: "Producto no válido." };
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "productos")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector)) return { ok: false, message: "Tus permisos han cambiado. Actualiza la página." };
  const [main, extra] = await Promise.all([
    c.db.from("products").select("barcode").eq("org_id", org).eq("id", productId).maybeSingle(),
    c.db.from("product_barcodes").select("id,code").eq("org_id", org).eq("product_id", productId).order("created_at"),
  ]);
  if (main.error) return { ok: false, message: "No se pudieron cargar los códigos." };
  return { ok: true, main: (main.data as { barcode: string | null } | null)?.barcode ?? null, extra: (extra.data ?? []) as { id: string; code: string }[] };
}

/** Adds a barcode to a product: the main one if it has none, otherwise an extra one. Never a code of another product. */
export async function addProductCode(org: string, productId: string, raw: string): Promise<FormResult> {
  if (!uuid.safeParse(productId).success) return { ok: false, message: "Producto no válido." };
  const code = raw.trim();
  if (!codeRe.test(code)) return { ok: false, message: "Código no válido: usa de 4 a 40 letras o números." };
  const c = await workspaceContext(org);
  const entry = modules.find(m => m.id === "productos")!;
  if (!moduleAllowed(entry, c.license, c.access, c.sector) || !can(c.access, "products_edit")) return { ok: false, message: "Los códigos los registra el dueño, un administrador o finanzas." };
  const { data: owner } = await c.db.rpc("product_code_owner", { p_org: org, p_code: code });
  const o = Array.isArray(owner) ? owner[0] as { product_id: string; name: string } | undefined : undefined;
  if (o) return { ok: false, message: o.product_id === productId ? "Ese código ya está en este producto." : `El código ${code} ya es de «${o.name}». Un código solo puede ser de un producto.` };
  const { data: prod } = await c.db.from("products").select("barcode").eq("org_id", org).eq("id", productId).maybeSingle();
  const hasMain = !!(prod as { barcode: string | null } | null)?.barcode;
  const r = hasMain
    ? await c.db.from("product_barcodes").insert({ org_id: org, product_id: productId, code })
    : await c.db.from("products").update({ barcode: code }).eq("org_id", org).eq("id", productId);
  if (r.error) return { ok: false, message: /23505|ya es de otro/.test(`${r.error.code} ${r.error.message}`) ? `El código ${code} ya es de otro producto.` : dbMessage(r.error.message, "No se pudo guardar el código.") };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: hasMain ? `Código ${code} agregado: también vende este producto.` : `Código ${code} guardado como principal.` };
}

export async function removeProductCode(org: string, codeId: string): Promise<FormResult> {
  if (!uuid.safeParse(codeId).success) return { ok: false, message: "Código no válido." };
  const c = await workspaceContext(org);
  if (!can(c.access, "products_edit")) return { ok: false, message: "Tu rol no puede quitar códigos." };
  const { error } = await c.db.from("product_barcodes").delete().eq("org_id", org).eq("id", codeId);
  if (error) return { ok: false, message: "No se pudo quitar el código." };
  revalidatePath(`/erp/${org}`, "layout");
  return { ok: true, message: "Código quitado." };
}
