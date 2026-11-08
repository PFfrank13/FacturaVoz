import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const route = readFileSync(
  join(__dirname, "../src/app/api/products/remove-bg/route.ts"), "utf8",
);
const client = readFileSync(
  join(__dirname, "../../app/lib/services/v2_api.dart"), "utf8",
);

describe("Product AI cutout security gates (static checks, not provider E2E)", () => {
  it("authenticates, validates company, role and active Hub license before the provider call", () => {
    expect(route).toContain("authenticateBearer(req)");
    expect(route).toContain("licenseAllows(auth.supabase, orgId, \"stock\")");
    expect(route).toContain('rpc("my_access", { p_org: orgId })');
    expect(route).toContain("access.data?.can?.products_edit !== true");
    expect(route.indexOf("licenseAllows(")).toBeLessThan(route.indexOf('fetch("https://api.remove.bg'));
  });

  it("is capped, checks bytes and never exposes provider credentials", () => {
    expect(route).toContain("MAX_INPUT_BYTES = 3_000_000");
    expect(route).toContain("MAX_OUTPUT_BYTES = 4_000_000");
    expect(route).toContain("sniffImage(bytes)");
    expect(route).toContain('rpc("consume_api_quota"');
    expect(route).toContain("process.env.REMOVE_BG_API_KEY");
    expect(route).toContain('sniffImage(new Uint8Array(processed)) !== "image/png"');
    expect(client).not.toContain("REMOVE_BG_API_KEY");
    expect(route).toContain("corsHeaders(origin)");
  });

  it("does not save or publish images without explicit confirmation in Flutter", () => {
    expect(route).not.toContain(".storage.from(");
    expect(client).toContain("removeProductBackground(");
  });
});
