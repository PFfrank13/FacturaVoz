import { beforeEach, expect, it, vi } from "vitest";
const mock = vi.hoisted(() => ({ context: vi.fn(), update: vi.fn(), eq: vi.fn(), select: vi.fn(), single: vi.fn(), upload: vi.fn(), remove: vi.fn() }));
vi.mock("@/lib/erp/context", () => ({ workspaceContext: mock.context }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
import { updateProduct, uploadProductPhoto } from "../src/app/erp/actions";

const previous = { ok: false, message: "" };
const PRODUCT = "11111111-2222-4333-8444-555555555555";
const license = { enforced: true, source: "hub", mode: "full", features: { facturar: true } };
const chain = { eq: mock.eq, select: mock.select, maybeSingle: mock.single };
function context(access: Record<string, unknown> = { is_admin: true }, features = license.features) {
  return {
    db: { from: () => ({ update: mock.update }), storage: { from: () => ({ upload: mock.upload, remove: mock.remove }) } },
    user: { id: "verified-user" }, sector: "bodega", access, license: { ...license, features },
  };
}
const form = (fields: Record<string, string | File>) => { const f = new FormData(); for (const [k, v] of Object.entries(fields)) f.set(k, v); return f; };

beforeEach(() => {
  vi.clearAllMocks();
  mock.update.mockReturnValue(chain);
  mock.eq.mockReturnValue(chain);
  mock.select.mockReturnValue(chain);
  mock.single.mockResolvedValue({ data: { id: PRODUCT }, error: null });
  mock.upload.mockResolvedValue({ error: null });
  mock.context.mockResolvedValue(context());
});

it("updates only the verified company's product with validated fields", async () => {
  const r = await updateProduct("verified-org", PRODUCT, previous, form({ name: "Leche fresca", unit_price: "5.20", category: "Lácteos", reorder_point: "6", active: "on", org_id: "forged", image_path: "forged" }));
  expect(r.ok).toBe(true);
  expect(mock.update).toHaveBeenCalledWith({ name: "Leche fresca", unit_price: 5.2, category: "Lácteos", reorder_point: 6, active: true });
  expect(mock.eq).toHaveBeenCalledWith("org_id", "verified-org");
  expect(mock.eq).toHaveBeenCalledWith("id", PRODUCT);
});

it("updates the cost when sent and leaves it alone when the form omits it", async () => {
  await updateProduct("org", PRODUCT, previous, form({ name: "Arroz", unit_price: "5.2", category: "", reorder_point: "", unit_cost: "4.1", active: "on" }));
  expect(mock.update).toHaveBeenLastCalledWith(expect.objectContaining({ unit_cost: 4.1 }));
  await updateProduct("org", PRODUCT, previous, form({ name: "Arroz", unit_price: "5.2", category: "", reorder_point: "", active: "on" }));
  expect(mock.update.mock.lastCall![0]).not.toHaveProperty("unit_cost");
});

it("an unchecked box archives the product and an empty minimum clears it", async () => {
  await updateProduct("org", PRODUCT, previous, form({ name: "Pan", unit_price: "1", category: "", reorder_point: "" }));
  expect(mock.update).toHaveBeenCalledWith({ name: "Pan", unit_price: 1, category: null, reorder_point: null, active: false });
});

it("viewing the catalog does not allow editing it", async () => {
  mock.context.mockResolvedValue(context({ can: { sell: true, products_edit: false } }));
  expect((await updateProduct("org", PRODUCT, previous, form({ name: "X", unit_price: "1", category: "", reorder_point: "" }))).ok).toBe(false);
  expect(mock.update).not.toHaveBeenCalled();
});

it("does not write after Hub turns the catalog off", async () => {
  mock.context.mockResolvedValue(context({ is_admin: true }, { facturar: false }));
  expect((await updateProduct("org", PRODUCT, previous, form({ name: "X", unit_price: "1", category: "", reorder_point: "" }))).ok).toBe(false);
  expect(mock.update).not.toHaveBeenCalled();
});

it("rejects malformed ids and values before any write", async () => {
  expect((await updateProduct("org", "not-a-uuid", previous, form({ name: "X", unit_price: "1" }))).ok).toBe(false);
  expect(mock.context).not.toHaveBeenCalled();
  expect((await updateProduct("org", PRODUCT, previous, form({ name: "", unit_price: "-3", category: "", reorder_point: "" }))).ok).toBe(false);
  expect(mock.update).not.toHaveBeenCalled();
});

it("reports a product outside the company instead of claiming success", async () => {
  mock.single.mockResolvedValue({ data: null, error: null });
  expect((await updateProduct("org", PRODUCT, previous, form({ name: "X", unit_price: "1", category: "", reorder_point: "" }))).ok).toBe(false);
});

it("uploads photos to the company's folder, as the mobile app does, then links them", async () => {
  const photo = new File([new Uint8Array([1, 2, 3])], "leche.webp", { type: "image/webp" });
  expect((await uploadProductPhoto("verified-org", PRODUCT, previous, form({ photo }))).ok).toBe(true);
  const [path] = mock.upload.mock.calls[0];
  expect(path).toMatch(/^verified-org\/productos\/\d+_3\.webp$/);
  expect(mock.update).toHaveBeenCalledWith({ image_path: path });
});

it("refuses other file types and oversized photos without uploading", async () => {
  const pdf = new File([new Uint8Array([1])], "x.pdf", { type: "application/pdf" });
  expect((await uploadProductPhoto("org", PRODUCT, previous, form({ photo: pdf }))).ok).toBe(false);
  const huge = new File([new Uint8Array(5 * 1024 * 1024 + 1)], "x.jpg", { type: "image/jpeg" });
  expect((await uploadProductPhoto("org", PRODUCT, previous, form({ photo: huge }))).ok).toBe(false);
  expect(mock.upload).not.toHaveBeenCalled();
});

it("removes the uploaded file if it cannot be linked to the product", async () => {
  mock.single.mockResolvedValue({ data: null, error: { message: "denied" } });
  const photo = new File([new Uint8Array([1])], "x.png", { type: "image/png" });
  expect((await uploadProductPhoto("org", PRODUCT, previous, form({ photo }))).ok).toBe(false);
  expect(mock.remove).toHaveBeenCalledWith([mock.upload.mock.calls[0][0]]);
});
