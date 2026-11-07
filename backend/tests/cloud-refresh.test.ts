import { afterEach, expect, it, vi } from "vitest";
import { coalescedRefresh } from "../src/lib/retail/cloud-refresh";
afterEach(() => vi.useRealTimers());
it("coalesces transaction event bursts without starving queries", () => {
  vi.useFakeTimers(); const query = vi.fn(); const refresh = coalescedRefresh(query, () => true);
  for (let n = 0; n < 10; n++) { refresh.request(); vi.advanceTimersByTime(50); }
  expect(query).toHaveBeenCalledTimes(2);
  refresh.stop();
});
it("skips hidden/offline reads and recovers on the next eligible event", () => {
  vi.useFakeTimers(); let online = false; const query = vi.fn(); const refresh = coalescedRefresh(query, () => online);
  refresh.request(); vi.advanceTimersByTime(300); expect(query).not.toHaveBeenCalled();
  online = true; refresh.request(); online = false; vi.advanceTimersByTime(300); expect(query).not.toHaveBeenCalled();
  online = true; refresh.request(); vi.advanceTimersByTime(300); expect(query).toHaveBeenCalledOnce();
});
it("does not refresh the old organization after cleanup", () => {
  vi.useFakeTimers(); const query = vi.fn(); const refresh = coalescedRefresh(query, () => true);
  refresh.request(); refresh.stop(); refresh.request(); vi.advanceTimersByTime(300);
  expect(query).not.toHaveBeenCalled();
});
