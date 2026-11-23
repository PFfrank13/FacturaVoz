import { beforeEach, expect, it, vi } from "vitest";
const mock = vi.hoisted(() => ({ context: vi.fn(), from: vi.fn(), rpc: vi.fn(), maybeSingle: vi.fn() }));
vi.mock("@/lib/erp/context", () => ({ workspaceContext: mock.context }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/lookup", () => ({ lookupDocument: vi.fn() }));
vi.mock("@/lib/dayclose-core", () => ({ closeDay: vi.fn() }));
import { shareReceipt } from "../src/app/erp/actions";

const id = "7d0c3b1e-2f4a-4c8b-9a1d-3e5f6a7b8c9d";
const chain = { select: () => chain, eq: () => chain, maybeSingle: mock.maybeSingle };
const license = { enforced: true, source: "hub", mode: "full", features: { facturar: true } };
beforeEach(() => {
  vi.clearAllMocks();
  mock.from.mockReturnValue(chain);
  mock.maybeSingle.mockResolvedValue({ data: { id, client: { phone: "987654321", email: "rosa@correo.pe" } }, error: null });
  mock.rpc.mockResolvedValue({ data: "AbCdEfGhIjKlMnOpQrStUv", error: null });
  mock.context.mockResolvedValue({ db: { from: mock.from, rpc: mock.rpc }, user: { id: "u" }, sector: "bodega", access: { is_admin: true }, license, organization: { name: "Bodega Lucha" } });
});

it("returns the receipt's private link and the customer's contact", async () => {
  expect(await shareReceipt("org", id)).toEqual({ ok: true, path: "/comprobante/AbCdEfGhIjKlMnOpQrStUv", phone: "987654321", email: "rosa@correo.pe", business: "Bodega Lucha" });
  expect(mock.context).toHaveBeenCalledWith("org");
  expect(mock.rpc).toHaveBeenCalledWith("invoice_portal_link", { p_invoice: id });
});

it("rejects a malformed id before touching the database", async () => {
  expect((await shareReceipt("org", "x' or 1=1")).ok).toBe(false);
  expect(mock.context).not.toHaveBeenCalled();
});

it("does not create links when the module is no longer allowed", async () => {
  mock.context.mockResolvedValue({ db: { from: mock.from, rpc: mock.rpc }, sector: "bodega", access: { is_admin: true }, license: { ...license, features: { facturar: false } } });
  expect((await shareReceipt("org", id)).ok).toBe(false);
  expect(mock.rpc).not.toHaveBeenCalled();
});

it("does not create a link for a receipt outside the company (RLS returns nothing)", async () => {
  mock.maybeSingle.mockResolvedValue({ data: null, error: null });
  expect(await shareReceipt("org", id)).toEqual({ ok: false, message: "No encontramos ese comprobante." });
  expect(mock.rpc).not.toHaveBeenCalled();
});

it("reports a failed or unexpected token without leaking it", async () => {
  mock.rpc.mockResolvedValue({ data: "<script>", error: null });
  expect((await shareReceipt("org", id)).ok).toBe(false);
});
