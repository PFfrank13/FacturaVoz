import { amountLegend } from "./words";
import { calc, type Afectacion, type Line } from "./calc";

export type Issuer = {
  ruc: string;
  razonSocial: string;
  nombreComercial?: string | null;
  ubigeo: string;
  departamento: string;
  provincia: string;
  distrito: string;
  direccion: string;
};

export type BuildInput = {
  docType: "01" | "03";
  currency: "PEN" | "USD";
  afectacion: Afectacion;
  taxRate: number;
  unit: "NIU" | "ZZ";
  issuer: Issuer;
  client: { tipoDoc: string; numDoc: string; name: string; address?: string | null };
  lines: Line[];
  now?: Date;
};

/** Fecha/hora en Lima (UTC-5, sin horario de verano) con el formato que espera Greenter. */
export function limaIso(d: Date): string {
  const l = new Date(d.getTime() - 5 * 3600_000);
  return l.toISOString().slice(0, 19) + "-05:00";
}

export function validateFiscalInput(i: BuildInput): string | null {
  const iss = i.issuer;
  if (!/^\d{6}$/.test(iss.ubigeo)) return "Falta el ubigeo (6 dígitos) del domicilio fiscal";
  if (!iss.departamento || !iss.provincia || !iss.distrito || !iss.direccion) return "Completa la dirección fiscal del negocio";
  if (!iss.razonSocial.trim()) return "Falta la razón social";
  if (i.afectacion === "gravado" && i.taxRate !== 18) return "Para operaciones gravadas el IGV debe ser 18%";
  if (i.afectacion !== "gravado" && i.taxRate !== 0) return "Operaciones exoneradas o inafectas deben tener impuesto 0%";
  if (i.lines.length < 1 || i.lines.length > 50) return "La factura debe tener entre 1 y 50 líneas";
  if (i.docType === "01" && i.client.tipoDoc !== "6") return "La factura requiere el RUC del cliente";
  const c = calc(i.lines, i.afectacion, i.taxRate);
  if (c.lines.some((l) => l.quantity <= 0 || l.valorUnitario < 0 || !l.description)) return "Hay líneas con datos no válidos";
  if (c.total <= 0) return "El total debe ser mayor que cero";
  // Boleta: identificar al comprador desde S/ 700 (o siempre en USD)
  if (i.docType === "03" && i.client.tipoDoc === "-" && (i.currency === "USD" || c.total >= 700))
    return "Para boletas desde S/ 700 debes identificar al cliente (DNI u otro documento)";
  if (i.client.name.trim().length === 0) return "Falta el nombre del cliente";
  return null;
}

/** Construye el JSON de Lycet/Greenter (sin serie ni correlativo: los asigna la base de datos). */
export function buildInvoicePayload(i: BuildInput) {
  const c = calc(i.lines, i.afectacion, i.taxRate);
  const tipAfe = { gravado: "10", exonerado: "20", inafecto: "30" }[i.afectacion];
  const address = {
    ubigueo: i.issuer.ubigeo,
    codigoPais: "PE",
    departamento: i.issuer.departamento,
    provincia: i.issuer.provincia,
    distrito: i.issuer.distrito,
    urbanizacion: "-",
    direccion: i.issuer.direccion,
  };
  const totals = {
    gravadas: i.afectacion === "gravado" ? c.base : 0,
    exoneradas: i.afectacion === "exonerado" ? c.base : 0,
    inafectas: i.afectacion === "inafecto" ? c.base : 0,
    igv: c.igv,
    total: c.total,
  };
  const legend = amountLegend(c.total, i.currency);

  const payload: Record<string, unknown> = {
    ublVersion: "2.1",
    tipoOperacion: "0101",
    tipoDoc: i.docType,
    serie: "PENDIENTE",
    correlativo: "0",
    fechaEmision: limaIso(i.now ?? new Date()),
    formaPago: { tipo: "Contado" },
    tipoMoneda: i.currency,
    company: {
      ruc: i.issuer.ruc,
      razonSocial: i.issuer.razonSocial.trim(),
      nombreComercial: (i.issuer.nombreComercial || i.issuer.razonSocial).trim(),
      address,
    },
    client: {
      tipoDoc: i.client.tipoDoc,
      numDoc: i.client.numDoc,
      rznSocial: i.client.tipoDoc === "-" ? "CLIENTES VARIOS" : i.client.name.trim(),
      ...(i.client.address ? { address: { ubigueo: "-", codigoPais: "PE", departamento: "-", provincia: "-", distrito: "-", direccion: i.client.address } } : {}),
    },
    mtoOperGravadas: totals.gravadas,
    mtoOperExoneradas: totals.exoneradas,
    mtoOperInafectas: totals.inafectas,
    mtoIGV: totals.igv,
    totalImpuestos: totals.igv,
    valorVenta: c.base,
    subTotal: c.total,
    mtoImpVenta: c.total,
    details: c.lines.map((l, k) => ({
      unidad: i.unit,
      cantidad: l.quantity,
      codProducto: String(k + 1).padStart(3, "0"),
      descripcion: l.description,
      mtoValorUnitario: l.valorUnitario,
      mtoValorVenta: l.base,
      mtoBaseIgv: l.base,
      porcentajeIgv: i.afectacion === "gravado" ? i.taxRate : 0,
      igv: l.igv,
      tipAfeIgv: tipAfe,
      totalImpuestos: l.igv,
      mtoPrecioUnitario: l.precioUnitario,
    })),
    legends: [{ code: "1000", value: legend }],
  };
  // Los campos de operaciones que no aplican se omiten (Greenter los trata como no informados)
  for (const k of ["mtoOperGravadas", "mtoOperExoneradas", "mtoOperInafectas"]) {
    if (payload[k] === 0) delete payload[k];
  }
  return { payload, totals, legend };
}
