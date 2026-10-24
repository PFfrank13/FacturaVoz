import { limaIso } from "./payload";

export type NoteReason = "01" | "06";

export const NOTE_REASONS: Record<NoteReason, string> = {
  "01": "ANULACION DE LA OPERACION",
  "06": "DEVOLUCION TOTAL",
};

type Json = Record<string, unknown>;

/** Serie de la nota: F001 -> FC01, B001 -> BC01 (la primera letra debe coincidir con el comprobante afectado). */
export function noteSeriesFor(originalSeries: string): string {
  return `${originalSeries[0]}C${originalSeries.slice(-2)}`;
}

/** Texto del motivo: solo caracteres seguros, máximo 250. */
export function cleanReasonText(code: NoteReason, text: unknown): string {
  const t = typeof text === "string" ? text.replace(/[^\p{L}\p{N} .,;:()\-/]/gu, "").replace(/\s+/g, " ").trim().slice(0, 250) : "";
  return t || NOTE_REASONS[code];
}

/**
 * Nota de crédito TOTAL: reutiliza exactamente los importes y líneas que se enviaron (y SUNAT aceptó)
 * en el comprobante original, así que no puede diferir de él. La serie/correlativo los asigna la base de datos.
 */
export function buildNotePayload(orig: Json, reasonCode: NoteReason, reasonText: string, now: Date = new Date()) {
  const tipoDoc = String(orig.tipoDoc ?? "");
  if (tipoDoc !== "01" && tipoDoc !== "03") throw new Error("Comprobante original no válido");
  const pick = (k: string) => (orig[k] === undefined ? {} : { [k]: orig[k] });
  const payload: Json = {
    ublVersion: "2.1",
    tipoDoc: "07",
    serie: "PENDIENTE",
    correlativo: "0",
    fechaEmision: limaIso(now),
    tipDocAfectado: tipoDoc,
    numDocfectado: `${orig.serie}-${orig.correlativo}`,
    codMotivo: reasonCode,
    desMotivo: reasonText,
    tipoMoneda: orig.tipoMoneda,
    company: orig.company,
    client: orig.client,
    ...pick("mtoOperGravadas"),
    ...pick("mtoOperExoneradas"),
    ...pick("mtoOperInafectas"),
    mtoIGV: orig.mtoIGV,
    totalImpuestos: orig.totalImpuestos,
    valorVenta: orig.valorVenta,
    subTotal: orig.subTotal,
    mtoImpVenta: orig.mtoImpVenta,
    details: orig.details,
    legends: orig.legends,
  };
  const totals = {
    gravadas: Number(orig.mtoOperGravadas ?? 0),
    exoneradas: Number(orig.mtoOperExoneradas ?? 0),
    inafectas: Number(orig.mtoOperInafectas ?? 0),
    igv: Number(orig.mtoIGV ?? 0),
    total: Number(orig.mtoImpVenta ?? 0),
  };
  return { payload, totals };
}
