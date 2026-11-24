/** Quick sale on the web (same rules as the mobile POS): code lookup, scale labels, cart and change. Pure: tested. */

export type PosProduct = { id: string; name: string; unit_price: number; unit: string; stock: number | null; barcode: string | null; icbper: boolean; category: string | null; image_url: string | null };
export type CartLine = { product_id: string; name: string; unit_price: number; quantity: number; unit: string; stock: number | null };

export function ean13Check(twelve: string): number {
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += (twelve.charCodeAt(i) - 48) * (i % 2 === 0 ? 1 : 3);
  return (10 - (sum % 10)) % 10;
}

/** Variable-weight EAN-13 from the scale: 2X + PLU (5) + grams (5) + check. */
export function parseScaleLabel(raw: string): { plu: string; prefixPlu: string; kilos: number } | null {
  const code = raw.trim();
  if (!/^2\d{12}$/.test(code)) return null;
  if (ean13Check(code.slice(0, 12)) !== code.charCodeAt(12) - 48) return null;
  const grams = Number(code.slice(7, 12));
  if (grams <= 0) return null;
  return { plu: code.slice(2, 7), prefixPlu: code.slice(0, 7), kilos: grams / 1000 };
}

function matchesScale(barcode: string, l: { plu: string; prefixPlu: string }): boolean {
  const b = barcode.trim();
  if (!b) return false;
  return b === l.plu || b === l.prefixPlu || (/^\d{1,5}$/.test(b) && Number(b) === Number(l.plu));
}

/** What a scanned or typed code sells: the product (main or extra code) and, for a scale label, its weight. */
export function findByCode(code: string, products: PosProduct[], extra: Record<string, string>): { product: PosProduct; quantity: number } | null {
  const c = code.trim();
  if (!c) return null;
  const direct = products.find(p => p.barcode?.trim() === c) ?? (extra[c] ? products.find(p => p.id === extra[c]) : undefined);
  if (direct) return { product: direct, quantity: 1 };
  const label = parseScaleLabel(c);
  if (label) {
    const p = products.find(x => x.barcode && matchesScale(x.barcode, label));
    if (p) return { product: p, quantity: label.kilos };
  }
  return null;
}

const round = (n: number, d = 3) => Math.round(n * 10 ** d) / 10 ** d;

/** Adds to the cart: the same product sums up (by weight products too). */
export function addToCart(cart: CartLine[], p: PosProduct, quantity: number): CartLine[] {
  const i = cart.findIndex(l => l.product_id === p.id);
  if (i >= 0) return cart.map((l, j) => j === i ? { ...l, quantity: round(l.quantity + quantity) } : l);
  return [...cart, { product_id: p.id, name: p.name, unit_price: Number(p.unit_price), quantity: round(quantity), unit: p.unit, stock: p.stock }];
}

export function setQuantity(cart: CartLine[], productId: string, quantity: number): CartLine[] {
  return quantity <= 0 ? cart.filter(l => l.product_id !== productId) : cart.map(l => l.product_id === productId ? { ...l, quantity: round(quantity) } : l);
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/** Same totals as the mobile POS (computeTotals): prices without tax, tax per line rounded, total = both. */
export function cartTotals(cart: CartLine[], taxRate: number): { subtotal: number; tax: number; total: number } {
  const subtotal = r2(cart.reduce((s, l) => s + r2(l.unit_price * l.quantity), 0));
  const tax = r2(cart.reduce((s, l) => s + r2(r2(l.unit_price * l.quantity) * taxRate / 100), 0));
  return { subtotal, tax, total: r2(subtotal + tax) };
}

/** Shelf price shown to the buyer (with tax). */
export const shelfPrice = (p: { unit_price: number }, taxRate: number) => r2(Number(p.unit_price) * (1 + taxRate / 100));

/** Change for cash; null when what was received does not cover the total. */
export function changeFor(total: number, received: number): number | null {
  if (!Number.isFinite(received) || received + 1e-9 < total) return null;
  return Math.round((received - total) * 100) / 100;
}

/** Lines that would leave stock below zero (products with stock control only). */
export function stockProblems(cart: CartLine[]): string[] {
  return cart.filter(l => l.stock != null && l.quantity > l.stock).map(l => `${l.name}: quedan ${l.stock}`);
}

/** Quick bills for the cash keypad: exact and the next round amounts. */
export function quickCash(total: number): number[] {
  const out = new Set<number>([Math.ceil(total * 10) / 10]);
  for (const step of [1, 5, 10, 20, 50, 100, 200]) out.add(Math.ceil(total / step) * step);
  return [...out].filter(v => v >= total).sort((a, b) => a - b).slice(0, 5);
}

/** Product search by name, category or code (accents ignored). */
export function searchProducts(q: string, products: PosProduct[], limit = 60): PosProduct[] {
  const norm = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const n = norm(q.trim());
  if (!n) return products.slice(0, limit);
  const words = n.split(/\s+/);
  return products.filter(p => {
    const hay = norm(`${p.name} ${p.category ?? ""} ${p.barcode ?? ""}`);
    return words.every(w => hay.includes(w));
  }).slice(0, limit);
}
