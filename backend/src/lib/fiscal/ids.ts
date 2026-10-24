// Validación de documentos de identidad peruanos.
export function isValidRuc(ruc: string): boolean {
  if (!/^\d{11}$/.test(ruc)) return false;
  if (!["10", "15", "16", "17", "20"].includes(ruc.slice(0, 2))) return false;
  const w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const sum = w.reduce((s, x, i) => s + x * Number(ruc[i]), 0);
  const check = (11 - (sum % 11)) % 10;
  return check === Number(ruc[10]);
}

export const isValidDni = (d: string) => /^\d{8}$/.test(d);

export type ClientDocType = "6" | "1" | "4" | "7" | "0";

/** Devuelve el código del catálogo 06 de SUNAT y el número, o un error legible. */
export function validateClientDoc(
  docType: string,
  docNumber: string,
): { ok: true; tipoDoc: string; numDoc: string } | { ok: false; error: string } {
  const n = docNumber.trim().toUpperCase();
  switch (docType) {
    case "6":
      return isValidRuc(n) ? { ok: true, tipoDoc: "6", numDoc: n } : { ok: false, error: "RUC del cliente no válido" };
    case "1":
      return isValidDni(n) ? { ok: true, tipoDoc: "1", numDoc: n } : { ok: false, error: "DNI del cliente no válido (8 dígitos)" };
    case "4":
      return /^[A-Z0-9]{1,12}$/.test(n) ? { ok: true, tipoDoc: "4", numDoc: n } : { ok: false, error: "Carnet de extranjería no válido" };
    case "7":
      return /^[A-Z0-9]{1,12}$/.test(n) ? { ok: true, tipoDoc: "7", numDoc: n } : { ok: false, error: "Pasaporte no válido" };
    case "0":
      return { ok: true, tipoDoc: "-", numDoc: "-" };
    default:
      return { ok: false, error: "Tipo de documento del cliente no válido" };
  }
}
