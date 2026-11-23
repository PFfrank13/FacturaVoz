import { beforeEach, expect, it, vi } from "vitest";
const mock = vi.hoisted(() => ({ context: vi.fn(), insert: vi.fn(), from: vi.fn() }));
vi.mock("@/lib/erp/context", () => ({ workspaceContext: mock.context }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/lookup", () => ({ lookupDocument: vi.fn() }));
import { createRecord } from "../src/app/erp/actions";
const previous = { ok: false, message: "" };
beforeEach(() => {
  vi.clearAllMocks();
  mock.from.mockReturnValue({ insert: mock.insert });
  mock.insert.mockResolvedValue({ error: null });
  mock.context.mockResolvedValue({ db: { from: mock.from }, user: { id: "verified-user" }, sector: "bodega", access: { is_admin: true }, license: { enforced: true, source: "hub", mode: "full", features: { clientes: true, facturar: true } } });
});
it("uses the verified user and explicit workspace, ignoring forged form tenant/user fields", async () => {
  const form = new FormData();
  for (const [key, value] of Object.entries({ name: "Synthetic contact", email: "", phone: "", tax_id: "", org_id: "forged", user_id: "forged" })) form.set(key, value);
  expect((await createRecord("verified-org", "clientes", previous, form)).ok).toBe(true);
  expect(mock.context).toHaveBeenCalledWith("verified-org");
  expect(mock.insert).toHaveBeenCalledWith(expect.objectContaining({ org_id: "verified-org", user_id: "verified-user" }));
});
it("does not write after Hub revokes a previously open module", async () => {
  mock.context.mockResolvedValue({ db: { from: mock.from }, sector: "bodega", access: { is_admin: true }, license: { enforced: true, source: "hub", mode: "full", features: { clientes: false } } });
  expect((await createRecord("org", "clientes", previous, new FormData())).ok).toBe(false);
  expect(mock.from).not.toHaveBeenCalled();
});
it("viewing a catalog does not imply permission to edit it", async () => {
  mock.context.mockResolvedValue({ db: { from: mock.from }, sector: "bodega", access: { can: { sell: true, products_edit: false } }, license: { enforced: true, source: "hub", mode: "full", features: { facturar: true } } });
  expect((await createRecord("org", "productos", previous, new FormData())).ok).toBe(false);
  expect(mock.insert).not.toHaveBeenCalled();
});
it("rejects malformed fields before any insert", async () => {
  const form = new FormData(); form.set("name", ""); form.set("email", "not-an-email");
  expect((await createRecord("org", "clientes", previous, form)).ok).toBe(false);
  expect(mock.insert).not.toHaveBeenCalled();
});
