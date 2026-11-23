import { afterEach, expect, it, vi } from "vitest";

async function csp(url: string | undefined) {
  vi.resetModules();
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", url ?? "");
  const config = (await import("../next.config")).default;
  const rules = await config.headers!();
  const erp = rules.find(r => r.source.startsWith("/:path"))!;
  return erp.headers.find(h => h.key === "Content-Security-Policy")!.value;
}
afterEach(() => vi.unstubAllEnvs());

it("keeps the production policy unchanged for a *.supabase.co project", async () => {
  const policy = await csp("https://abcdefghij.supabase.co");
  expect(policy).toContain("connect-src 'self' https://*.supabase.co wss://*.supabase.co;");
  expect(policy).not.toContain("http://");
});

it("allows a custom or local Supabase origin and its realtime socket, nothing broader", async () => {
  const policy = await csp("http://127.0.0.1:55321");
  expect(policy).toContain("connect-src 'self' https://*.supabase.co wss://*.supabase.co http://127.0.0.1:55321 ws://127.0.0.1:55321");
  expect(policy).toContain("img-src 'self' data: blob: https://*.supabase.co http://127.0.0.1:55321;");
  const custom = await csp("https://db.mi-negocio.pe");
  expect(custom).toContain("https://db.mi-negocio.pe wss://db.mi-negocio.pe");
});

it("ignores a missing or malformed URL", async () => {
  expect(await csp(undefined)).toContain("connect-src 'self' https://*.supabase.co wss://*.supabase.co;");
  expect(await csp("not a url")).toContain("connect-src 'self' https://*.supabase.co wss://*.supabase.co;");
});
