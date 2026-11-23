/** Pure helpers for the web Compras module (no I/O, fully testable). Mirrors the mobile «Compras y recepción». */

export type PurchaseLine = { product_id: string; quantity: number; unit_cost: number };
export type PurchaseItem = { product_id: string; name: string; quantity: number; unit_cost_cents: number; line_total_cents: number; stock_before: number; stock_after: number };
export type PurchaseRow = {
  id: string; supplier_name: string; document_ref: string | null; payment_method: string; total_cents: number; created_at: string;
  items: PurchaseItem[]; paid: { method: string; paid_cents: number; created_at: string } | null;
};

export const paymentLabel: Record<string, string> = {
  pendiente: "Por pagar", efectivo: "Efectivo (sale de caja)", yape: "Yape", plin: "Plin", transferencia: "Transferencia", tarjeta: "Tarjeta",
};

/** Soles to whole cents without float drift (2.675 → 268). */
export const toCents = (soles: number) => Math.round(Number((soles * 100).toFixed(4)));
/** Quantity × unit cost in cents, rounded as the database does. */
export const lineCents = (l: Pick<PurchaseLine, "quantity" | "unit_cost">) => Math.round(l.quantity * toCents(l.unit_cost));
export const purchaseCents = (lines: Pick<PurchaseLine, "quantity" | "unit_cost">[]) => lines.reduce((a, l) => a + lineCents(l), 0);

/** The first problem with a purchase, in the owner's words, or null when the database will accept it. */
export function purchaseProblem(supplier: string, reference: string, lines: PurchaseLine[]): string | null {
  const s = supplier.trim();
  if (!s) return "Escribe el nombre del proveedor.";
  if (s.length > 120) return "El nombre del proveedor es demasiado largo.";
  if (reference.trim().length > 40) return "El número de comprobante admite hasta 40 caracteres.";
  if (!lines.length) return "Agrega al menos un producto.";
  if (lines.length > 50) return "Una compra admite hasta 50 productos.";
  const seen = new Set<string>();
  for (const [i, l] of lines.entries()) {
    const n = lines.length > 1 ? ` en la línea ${i + 1}` : "";
    if (!l.product_id) return `Elige el producto${n}.`;
    if (seen.has(l.product_id)) return "Un mismo producto figura dos veces: junta las cantidades en una línea.";
    seen.add(l.product_id);
    if (!(l.quantity > 0) || l.quantity > 100000 || Math.round(l.quantity * 100) !== l.quantity * 100) return `La cantidad${n} debe ser mayor que cero, con hasta 2 decimales.`;
    if (!(l.unit_cost >= 0) || l.unit_cost > 10_000_000) return `Revisa el costo unitario${n}.`;
  }
  if (purchaseCents(lines) <= 0) return "El total de la compra debe ser mayor que cero.";
  return null;
}

export const isPending = (p: Pick<PurchaseRow, "payment_method" | "paid">) => p.payment_method === "pendiente" && !p.paid;

export function summarizePurchases(rows: PurchaseRow[], month: string) {
  let monthCents = 0, payableCents = 0, payable = 0;
  for (const r of rows) {
    if (r.created_at.slice(0, 7) === month) monthCents += r.total_cents;
    if (isPending(r)) { payableCents += r.total_cents; payable++; }
  }
  return { month: monthCents / 100, payable: payableCents / 100, payableCount: payable };
}

/** Past suppliers, most used first, for the supplier field suggestions. */
export function supplierSuggestions(rows: Pick<PurchaseRow, "supplier_name">[]): string[] {
  const count = new Map<string, number>();
  for (const r of rows) count.set(r.supplier_name, (count.get(r.supplier_name) ?? 0) + 1);
  return [...count.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], "es")).map(([s]) => s).slice(0, 30);
}
