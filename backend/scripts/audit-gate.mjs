// Auditoría estricta de la cadena de suministro del backend.
// Las revisiones excepcionales son temporales, específicas y solo dev.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const high = new Set(["high", "critical"]);

const REVIEWED_DEV = Object.freeze({
  "GHSA-fc5q-39xc-vjpf": {
    package: "picomatch",
    expires: "2026-12-31",
    reason: "ReDoS en extglobs aportados por el usuario. Presente exclusivamente " +
      "en ESLint y Vitest del CI; no se compilan ni aceptan patrones de usuarios " +
      "en ejecución de producción. Sin release reparado para picomatch 4.x a " +
      "2026-11-17. Vigilar GHSA-fc5q-39xc-vjpf e issue #14.",
  },
});

function issueId(via) {
  const id = String(via?.url ?? "").split("/").pop();
  return /^GHSA-[a-z0-9-]+$/.test(id) ? id : "";
}

function devOnly(name, report, lock) {
  const v = report.vulnerabilities?.[name];
  const nodes = v?.nodes;
  return Array.isArray(nodes) && nodes.length > 0 &&
    nodes.every((path) =>
      typeof path === "string" &&
      lock.packages?.[path]?.dev === true);
}

function roots(name, report, seen = new Set()) {
  if (seen.has(name)) return [{ id: "", reason: "dependencias circulares" }];
  const v = report.vulnerabilities?.[name];
  if (!v || !Array.isArray(v.via)) return [{ id: "", reason: "cadena incompleta" }];
  const next = new Set([...seen, name]);
  const results = [];
  for (const via of v.via) {
    if (typeof via === "string") {
      const child = report.vulnerabilities?.[via];
      // No derivar una vulnerabilidad HIGH de una alerta solo MODERATE.
      if (child && high.has(child.severity)) {
        for (const root of roots(via, report, next)) {
          results.push({ ...root, chain: [name, ...(root.chain ?? [via])] });
        }
      }
    } else if (via && high.has(via.severity)) {
      results.push({ id: issueId(via), package: via.name,
        chain: [name], severity: via.severity });
    }
  }
  return results.length ? results : [{ id: "", reason: "sin advisory HIGH identificable", chain: [name] }];
}

/** Comprueba toda la cadena HIGH, no solo los advisories directos. */
export function evaluateAudit(report, lock, today = new Date().toISOString().slice(0, 10)) {
  if (!report || typeof report !== "object" ||
      !report.metadata?.vulnerabilities || !report.vulnerabilities ||
      typeof report.vulnerabilities !== "object" ||
      !lock?.packages || typeof lock.packages !== "object" || report.error) {
    return { failures: ["Auditoría incompleta o respuesta inválida de npm"],
      accepted: [] };
  }
  const failures = [];
  const accepted = new Set();
  for (const [name, v] of Object.entries(report.vulnerabilities)) {
    if (!high.has(v.severity)) continue;
    for (const root of roots(name, report)) {
      const reviewed = REVIEWED_DEV[root.id];
      const chain = root.chain ?? [name];
      const devChain = chain.every((part) => devOnly(part, report, lock));
      if (reviewed && root.package === reviewed.package &&
          today <= reviewed.expires && devChain) {
        accepted.add(root.id);
      } else {
        const why = !reviewed ? "no revisado" :
          today > reviewed.expires ? "revisión vencida" :
          !devChain ? "incluye dependencias de producción" :
          "paquete distinto del revisado";
        failures.push(`${name}: ${root.id || "sin GHSA"} (${why})`);
      }
    }
  }
  return { failures: [...new Set(failures)], accepted: [...accepted] };
}

function runAudit(extraArgs = []) {
  const result = spawnSync("npm", ["audit", "--json", ...extraArgs], {
    encoding: "utf8", maxBuffer: 16 * 1024 * 1024, timeout: 120_000,
  });
  if (result.error || ![0, 1].includes(result.status)) {
    throw new Error(`npm audit no pudo ejecutarse: ${result.error?.message ??
      result.stderr?.trim() ?? "estado desconocido"}`);
  }
  let report;
  try { report = JSON.parse(result.stdout); }
  catch { throw new Error("npm audit devolvió JSON inválido o incompleto"); }
  if (report.error || !report.metadata?.vulnerabilities || !report.vulnerabilities) {
    throw new Error("npm audit no devolvió un inventario verificable");
  }
  return report;
}

function main() {
  const lock = JSON.parse(readFileSync(new URL("../package-lock.json", import.meta.url), "utf8"));
  // La auditoría de la aplicación desplegada NO tiene excepciones.
  const runtime = evaluateAudit(runAudit(["--omit=dev"]), lock);
  if (runtime.failures.length || runtime.accepted.length) {
    throw new Error("Dependencias de producción sin seguridad comprobada: " +
      [...runtime.failures, ...runtime.accepted].join(", "));
  }

  const full = evaluateAudit(runAudit(), lock);
  if (full.failures.length) {
    console.error("Vulnerabilidades HIGH/CRITICAL no admitidas:\n" +
      full.failures.join("\n"));
    process.exitCode = 1;
    return;
  }
  if (full.accepted.length) {
    for (const id of full.accepted) {
      const review = REVIEWED_DEV[id];
      console.warn(`RIESGO DE DESARROLLO TEMPORAL: ${id}; vence ${review.expires}. ${review.reason}`);
    }
  }
  console.log("audit-gate: dependencias de producción sin HIGH/CRITICAL; " +
    "sin nuevas alertas altas en herramientas de desarrollo.");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); }
  catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
