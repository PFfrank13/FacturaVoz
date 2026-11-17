import { readFileSync } from "node:fs";
import { generateKeyPairSync, sign } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { safeNext } from "../src/lib/safe-next";
import { evaluatePreflight } from "../src/lib/license-preflight";

// ───────────── Enlace del Hub /solvex/ir/{org} y regreso tras iniciar sesión ─────────────
const nav = vi.hoisted(() => ({
  redirect: vi.fn((u: string) => { throw new Error(`REDIRECT:${u}`); }),
  notFound: vi.fn(() => { throw new Error("NOT_FOUND"); }),
}));
vi.mock("next/navigation", () => ({ redirect: nav.redirect, notFound: nav.notFound }));
import SolvexGo from "../src/app/solvex/ir/[org]/page";

describe("/solvex/ir/{org} (enlace 'Ir a FacturaVoz' del Hub, antes 404)", () => {
  beforeEach(() => vi.clearAllMocks());
  it("lleva al espacio de trabajo de esa empresa (la sesión y la pertenencia las exige /erp)", async () => {
    await expect(SolvexGo({ params: Promise.resolve({ org: "71C6841A-968A-4C21-ACB9-25114A507067" }) })).rejects.toThrow("REDIRECT:/erp/71c6841a-968a-4c21-acb9-25114a507067");
  });
  it("rechaza identificadores que no son una empresa", async () => {
    await expect(SolvexGo({ params: Promise.resolve({ org: "../../pagar" }) })).rejects.toThrow("NOT_FOUND");
    expect(nav.redirect).not.toHaveBeenCalled();
  });
});

describe("safeNext: sin redirecciones abiertas", () => {
  const org = "71c6841a-968a-4c21-acb9-25114a507067";
  it("acepta solo rutas internas de una empresa", () => {
    expect(safeNext(`/solvex/ir/${org}`)).toBe(`/solvex/ir/${org}`);
    expect(safeNext(`/erp/${org}`)).toBe(`/erp/${org}`);
    expect(safeNext(`/erp/${org}/inventario`)).toBe(`/erp/${org}/inventario`);
  });
  it("rechaza dominios externos, esquemas y rutas arbitrarias", () => {
    for (const bad of ["https://evil.com", "//evil.com", `/erp/${org}/../../admin`, "/pagar/abc", "/", "javascript:alert(1)", null, 42]) {
      expect(safeNext(bad)).toBeNull();
    }
  });
});

// ───────────── Sin licencias locales en el backend ─────────────
describe("v3.4: el Hub es la única fuente comercial", () => {
  const read = (p: string) => readFileSync(new URL(p, import.meta.url), "utf8");
  it("webhook y sincronización ya no saltan empresas 'local' y usan license_sync_apply", () => {
    for (const f of ["../src/app/api/solvex/webhook/route.ts", "../src/app/api/cron/solvex-sync/route.ts", "../src/app/api/license/refresh/route.ts"]) { // preflight solo lee
      const src = read(f);
      expect(src).not.toMatch(/source\s*===\s*"local"/);
      expect(src).toContain('"license_sync_apply"');
    }
  });
  it("el ERP web acepta local solo durante la transición (la FASE B lo elimina en la base)", () => {
    expect(read("../src/lib/erp/access.ts")).toContain("FASE B");
  });
  it("FASE A no cambia el acceso de nadie; FASE B es estricta y se niega si alguien quedaría bloqueado", () => {
    const a = read("../supabase/migrations/20261209_v34a_transicion_hub_sin_corte.sql");
    expect(a).not.toMatch(/function private\.org_mode/);
    expect(a).not.toMatch(/function private\.effective_features/);
    expect(a).not.toMatch(/function private\.license_enforced/);
    expect(a).not.toMatch(/^\s*update\s+public\.org_licenses/im);
    expect(a).toContain("pending_code_mismatch");
    const b = read("../supabase/migrations/20261210_v34b_licencias_solo_hub.sql");
    expect(b).toContain("FASE B detenida para no bloquear empresas");
    expect(b).toMatch(/private\.license_enforced\(\)\s*returns boolean language sql immutable set search_path = '' as \$\$ select true \$\$/);
    expect(b).toContain("check (source = 'hub')");
    expect(b).not.toMatch(/'local'\s*,\s*'dev'\)\s*then\s*return\s*'full'/);
  });
  it("las migraciones locales heredadas ya no modifican datos", () => {
    const a = read("../supabase/migrations/20261201_v32_local_dev_license_bodega.sql");
    const b = read("../supabase/migrations/20261202_v32_local_trial_banner_cleanup.sql");
    expect(a).not.toMatch(/^\s*update\s+public\.org_licenses/im);
    expect(a).not.toMatch(/^\s*insert\s+into\s+private\.standalone_license_backups/im);
    expect(b).not.toMatch(/^\s*update\s+public\.org_licenses/im);
  });
});

// ───────────── POST /api/license/refresh ─────────────
const hub = vi.hoisted(() => ({ licenses: [] as { tenant_ref: string; token: string }[] }));
const db = vi.hoisted(() => ({ rpc: vi.fn(), role: "owner" as string | null }));
vi.mock("@/lib/api-auth", () => ({
  preflight: vi.fn(),
  jsonWith: () => (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } }),
  readJson: async (req: Request) => JSON.parse(await req.text()),
  authenticateBearer: async (req: Request) => req.headers.get("authorization")
    ? { userId: "11111111-1111-4111-8111-111111111111", supabase: { rpc: async () => ({ data: db.role, error: null }) } }
    : null,
}));
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: () => ({ rpc: db.rpc }) }));

const { privateKey, publicKey } = generateKeyPairSync("ed25519");
const rawPub = publicKey.export({ format: "der", type: "spki" }).subarray(12).toString("base64");
const b64u = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
function token(payload: Record<string, unknown>) {
  const h = b64u({ alg: "EdDSA", typ: "slx-license+jwt" });
  const p = b64u(payload);
  return `${h}.${p}.${sign(null, Buffer.from(`${h}.${p}`), privateKey).toString("base64url")}`;
}
const ORG = "71c6841a-968a-4c21-acb9-25114a507067";
const INSTANCE = "ins_abcdefghij0123456789";
const now = Math.floor(Date.now() / 1000);

describe("POST /api/license/refresh", () => {
  beforeEach(() => {
    vi.resetModules();
    db.rpc.mockReset();
    db.role = "owner";
    process.env.SOLVEX_HUB_URL = "https://hub.example";
    process.env.SOLVEX_API_KEY = "slxk_abcd1234_" + "x".repeat(44);
    process.env.SOLVEX_INSTANCE_ID = INSTANCE;
    process.env.SOLVEX_PUBLIC_KEYS = rawPub;
    process.env.SUPABASE_SERVICE_ROLE_KEY = "test";
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ licenses: hub.licenses }), { status: 200 })));
    db.rpc.mockImplementation(async (fn: string) => fn === "license_activation_attempt" ? { data: true, error: null } : { data: "reconciled", error: null });
  });
  const call = async (body: unknown, auth = true) => {
    const { POST } = await import("../src/app/api/license/refresh/route");
    return POST(new Request("https://x/api/license/refresh", { method: "POST", headers: auth ? { authorization: "Bearer a.b.c" } : {}, body: JSON.stringify(body) }));
  };

  it("aplica SOLO el token firmado para esta empresa e instancia", async () => {
    const good = { iss: "solvex-hub", aud: INSTANCE, tenant: ORG, lic: "LIC-1", iat: now, exp: now + 3600, plan: "BASICO", status: "prueba", mode: "full" };
    hub.licenses = [
      { tenant_ref: ORG, token: token(good) },
      { tenant_ref: "22222222-2222-4222-8222-222222222222", token: token({ ...good, tenant: "22222222-2222-4222-8222-222222222222" }) },
      { tenant_ref: ORG, token: token({ ...good, aud: "ins_otrainstancia0000000" }) },
    ];
    const r = await call({ org_id: ORG });
    expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({ ok: true, result: "reconciled", plan: "BASICO", status: "prueba" });
    const applies = db.rpc.mock.calls.filter(([fn]) => fn === "license_sync_apply");
    expect(applies).toHaveLength(1);
    expect(applies[0][1]).toMatchObject({ p_org: ORG, p_payload: { tenant: ORG, aud: INSTANCE } });
  });
  it("una firma inválida no se aplica", async () => {
    const t = token({ iss: "solvex-hub", aud: INSTANCE, tenant: ORG, lic: "L", iat: now, exp: now + 3600, mode: "full" });
    hub.licenses = [{ tenant_ref: ORG, token: t.slice(0, -4) + "AAAA" }];
    const r = await call({ org_id: ORG });
    expect(r.status).toBe(404);
    expect(db.rpc.mock.calls.some(([fn]) => fn === "license_sync_apply")).toBe(false);
  });
  it("exige sesión y pertenencia, y limita intentos", async () => {
    expect((await call({ org_id: ORG }, false)).status).toBe(401);
    db.role = null;
    expect((await call({ org_id: ORG })).status).toBe(403);
    db.role = "cajero";
    db.rpc.mockImplementation(async () => ({ data: false, error: null }));
    expect((await call({ org_id: ORG })).status).toBe(429);
  });
});

// ───────────── Preflight (solo lectura) ─────────────

describe("evaluatePreflight: GO solo si la reconciliación activaría la empresa", () => {
  const base = { iss: "solvex-hub", aud: INSTANCE, tenant: ORG, lic: "LIC-PRUEBA-0001", iat: now, exp: now + 86400, plan: "BASICO", status: "prueba", mode: "full" as const, period_end: new Date(Date.now() + 7 * 86400e3).toISOString(), features: { max_users: 2 } };
  const local = { source: "local", license_code: "LIC-PRUEBA-0001", pending_code: "LIC-PRUEBA-0001", activated_code: null };
  const tok = (p: Record<string, unknown>) => ({ tenant: ORG, token: "x", payload: p as never });
  it("GO: token vigente, mismo código, tenant e instancia correctos", () => {
    const r = evaluatePreflight(ORG, [tok(base)], 0, local);
    expect(r.verdict).toBe("GO");
    expect(r.token).toMatchObject({ plan: "BASICO", status: "prueba", lic_last4: "0001", max_users: 2 });
    expect(JSON.stringify(r)).not.toContain("LIC-PRUEBA-0001");
  });
  it("NO-GO: el Hub no tiene licencia para la empresa", () => {
    expect(evaluatePreflight(ORG, [], 3, local)).toMatchObject({ verdict: "NO-GO", rejected_tokens_in_instance: 3 });
  });
  it("NO-GO: código distinto (habría que activar a mano)", () => {
    const r = evaluatePreflight(ORG, [tok({ ...base, lic: "NUEVO-9999" })], 0, local);
    expect(r.verdict).toBe("NO-GO");
    expect(r.checks.codigo_coincide_con_el_de_la_empresa).toBe(false);
  });
  it("NO-GO: período vencido, suspendida o token vencido", () => {
    expect(evaluatePreflight(ORG, [tok({ ...base, period_end: "2026-11-11T04:59:59Z", grace_end: "2026-11-11T04:59:59Z" })], 0, local).verdict).toBe("NO-GO");
    expect(evaluatePreflight(ORG, [tok({ ...base, mode: "blocked", status: "suspendida" })], 0, local).verdict).toBe("NO-GO");
    expect(evaluatePreflight(ORG, [tok({ ...base, exp: now - 10 })], 0, local).verdict).toBe("NO-GO");
  });
  it("toma el token más reciente del tenant", () => {
    const r = evaluatePreflight(ORG, [tok({ ...base, iat: now - 100, plan: "BASICO" }), tok({ ...base, iat: now, plan: "PRO" })], 0, local);
    expect(r.token?.plan).toBe("PRO");
  });
});
