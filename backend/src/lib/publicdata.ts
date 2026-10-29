import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { isToken, totalsOf } from "@/lib/publicbase";

/**
 * Datos que ve el CLIENTE FINAL en las páginas públicas (/cotizacion/<token>, /pagar/<token>).
 * El token (64 hex, 244 bits de azar) es la única llave. Se devuelve solo lo que ya figura en el comprobante.
 */

type Rel<T> = T | T[] | null;
const one = <T>(v: Rel<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);

export type PublicItem = { description: string; quantity: number; unit_price: number };

export type PublicQuote = {
  id: string;
  orgId: string;
  userId: string;
  number: string;
  status: "draft" | "sent" | "accepted" | "rejected" | "converted";
  issueDate: string;
  validUntil: string | null;
  expired: boolean;
  currency: string;
  taxRate: number;
  notes: string;
  client: string;
  business: string;
  businessTaxId: string;
  items: PublicItem[];
  subtotal: number;
  tax: number;
  total: number;
  responderName: string;
};

export const limaToday = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());

export async function getPublicQuote(token: string): Promise<PublicQuote | null> {
  if (!isToken(token)) return null;
  const admin = createAdminClient();
  const { data: q } = await admin
    .from("quotes")
    .select(
      "id, org_id, user_id, number, status, issue_date, valid_until, currency, tax_rate, notes, responder_name, clients(name), organizations(name, trade_name, tax_id), quote_items(description, quantity, unit_price, position)",
    )
    .eq("public_token", token)
    .order("position", { referencedTable: "quote_items", ascending: true })
    .maybeSingle();
  if (!q) return null;
  const items = ((q.quote_items ?? []) as { description: string; quantity: number | string; unit_price: number | string }[]).map((i) => ({
    description: i.description,
    quantity: Number(i.quantity),
    unit_price: Number(i.unit_price),
  }));
  const t = totalsOf(items, q.tax_rate as number);
  const org = one(q.organizations as Rel<{ name: string; trade_name: string | null; tax_id: string | null }>);
  const status = q.status as PublicQuote["status"];
  return {
    id: q.id as string,
    orgId: q.org_id as string,
    userId: q.user_id as string,
    number: q.number as string,
    status,
    issueDate: q.issue_date as string,
    validUntil: (q.valid_until as string | null) ?? null,
    expired: (status === "draft" || status === "sent") && !!q.valid_until && (q.valid_until as string) < limaToday(),
    currency: q.currency as string,
    taxRate: Number(q.tax_rate),
    notes: (q.notes as string | null) ?? "",
    client: one(q.clients as Rel<{ name: string }>)?.name ?? "",
    business: org?.trade_name || org?.name || "",
    businessTaxId: org?.tax_id ?? "",
    items,
    ...t,
    responderName: (q.responder_name as string | null) ?? "",
  };
}

export type PublicInvoice = {
  invoiceId: string;
  orgId: string;
  createdBy: string;
  number: string;
  docLabel: string;
  issueDate: string;
  dueDate: string | null;
  currency: string;
  client: string;
  business: string;
  businessTaxId: string;
  items: PublicItem[];
  subtotal: number;
  tax: number;
  total: number;
  paid: number;
  balance: number;
  payable: boolean; // false si está anulada, en borrador o rechazada
  overdue: boolean;
  pay: {
    yape: string;
    plin: string;
    bankName: string;
    bankAccount: string;
    bankCci: string;
    holder: string;
    note: string;
    mp: boolean;
  };
  pendingClaims: number;
};

export async function getPublicInvoice(token: string): Promise<PublicInvoice | null> {
  if (!isToken(token)) return null;
  const admin = createAdminClient();
  const { data: link } = await admin.from("pay_links").select("invoice_id, org_id, created_by").eq("token", token).maybeSingle();
  if (!link) return null;
  const { data: inv } = await admin
    .from("invoices")
    .select(
      "id, number, status, issue_date, due_date, currency, tax_rate, clients(name), organizations(name, trade_name, tax_id), invoice_items(description, quantity, unit_price, position), payments(amount), fiscal_documents(status, series, correlative, doc_type), fiscal_notes(status)",
    )
    .eq("id", link.invoice_id)
    .order("position", { referencedTable: "invoice_items", ascending: true })
    .maybeSingle();
  if (!inv) return null;
  const { data: ps } = await admin.from("org_pay_settings").select("*").eq("org_id", link.org_id).maybeSingle();
  const { count } = await admin
    .from("payment_claims")
    .select("id", { count: "exact", head: true })
    .eq("invoice_id", link.invoice_id)
    .eq("status", "pending");

  const items = ((inv.invoice_items ?? []) as { description: string; quantity: number | string; unit_price: number | string }[]).map((i) => ({
    description: i.description,
    quantity: Number(i.quantity),
    unit_price: Number(i.unit_price),
  }));
  const t = totalsOf(items, inv.tax_rate as number);
  const paid = Math.round(((inv.payments ?? []) as { amount: number | string }[]).reduce((s, p) => s + Number(p.amount), 0) * 100) / 100;
  const balance = Math.max(0, Math.round((t.total - paid) * 100) / 100);
  const fd = one(inv.fiscal_documents as Rel<{ status: string; series: string; correlative: number; doc_type: string }>);
  const note = one(inv.fiscal_notes as Rel<{ status: string }>);
  const org = one(inv.organizations as Rel<{ name: string; trade_name: string | null; tax_id: string | null }>);
  const accepted = fd?.status === "accepted";
  const number = accepted ? `${fd!.series}-${String(fd!.correlative).padStart(8, "0")}` : (inv.number as string);
  const docLabel = accepted ? (fd!.doc_type === "01" ? "Factura electrónica" : "Boleta de venta electrónica") : "Nota de venta";
  const payable = inv.status === "sent" && fd?.status !== "rejected" && note?.status !== "accepted" && balance > 0.004;
  return {
    invoiceId: inv.id as string,
    orgId: link.org_id as string,
    createdBy: link.created_by as string,
    number,
    docLabel,
    issueDate: inv.issue_date as string,
    dueDate: (inv.due_date as string | null) ?? null,
    currency: inv.currency as string,
    client: one(inv.clients as Rel<{ name: string }>)?.name ?? "",
    business: org?.trade_name || org?.name || "",
    businessTaxId: org?.tax_id ?? "",
    items,
    ...t,
    paid,
    balance,
    payable,
    overdue: payable && !!inv.due_date && (inv.due_date as string) < limaToday(),
    pay: {
      yape: (ps?.yape_phone as string | null) ?? "",
      plin: (ps?.plin_phone as string | null) ?? "",
      bankName: (ps?.bank_name as string | null) ?? "",
      bankAccount: (ps?.bank_account as string | null) ?? "",
      bankCci: (ps?.bank_cci as string | null) ?? "",
      holder: (ps?.account_holder as string | null) ?? "",
      note: (ps?.pay_note as string | null) ?? "",
      mp: ps?.mp_enabled === true,
    },
    pendingClaims: count ?? 0,
  };
}

/** Correo del usuario (para avisarle de una respuesta o de un pago reportado). */
export async function userEmail(userId: string): Promise<string | null> {
  try {
    const { data } = await createAdminClient().auth.admin.getUserById(userId);
    return data.user?.email ?? null;
  } catch {
    return null;
  }
}

/** Mismo origen o sin Origin (navegación). Defensa básica contra envíos desde otros sitios. */
export function sameOrigin(req: Request): boolean {
  const origin = req.headers.get("origin");
  if (!origin) return true;
  try {
    return new URL(origin).host === req.headers.get("host");
  } catch {
    return false;
  }
}

export type StoreProduct = {
  id: string;
  name: string;
  price: number;
  priceWithTax: number;
  service: boolean;
  category: string;
  description: string;
  image: string | null;
  featured: boolean;
  wholesalePrice: number | null;
  wholesaleMinQty: number | null;
  stock: number | null;
};
export type PublicStore = {
  slug: string;
  business: string;
  taxId: string;
  headline: string;
  about: string;
  whatsapp: string;
  currency: string;
  taxRate: number;
  color: string;
  mode: "tienda" | "carta";
  pickup: boolean;
  delivery: boolean;
  deliveryNote: string;
  minOrder: number | null;
  booking: boolean;
  logo: string | null;
  categories: string[];
  products: StoreProduct[];
  pay: { yape: string; plin: string };
};

/** Catálogo público /tienda/<slug> (solo productos activos y visibles en tienda). Fotos con URL firmada (1 h). */
export async function getPublicStore(slug: string): Promise<PublicStore | null> {
  const s = (slug ?? "").toLowerCase();
  if (!/^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/.test(s)) return null;
  const admin = createAdminClient();
  const { data: st } = await admin.from("org_store").select("*").eq("slug", s).maybeSingle();
  if (!st || st.enabled !== true) return null;
  const { data: org } = await admin.from("organizations").select("name, trade_name, tax_id, currency, default_tax_rate, logo_path").eq("id", st.org_id).maybeSingle();
  if (!org) return null;
  const rate = org.default_tax_rate == null ? 18 : Number(org.default_tax_rate);
  // Columnas nuevas (20261108): si la migración aún no corre, se usa el catálogo básico.
  let prods: Record<string, unknown>[] = [];
  const full = await admin
    .from("products")
    .select("id, name, unit_price, unit, category, description, image_path, featured, wholesale_price, wholesale_min_qty, stock, sort")
    .eq("org_id", st.org_id)
    .eq("active", true)
    .eq("in_store", true)
    .order("featured", { ascending: false })
    .order("sort", { ascending: true })
    .order("name", { ascending: true })
    .limit(400);
  if (full.error) {
    const basic = await admin.from("products").select("id, name, unit_price, unit").eq("org_id", st.org_id).eq("active", true).eq("in_store", true).order("name").limit(400);
    prods = (basic.data ?? []) as Record<string, unknown>[];
  } else prods = (full.data ?? []) as Record<string, unknown>[];
  const paths = prods.map((p) => p.image_path).filter((x): x is string => typeof x === "string" && x.length > 0);
  const signed = new Map<string, string>();
  if (paths.length) {
    const { data: urls } = await admin.storage.from("org-media").createSignedUrls(paths, 3600);
    for (const u of urls ?? []) if (u.path && u.signedUrl) signed.set(u.path, u.signedUrl);
  }
  let logo: string | null = null;
  if (org.logo_path) {
    const { data: lu } = await admin.storage.from("org-media").createSignedUrl(org.logo_path as string, 3600);
    logo = lu?.signedUrl ?? null;
  }
  const withTax = (n: number) => Math.round(n * (1 + rate / 100) * 100) / 100;
  const products: StoreProduct[] = prods.map((p) => {
    const price = Number(p.unit_price);
    const wp = p.wholesale_price == null ? null : Number(p.wholesale_price);
    return {
      id: String(p.id),
      name: String(p.name),
      price,
      priceWithTax: withTax(price),
      service: p.unit === "ZZ",
      category: String(p.category ?? "").trim(),
      description: String(p.description ?? ""),
      image: typeof p.image_path === "string" ? signed.get(p.image_path) ?? null : null,
      featured: p.featured === true,
      wholesalePrice: wp == null ? null : withTax(wp),
      wholesaleMinQty: p.wholesale_min_qty == null ? null : Number(p.wholesale_min_qty),
      stock: st.show_stock === true && p.stock != null ? Number(p.stock) : null,
    };
  });
  const categories = [...new Set(products.map((p) => p.category).filter(Boolean))].sort((a, b) => a.localeCompare(b, "es"));
  return {
    slug: s,
    business: (org.trade_name as string | null) || (org.name as string),
    taxId: (org.tax_id as string | null) ?? "",
    headline: (st.headline as string | null) ?? "",
    about: (st.about as string | null) ?? "",
    whatsapp: (st.whatsapp as string | null) ?? "",
    currency: (org.currency as string | null) ?? "PEN",
    taxRate: rate,
    color: /^#[0-9a-fA-F]{6}$/.test(String(st.theme_color ?? "")) ? String(st.theme_color) : "#6a62e2",
    mode: st.mode === "carta" ? "carta" : "tienda",
    pickup: st.pickup !== false,
    delivery: st.delivery === true,
    deliveryNote: (st.delivery_note as string | null) ?? "",
    minOrder: st.min_order == null ? null : Number(st.min_order),
    booking: st.booking === true,
    logo,
    categories,
    products,
    pay: await (async () => {
      // Yape/Plin para pagar al hacer el pedido (solo números públicos que el dueño eligió mostrar).
      const { data: ps } = await admin.from("org_pay_settings").select("yape_phone, plin_phone").eq("org_id", st.org_id).maybeSingle();
      return { yape: (ps?.yape_phone as string | null) ?? "", plin: (ps?.plin_phone as string | null) ?? "" };
    })(),
  };
}
