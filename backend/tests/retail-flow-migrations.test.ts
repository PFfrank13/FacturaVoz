import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const sql = (name: string) => readFileSync(
  join(__dirname, "../supabase/migrations", name), "utf8",
);
const receipt = sql("20261126_v32_retail_receive.sql");
const settlement = sql("20261127_v32_retail_settle.sql");
const stock = sql("20261128_v32_retail_sale_stock_events.sql");

describe("Retail Basic migration regression gates (static only; not DB integration)", () => {
  it("validates tenant admin, Hub license, product IDs and idempotent receipt", () => {
    expect(receipt).toContain("not private.is_org_admin(p_org)");
    expect(receipt).toContain("not private.license_write_ok(p_org)");
    expect(receipt).toContain("not private.has_feature(p_org,'stock')");
    expect(receipt).toContain("on conflict (org_id, request_id) do nothing");
    expect(receipt).toContain("for update");
    expect(receipt).toContain("create table if not exists public.retail_inventory_events");
    expect(receipt).toContain("revoke all on public.retail_receipts from public, anon, authenticated");
  });

  it("cannot settle a purchase with second request ID or second stock receipt", () => {
    expect(settlement).toContain("unique (org_id, request_id)");
    expect(settlement).toContain("unique (receipt_id)");
    expect(settlement).toContain("v_receipt.payment_method <> 'pendiente'");
    expect(settlement).toContain("v_previous.receipt_id <> p_receipt");
    expect(settlement).toContain("private.license_write_ok(p_org)");
    expect(settlement).toContain("private.is_org_admin(p_org)");
    expect(settlement).not.toContain("update public.products");
  });

  it("allows negative-stock sales, records immutable movements and protects view", () => {
    expect(stock).toContain("create table if not exists public.retail_sale_stock_events");
    expect(stock).toContain("unique references public.invoice_items");
    expect(stock).toContain("v_after := v_before - r.quantity");
    expect(stock).not.toContain("Stock insuficiente");
    expect(stock).toContain("for update");
    expect(stock).toContain("security_invoker = true");
    expect(stock).toContain("private.is_org_admin(org_id)");
    expect(stock).toContain("grant select on public.retail_stock_flow to authenticated");
  });

  it("does not modify production Hub licenses or turn off enforcement", () => {
    for (const file of [receipt, settlement, stock]) {
      expect(file).not.toMatch(/update\s+public\.org_licenses\b/i);
      expect(file).not.toMatch(/license_set_enforced\s*\(/i);
      expect(file).not.toMatch(/drop\s+table\s+(?!if exists)public\.products/i);
      expect(file).not.toMatch(/delete\s+from\s+public\.invoices/i);
    }
  });
});
