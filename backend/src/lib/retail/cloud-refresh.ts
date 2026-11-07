/** Events invalidate queries; they never become authoritative business records. */
export const retailRefreshTables = [
  "org_licenses", "org_settings", "organization_members", "products",
  "invoices", "payments", "cash_movements", "expenses",
  "retail_suppliers", "retail_receipts", "retail_stock_ledger",
] as const;

export function coalescedRefresh(refresh: () => void, eligible: () => boolean, delay = 250) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let stopped = false;
  return {
    request() {
      if (stopped || timer !== undefined || !eligible()) return;
      // A bounded window prevents a busy store from postponing refresh forever.
      timer = setTimeout(() => {
        timer = undefined;
        if (!stopped && eligible()) refresh();
      }, delay);
    },
    stop() { stopped = true; clearTimeout(timer); timer = undefined; },
  };
}
