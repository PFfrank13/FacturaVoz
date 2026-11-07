/** Decimal strings at boundaries; all business arithmetic is integer (half-up). */
export function scaled(value: string | number, digits: number): number {
  const text = String(value).trim().replace(",", ".");
  const match = /^(\d+)(?:\.(\d+))?$/.exec(text);
  if (!match || (match[2]?.length ?? 0) > digits) throw new Error("Importe o cantidad no válida");
  const result = BigInt(match[1]) * BigInt(10) ** BigInt(digits) + BigInt((match[2] ?? "").padEnd(digits, "0"));
  if (result > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Importe fuera de rango");
  return Number(result);
}
export const cents = (value: string | number) => scaled(value, 2);
function rounded(numerator: bigint, denominator: bigint): number {
  const result = (numerator + denominator / BigInt(2)) / denominator;
  if (result > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("Importe fuera de rango");
  return Number(result);
}
export function ticketTotals(lines: Array<{ unitPriceCents: number; quantityMilli: number }>, taxBasisPoints: number) {
  let subtotal = 0, tax = 0;
  for (const line of lines) {
    for (const n of [line.unitPriceCents, line.quantityMilli, taxBasisPoints])
      if (!Number.isSafeInteger(n) || n < 0) throw new Error("Valor monetario no válido");
    const amount = rounded(BigInt(line.unitPriceCents) * BigInt(line.quantityMilli), BigInt(1000));
    subtotal += amount;
    tax += rounded(BigInt(amount) * BigInt(taxBasisPoints), BigInt(10000));
  }
  if (!Number.isSafeInteger(subtotal + tax)) throw new Error("Total fuera de rango");
  return { subtotal, tax, total: subtotal + tax };
}
