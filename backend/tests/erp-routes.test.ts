import { beforeEach, describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import DataTable from "../src/components/erp/DataTable";

const mock = vi.hoisted(() => ({ context: vi.fn(), notFound: vi.fn(() => { throw new Error("NOT_FOUND"); }) }));
vi.mock("@/lib/erp/context", () => ({ workspaceContext: mock.context }));
vi.mock("next/navigation", () => ({ notFound: mock.notFound, useRouter: () => ({ refresh: vi.fn() }) }));
import ModulePage from "../src/app/erp/[org]/[module]/page";

describe("ERP routes", () => {
  beforeEach(() => vi.clearAllMocks());
  it("rejects a direct URL to stock before querying business data", async () => {
    const from = vi.fn();
    mock.context.mockResolvedValue({ org: "test", db: { from }, license: { enforced: true, source: "hub", mode: "full", features: { stock: false } }, access: { is_admin: true }, sector: "bodega" });
    await expect(ModulePage({ params: Promise.resolve({ org: "test", module: "inventario" }), searchParams: Promise.resolve({}) })).rejects.toThrow("NOT_FOUND");
    expect(from).not.toHaveBeenCalled();
  });
  it("rejects unknown/unimplemented modules", async () => {
    mock.context.mockResolvedValue({ db: {}, license: {}, access: {}, sector: "educacion" });
    await expect(ModulePage({ params: Promise.resolve({ org: "test", module: "calificaciones" }), searchParams: Promise.resolve({}) })).rejects.toThrow("NOT_FOUND");
  });
  it("renders a useful empty state, labelled search and keyboard reachable table", () => {
    const html = renderToStaticMarkup(createElement(DataTable, { rows: [], fields: [["name", "Nombre"]] }));
    expect(html).toContain("Todavía no hay registros");
    expect(html).toContain('type="search"');
    expect(html).toContain('tabindex="0"');
    expect(html).toContain('aria-sort="none"');
  });
  it("escapes untrusted customer names", () => {
    const html = renderToStaticMarkup(createElement(DataTable, { rows: [{ id: "1", name: "<script>alert(1)</script>" }], fields: [["name", "Nombre"]] }));
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });
});
