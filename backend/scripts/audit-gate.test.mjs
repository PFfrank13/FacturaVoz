import { strict as assert } from "node:assert";
import { test } from "node:test";
import { evaluateAudit } from "./audit-gate.mjs";

const GHSA = "https://github.com/advisories/GHSA-fc5q-39xc-vjpf";
const dev = Object.freeze({
  packages: {
    "node_modules/picomatch": { dev: true },
    "node_modules/vitest": { dev: true },
  },
});
const root = () => ({
  metadata: { vulnerabilities: { high: 2 } },
  vulnerabilities: {
    picomatch: {
      severity: "high",
      nodes: ["node_modules/picomatch"],
      via: [{ name: "picomatch", url: GHSA, severity: "high" }],
    },
    vitest: {
      severity: "high",
      nodes: ["node_modules/vitest"],
      via: ["picomatch"],
    },
  },
});

test("accepts only reviewed temporary developer advisory with exact chain", () => {
  assert.deepEqual(evaluateAudit(root(), dev, "2026-11-17"), {
    failures: [], accepted: ["GHSA-fc5q-39xc-vjpf"],
  });
});

test("expires reviewed developer risk instead of hiding it permanently", () => {
  const result = evaluateAudit(root(), dev, "2027-01-01");
  assert.deepEqual(result.accepted, []);
  assert.ok(result.failures.some(x => x.includes("revisión vencida")));
});

test("blocks picomatch if included in production graph", () => {
  const lock = structuredClone(dev);
  lock.packages["node_modules/picomatch"].dev = false;
  const result = evaluateAudit(root(), lock, "2026-11-17");
  assert.deepEqual(result.accepted, []);
  assert.ok(result.failures.some(x => x.includes("dependencias de producción")));
});

test("blocks newly published or unrelated HIGH advisory, even in dev", () => {
  const report = root();
  report.vulnerabilities.picomatch.via.push({
    name: "picomatch",
    url: "https://github.com/advisories/GHSA-aaaa-bbbb-cccc",
    severity: "high",
  });
  const result = evaluateAudit(report, dev, "2026-11-17");
  assert.ok(result.failures.some(x => x.includes("GHSA-aaaa-bbbb-cccc")));
});

test("rejects review if originating package changes", () => {
  const report = root();
  report.vulnerabilities.picomatch.via[0].name = "unrelated-package";
  const result = evaluateAudit(report, dev, "2026-11-17");
  assert.deepEqual(result.accepted, []);
  assert.ok(result.failures.some(x => x.includes("paquete distinto")));
});

test("fails closed on npm errors, missing metadata or a partial lockfile", () => {
  for (const report of [{ error: { code: "EAI_AGAIN" } }, { vulnerabilities: {} }, null]) {
    assert.equal(evaluateAudit(report, dev).failures.length, 1);
  }
  assert.equal(evaluateAudit(root(), {}).failures.length, 1);
});

test("all HIGH package nodes must be devOnly, not just the advisory leaf", () => {
  const lock = structuredClone(dev);
  lock.packages["node_modules/vitest"].dev = false;
  const result = evaluateAudit(root(), lock, "2026-11-17");
  assert.ok(result.failures.some(x => x.startsWith("vitest:")));
});

test("returns green for a fully audited, clean dependency graph", () => {
  const report = { metadata: { vulnerabilities: { high: 0, critical: 0 } },
    vulnerabilities: {} };
  assert.deepEqual(evaluateAudit(report, dev), { failures: [], accepted: [] });
});
