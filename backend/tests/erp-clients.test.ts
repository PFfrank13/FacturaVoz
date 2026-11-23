import { describe, expect, it } from "vitest";
import { docLabel, docTypeOf, matchesClient, mergeClients, summarizeClients, waPhone, type ClientRow } from "../src/lib/erp/clients";

const row = (over: Partial<ClientRow> = {}): ClientRow => ({
  id: "c1", name: "Rosa Quispe", tax_id: "45871236", doc_type: "1", email: null, phone: "987 654 321",
  address: null, district: null, notes: null, credit_limit: 50, created_at: "2026-01-01", ...over,
});

describe("clients", () => {
  it("infers the SUNAT document type from the number", () => {
    expect(docTypeOf("45871236")).toBe("1");
    expect(docTypeOf("20100047218")).toBe("6");
    expect(docTypeOf("CE-123")).toBeNull();
    expect(docLabel({ tax_id: "20100047218", doc_type: null })).toBe("RUC");
    expect(waPhone("987 654 321")).toBe("51987654321");
    expect(waPhone("01 4567890")).toBe("");
  });

  it("joins fiado balance by id and purchases by name, flagging overdue and over-limit debt", () => {
    const [c] = mergeClients(
      [row()],
      [{ client_id: "c1", balance: "62.40", charges: 62.4, payments: 0, last_move: null, oldest_due: "2026-11-20", credit_limit: 50 }],
      [{ client_key: "rosa quispe", purchases: 6, total: "180", first_purchase: "2026-09-01", last_purchase: "2026-10-01", avg_gap: 6, days_since: 53 }],
      "2026-11-23",
    );
    expect(c.balance).toBe(62.4);
    expect(c.overLimit).toBe(true);
    expect(c.overdue).toBe(true);
    expect(c.purchases).toBe(6);
    expect(matchesClient(c, "", "sin_volver")).toBe(true);
    expect(matchesClient(c, "4587")).toBe(true);
    expect(summarizeClients([c])).toEqual({ count: 1, receivable: 62.4, debtors: 1, attention: 1 });
  });

  it("a paid-off client is not overdue and has no limit problem", () => {
    const [c] = mergeClients([row({ credit_limit: null })], [{ client_id: "c1", balance: 0, charges: 10, payments: 10, last_move: null, oldest_due: "2026-01-01", credit_limit: null }], [], "2026-11-23");
    expect(c.overdue).toBe(false);
    expect(c.overLimit).toBe(false);
    expect(c.limit).toBeNull();
    expect(matchesClient(c, "", "con_deuda")).toBe(false);
  });
});
