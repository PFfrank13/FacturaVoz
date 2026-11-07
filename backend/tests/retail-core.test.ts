import { expect, it } from "vitest";
import { cents, scaled, ticketTotals } from "../src/lib/retail/money";
import { TicketStore, type TicketContent } from "../src/lib/retail/ticket-store";

it("decimal conversion and per-line half-up tax stay exact", () => {
  expect(cents("0.29")).toBe(29);
  expect(cents("12,50")).toBe(1250);
  expect(scaled("0.125", 3)).toBe(125);
  expect(ticketTotals([{ unitPriceCents: 29, quantityMilli: 3000 }], 1800)).toEqual({ subtotal: 87, tax: 16, total: 103 });
  expect(ticketTotals([{ unitPriceCents: 199, quantityMilli: 500 }], 0).total).toBe(100);
  for (const value of ["NaN", "Infinity", "-1", "1.001", "1e3"]) expect(() => cents(value)).toThrow();
});
const item = { id: "11111111-1111-4111-8111-111111111111", name: "Arroz QA", unitPriceCents: 250, quantityMilli: 2000 };
const ticket: TicketContent = { currency: "PEN", taxBasisPoints: 1800, operationId: null, method: "efectivo", lines: [item] };
function memory() { const data = new Map<string, string>(); return { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => { data.set(k, v); } }; }
it("recovers a versioned draft and pending operation after recreating the store", () => {
  const storage = memory(); const store = new TicketStore(storage, "org-a", "user-a");
  store.save({ ...ticket, operationId: item.id }, 0);
  expect(new TicketStore(storage, "org-a", "user-a").read()).toMatchObject({ version: 1, revision: 1, operationId: item.id, lines: [item] });
  expect(new TicketStore(storage, "org-b", "user-a").read()).toBeNull();
  expect(new TicketStore(storage, "org-a", "user-b").read()).toBeNull();
});
it("conflicting tabs cannot silently overwrite the most recent draft", () => {
  const storage = memory(); const a = new TicketStore(storage, "org", "user"); const b = new TicketStore(storage, "org", "user");
  a.save(ticket, 0);
  expect(() => b.save({ ...ticket, lines: [] }, 0)).toThrow("otra pestaña");
  expect(a.read()?.lines).toEqual([item]);
});
it("unsupported versions remain untouched rather than being reset", () => {
  const storage = memory(); const store = new TicketStore(storage, "org", "user");
  storage.setItem(store.key, '{"version":2}');
  expect(() => store.save(ticket, 0)).toThrow();
  expect(storage.getItem(store.key)).toBe('{"version":2}');
});
it("storage failure never reports a successful local save", () => {
  const store = new TicketStore({ getItem: () => null, setItem: () => { throw new Error("quota"); } }, "org", "user");
  expect(() => store.save(ticket, 0)).toThrow("quota");
});
