/** Pure helpers for the web «Promociones y puntos» module: the same promotions, coupons and points as the mobile app. */

export const promoKinds = { porcentaje: "% de descuento", monto: "Monto fijo menos", volumen: "Llevando N o más (% menos)" } as const;
export type PromoKind = keyof typeof promoKinds;
export const isPromoKind = (v: string): v is PromoKind => Object.hasOwn(promoKinds, v);

export type Promotion = { id: string; name: string; kind: string; value: number; min_qty: number | null; starts_on: string | null; ends_on: string | null; active: boolean; product_ids: string[] | null };
export type Coupon = { id: string; code: string; kind: string; value: number; max_uses: number | null; uses: number; expires_on: string | null; active: boolean };
export type LoyaltyRow = { client_id: string; client_name: string; phone: string | null; points: number };

/** «15 % menos», «S/ 2.00 menos», «llevando 3 o más, 10 % menos». */
export function discountLabel(kind: string, value: number, minQty: number | null, money: (v: number) => string): string {
  if (kind === "monto") return `${money(value)} menos`;
  const pct = `${Number.isInteger(value) ? value : value.toFixed(1)} % menos`;
  return kind === "volumen" ? `llevando ${minQty ?? 2} o más, ${pct}` : pct;
}

/** Where a promotion stands today (Lima date): running, scheduled, finished or paused. */
export function promoState(p: Pick<Promotion, "active" | "starts_on" | "ends_on">, today: string): "activa" | "programada" | "terminada" | "pausada" {
  if (!p.active) return "pausada";
  if (p.ends_on && p.ends_on < today) return "terminada";
  if (p.starts_on && p.starts_on > today) return "programada";
  return "activa";
}

export function couponState(c: Pick<Coupon, "active" | "expires_on" | "max_uses" | "uses">, today: string): "vigente" | "agotado" | "vencido" | "pausado" {
  if (!c.active) return "pausado";
  if (c.expires_on && c.expires_on < today) return "vencido";
  if (c.max_uses != null && c.uses >= c.max_uses) return "agotado";
  return "vigente";
}

/** First problem with a promotion form, or null. Percentages up to 90 % (the mobile app's limit). */
export function promoProblem(o: { name: string; kind: string; value: number | null; minQty: number | null; startsOn: string; endsOn: string }): string | null {
  if (!o.name.trim()) return "Ponle un nombre a la promoción.";
  if (o.name.trim().length > 80) return "El nombre admite hasta 80 caracteres.";
  if (!isPromoKind(o.kind)) return "Elige el tipo de descuento.";
  if (o.value == null || !(o.value > 0)) return "Escribe el descuento.";
  if (o.kind !== "monto" && o.value > 90) return "El descuento no puede pasar de 90 %.";
  if (o.kind === "volumen" && (o.minQty == null || o.minQty < 2)) return "Indica desde cuántas unidades aplica (2 o más).";
  if (o.startsOn && o.endsOn && o.endsOn < o.startsOn) return "La fecha final es anterior a la de inicio.";
  return null;
}

export function couponProblem(o: { code: string; kind: string; value: number | null; maxUses: number | null }): string | null {
  const code = o.code.trim();
  if (!/^[A-Za-z0-9-]{3,20}$/.test(code)) return "El código lleva de 3 a 20 letras, números o guiones.";
  if (o.kind !== "porcentaje" && o.kind !== "monto") return "Elige si el cupón descuenta un % o un monto.";
  if (o.value == null || !(o.value > 0)) return "Escribe el descuento del cupón.";
  if (o.kind === "porcentaje" && o.value > 90) return "El descuento no puede pasar de 90 %.";
  if (o.maxUses != null && (!Number.isInteger(o.maxUses) || o.maxUses < 1)) return "Los usos máximos deben ser un número entero desde 1.";
  return null;
}
