// Importe en letras para la leyenda 1000 de SUNAT: "SON CIENTO VEINTITRÉS CON 45/100 SOLES"
const U = ["", "UN", "DOS", "TRES", "CUATRO", "CINCO", "SEIS", "SIETE", "OCHO", "NUEVE", "DIEZ", "ONCE", "DOCE",
  "TRECE", "CATORCE", "QUINCE", "DIECISÉIS", "DIECISIETE", "DIECIOCHO", "DIECINUEVE", "VEINTE", "VEINTIÚN",
  "VEINTIDÓS", "VEINTITRÉS", "VEINTICUATRO", "VEINTICINCO", "VEINTISÉIS", "VEINTISIETE", "VEINTIOCHO", "VEINTINUEVE"];
const T = ["", "", "", "TREINTA", "CUARENTA", "CINCUENTA", "SESENTA", "SETENTA", "OCHENTA", "NOVENTA"];
const C = ["", "CIENTO", "DOSCIENTOS", "TRESCIENTOS", "CUATROCIENTOS", "QUINIENTOS", "SEISCIENTOS", "SETECIENTOS",
  "OCHOCIENTOS", "NOVECIENTOS"];

function below100(n: number): string {
  if (n < 30) return U[n];
  const d = Math.floor(n / 10);
  const u = n % 10;
  return u === 0 ? T[d] : `${T[d]} Y ${u === 1 ? "UN" : U[u]}`;
}

function below1000(n: number): string {
  if (n === 100) return "CIEN";
  const c = Math.floor(n / 100);
  const r = n % 100;
  return [c ? C[c] : "", r ? below100(r) : ""].filter(Boolean).join(" ");
}

export function integerToWords(n: number): string {
  if (!Number.isInteger(n) || n < 0 || n > 999_999_999_999) throw new Error("Importe fuera de rango");
  if (n === 0) return "CERO";
  const millardos = Math.floor(n / 1_000_000_000);
  const millones = Math.floor((n % 1_000_000_000) / 1_000_000);
  const miles = Math.floor((n % 1_000_000) / 1000);
  const resto = n % 1000;
  const parts: string[] = [];
  if (millardos) parts.push(millardos === 1 ? "MIL" : `${below1000(millardos)} MIL`);
  if (millones || millardos) {
    // "MIL MILLONES" cuando solo hay millardos
    if (millones) parts.push(millones === 1 ? "UN MILLÓN" : `${below1000(millones)} MILLONES`);
    else parts.push("MILLONES");
  }
  if (miles) parts.push(miles === 1 ? "MIL" : `${below1000(miles)} MIL`);
  if (resto) parts.push(below1000(resto).replace(/VEINTIÚN$/, "VEINTIUNO").replace(/\bUN$/, "UNO"));
  return parts.join(" ");
}

export function amountLegend(total: number, currency: "PEN" | "USD"): string {
  const cents = Math.round(total * 100);
  const whole = Math.floor(cents / 100);
  const frac = String(cents % 100).padStart(2, "0");
  const name = currency === "PEN" ? "SOLES" : "DÓLARES AMERICANOS";
  return `SON ${integerToWords(whole)} CON ${frac}/100 ${name}`;
}
