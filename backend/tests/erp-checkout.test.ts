import { beforeEach, expect, it, vi } from "vitest";
const m = vi.hoisted(() => ({ context: vi.fn(), from: vi.fn(), rpc: vi.fn(), products: vi.fn(), previous: vi.fn(), eq: vi.fn() }));
vi.mock("@/lib/erp/context", () => ({ workspaceContext: m.context }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
import { checkout } from "../src/app/erp/checkout";
const id = "11111111-1111-4111-8111-111111111111";
const input = { currency: "PEN", taxBasisPoints: 1800, requestId: id, method: "efectivo", items: [{ product_id: id, quantity: 2, unit_price: 10 }] };
beforeEach(() => {
  vi.clearAllMocks();
  const query = { select: vi.fn().mockReturnThis(), eq: m.eq, in: m.products, maybeSingle: m.previous };
  m.eq.mockReturnValue(query); m.from.mockReturnValue(query);
  m.previous.mockResolvedValue({ data: null });
  m.products.mockResolvedValue({ data: [{ id, name: "Arroz QA", unit_price: 10 }] });
  m.rpc.mockResolvedValue({ data: [{ invoice_id: id, charged: 23.6 }] });
  m.context.mockResolvedValue({ db: { from: m.from, rpc: m.rpc }, user: { id: "verified-user" },
    license: { enforced: true, source: "hub", mode: "full", features: { facturar: true, stock: false } },
    access: { can: { sell: true, collect: true } }, organization: { currency: "PEN", default_tax_rate: 18 } });
});
it("catalog without stock invokes one atomic checkout with trusted company and prices", async () => {
  expect((await checkout("verified-org", input)).ok).toBe(true);
  expect(m.eq).toHaveBeenCalledWith("org_id", "verified-org");
  expect(m.rpc).toHaveBeenCalledExactlyOnceWith("fast_checkout_atomic", expect.objectContaining({
    p_org_id: "verified-org", p_request_id: id, p_currency: "PEN",
    p_items: [{ ...input.items[0], description: "Arroz QA" }],
  }));
});
it("rejects forged price before invoking a transaction", async () => {
  expect((await checkout("org", { ...input, items: [{ ...input.items[0], unit_price: 1 }] })).ok).toBe(false);
  expect(m.rpc).not.toHaveBeenCalled();
});
it("rejects another company's or unavailable product", async () => {
  m.products.mockResolvedValue({ data: [] });
  expect((await checkout("org", input)).ok).toBe(false);
  expect(m.rpc).not.toHaveBeenCalled();
});
it("preserves uncertainty after an RPC error", async () => {
  m.rpc.mockResolvedValue({ error: { message: "timeout" } });
  expect(await checkout("org", input)).toMatchObject({ ok: false, uncertain: true });
});
it("recovers committed receipt even after a product price changes", async () => {
  m.previous.mockResolvedValue({ data: { invoice_id: id } });
  expect((await checkout("org", input)).ok).toBe(true);
  expect(m.products).not.toHaveBeenCalled();
});
it("revocation blocks checkout before catalog or transaction access", async () => {
  const context = await m.context(); context.license.features.facturar = false;
  expect((await checkout("org", input)).ok).toBe(false);
  expect(m.from).not.toHaveBeenCalled(); expect(m.rpc).not.toHaveBeenCalled();
});

it("changed tax is rejected before charging a stale ticket", async () => {
  expect((await checkout("org", { ...input, taxBasisPoints: 0 })).ok).toBe(false);
  expect(m.rpc).not.toHaveBeenCalled();
});
