"use client";
// Este módulo SOLO se importa vía next/dynamic con ssr:false (ver InvoiceDownload.tsx)
import { Document, Page, Text, View, StyleSheet, PDFDownloadLink } from "@react-pdf/renderer";
import { money, totals, type InvoiceInput } from "@/lib/schemas";

export type PdfData = InvoiceInput & { number: string; date: string };

const s = StyleSheet.create({
  page: { padding: 40, fontSize: 11, fontFamily: "Helvetica" },
  h1: { fontSize: 22, marginBottom: 4 },
  row: { flexDirection: "row", paddingVertical: 4, borderBottomWidth: 1, borderColor: "#ddd" },
  c1: { flex: 5 },
  c2: { flex: 1, textAlign: "right" },
  c3: { flex: 2, textAlign: "right" },
  c4: { flex: 2, textAlign: "right" },
  tot: { marginTop: 16, alignItems: "flex-end" },
});

function InvoiceDoc({ d }: { d: PdfData }) {
  const t = totals(d.items, d.tax_rate);
  return (
    <Document title={`Factura ${d.number}`}>
      <Page size="A4" style={s.page}>
        <Text style={s.h1}>Factura {d.number}</Text>
        <Text>Fecha: {d.date}</Text>
        <Text style={{ marginTop: 12, marginBottom: 20 }}>Cliente: {d.client_name}</Text>
        <View style={s.row}>
          <Text style={s.c1}>Concepto</Text>
          <Text style={s.c2}>Cant.</Text>
          <Text style={s.c3}>Precio</Text>
          <Text style={s.c4}>Importe</Text>
        </View>
        {d.items.map((i, k) => (
          <View key={k} style={s.row}>
            <Text style={s.c1}>{i.description}</Text>
            <Text style={s.c2}>{i.quantity}</Text>
            <Text style={s.c3}>{money(i.unit_price)}</Text>
            <Text style={s.c4}>{money(i.quantity * i.unit_price)}</Text>
          </View>
        ))}
        <View style={s.tot}>
          <Text>Base imponible: {money(t.subtotal)}</Text>
          <Text>IVA ({d.tax_rate}%): {money(t.tax)}</Text>
          <Text style={{ fontSize: 14, marginTop: 4 }}>Total: {money(t.total)}</Text>
        </View>
        {d.notes ? <Text style={{ marginTop: 24 }}>{d.notes}</Text> : null}
      </Page>
    </Document>
  );
}

export default function PDFButton({ data }: { data: PdfData }) {
  return (
    <PDFDownloadLink
      document={<InvoiceDoc d={data} />}
      fileName={`${data.number}.pdf`}
      className="inline-block rounded-lg bg-green-600 px-5 py-3 font-medium text-white"
    >
      {({ loading }) => (loading ? "Preparando PDF…" : "Descargar PDF")}
    </PDFDownloadLink>
  );
}
