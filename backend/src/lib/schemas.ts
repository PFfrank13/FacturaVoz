import { z } from "zod";

export const itemSchema = z.object({
  description: z.string().trim().min(1).max(200),
  quantity: z.number().positive().max(100000),
  unit_price: z.number().nonnegative().max(10_000_000),
});

export const invoiceInputSchema = z.object({
  client_name: z.string().trim().min(1).max(120),
  client_tax_id: z.string().trim().max(30).optional(),
  tax_rate: z.number().min(0).max(100),
  notes: z.string().max(500).optional(),
  transcript: z.string().max(5000).optional(),
  items: z.array(itemSchema).min(1).max(50),
});

export type InvoiceInput = z.infer<typeof invoiceInputSchema>;
export type ActionResult<T> =
  | { success: true; data: T }
  | { success: false; error: string };

export const money = (n: number, currency = "EUR") =>
  new Intl.NumberFormat("es-PE", { style: "currency", currency }).format(n);

const cents = (n: number) => Math.round(n * 100) / 100;

// Redondeo a céntimos en cada paso para que el PDF coincida con lo que se guarda
export const totals = (items: InvoiceInput["items"], taxRate: number) => {
  const subtotal = cents(items.reduce((s, i) => s + cents(i.quantity * i.unit_price), 0));
  const tax = cents(subtotal * (taxRate / 100));
  return { subtotal, tax, total: cents(subtotal + tax) };
};
