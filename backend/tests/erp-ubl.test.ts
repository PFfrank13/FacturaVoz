import { describe, expect, it } from "vitest";
import { matchProduct, parseUblInvoice } from "@/lib/erp/ubl";

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:cac" xmlns:cbc="urn:cbc" xmlns:ext="urn:ext">
  <ext:UBLExtensions><ext:UBLExtension><ext:ExtensionContent><ds:Signature Id="SignSUNAT"><cbc:ID>x</cbc:ID></ds:Signature></ext:ExtensionContent></ext:UBLExtension></ext:UBLExtensions>
  <cbc:UBLVersionID>2.1</cbc:UBLVersionID><cbc:CustomizationID>2.0</cbc:CustomizationID>
  <cbc:ID>F001-00012345</cbc:ID><cbc:IssueDate>2026-11-20</cbc:IssueDate><cbc:DocumentCurrencyCode>PEN</cbc:DocumentCurrencyCode>
  <cac:AccountingSupplierParty><cac:Party><cac:PartyIdentification><cbc:ID schemeID="6">20100055237</cbc:ID></cac:PartyIdentification>
    <cac:PartyLegalEntity><cbc:RegistrationName><![CDATA[ALICORP S.A.A.]]></cbc:RegistrationName></cac:PartyLegalEntity></cac:Party></cac:AccountingSupplierParty>
  <cac:AllowanceCharge><cbc:ChargeIndicator>true</cbc:ChargeIndicator><cbc:AllowanceChargeReasonCode>51</cbc:AllowanceChargeReasonCode><cbc:Amount currencyID="PEN">2.36</cbc:Amount></cac:AllowanceCharge>
  <cac:LegalMonetaryTotal><cbc:PayableAmount currencyID="PEN">118.00</cbc:PayableAmount></cac:LegalMonetaryTotal>
  <cac:InvoiceLine><cbc:ID>1</cbc:ID><cbc:InvoicedQuantity unitCode="NIU">12</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="PEN">60.00</cbc:LineExtensionAmount>
    <cac:Item><cbc:Description><![CDATA[ACEITE PRIMOR CLASICO 1 L]]></cbc:Description></cac:Item><cac:Price><cbc:PriceAmount currencyID="PEN">5.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
  <cac:InvoiceLine><cbc:ID>2</cbc:ID><cbc:InvoicedQuantity unitCode="KGM">10</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="PEN">40.00</cbc:LineExtensionAmount>
    <cac:Item><cbc:Description>Azúcar rubia granel</cbc:Description></cac:Item><cac:Price><cbc:PriceAmount currencyID="PEN">0</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
</Invoice>`;

describe("compra desde el XML del proveedor", () => {
  it("lee proveedor, número, percepción y líneas", () => {
    const inv = parseUblInvoice(xml)!;
    expect(inv).toMatchObject({ supplier: "ALICORP S.A.A.", ruc: "20100055237", reference: "F001-00012345", issueDate: "2026-11-20", total: 118, perception: 2.36 });
    expect(inv.lines).toEqual([
      { description: "ACEITE PRIMOR CLASICO 1 L", quantity: 12, unit_cost: 5, unit: "NIU" },
      { description: "Azúcar rubia granel", quantity: 10, unit_cost: 4, unit: "KGM" },
    ]);
  });
  it("rechaza archivos que no son factura", () => {
    expect(parseUblInvoice("<html></html>")).toBeNull();
  });
  it("empareja con el catálogo por nombre", () => {
    const products = [{ id: "a", name: "Aceite Primor 1 L" }, { id: "b", name: "Azúcar rubia" }, { id: "c", name: "Arroz extra" }];
    expect(matchProduct("ACEITE PRIMOR CLASICO 1 L", products)).toBe("a");
    expect(matchProduct("Azúcar rubia granel", products)).toBe("b");
    expect(matchProduct("Detergente Opal", products)).toBeNull();
  });
});
