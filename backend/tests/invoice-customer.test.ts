import { expect, it } from "vitest";
import { invoiceInputSchema } from "../src/lib/schemas";
const base = { client_name: "Cliente de prueba", tax_rate: 18,
  items: [{description:"Servicio", quantity:1, unit_price:10}] };
it("preserves the reviewed customer document without requiring it for legacy drafts", () => {
  expect(invoiceInputSchema.parse({...base,client_tax_id:" 12345678 "}).client_tax_id).toBe("12345678");
  expect(invoiceInputSchema.parse(base).client_tax_id).toBeUndefined();
  expect(invoiceInputSchema.safeParse({...base,client_tax_id:"1".repeat(31)}).success).toBe(false);
});
