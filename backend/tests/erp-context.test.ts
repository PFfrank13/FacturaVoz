import { beforeEach, expect, it, vi } from "vitest";
const mock = vi.hoisted(() => ({ db: { auth: { getUser: vi.fn() }, from: vi.fn(), rpc: vi.fn() } }));
vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/server", () => ({ createClient: async () => mock.db }));
vi.mock("next/navigation", () => ({ notFound: () => { throw new Error("NOT_FOUND"); }, redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); } }));
import { workspaceContext } from "../src/lib/erp/context";
beforeEach(() => vi.clearAllMocks());
it("rejects malformed organization identifiers before reading data", async () => {
  await expect(workspaceContext("anything")).rejects.toThrow("NOT_FOUND");
  expect(mock.db.from).not.toHaveBeenCalled();
});
it("requires a validated user, not just a cookie", async () => {
  mock.db.auth.getUser.mockResolvedValue({ data: { user: null } });
  await expect(workspaceContext("00000000-0000-4000-8000-000000000001")).rejects.toThrow("REDIRECT:/login");
  expect(mock.db.from).not.toHaveBeenCalled();
});
it("checks membership against the authenticated user and rejects another organization", async () => {
  const org = "00000000-0000-4000-8000-000000000002";
  mock.db.auth.getUser.mockResolvedValue({ data: { user: { id: "actual-user" } } });
  const query = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn(async () => ({ data: null, error: null })) };
  query.select.mockReturnValue(query); query.eq.mockReturnValue(query); mock.db.from.mockReturnValue(query);
  await expect(workspaceContext(org)).rejects.toThrow("NOT_FOUND");
  expect(query.eq).toHaveBeenCalledWith("org_id", org);
  expect(query.eq).toHaveBeenCalledWith("user_id", "actual-user");
  // The license/access RPCs now run in parallel with the membership check (one round trip); they verify
  // membership themselves and raise for outsiders, and the page still answers NOT_FOUND before using anything.
});
