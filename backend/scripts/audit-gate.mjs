// Falla si hay vulnerabilidades HIGH/CRITICAL, salvo las revisadas y justificadas aquí.
import { execSync } from "node:child_process";

const ALLOW = {
  // node-forge: fallo en VERIFICACIÓN de firmas RSA PKCS#1 v1.5. Solo lo usamos para LEER un .pfx
  // y exportar clave/certificado (src/lib/fiscal/cert.ts); nunca verificamos firmas con él.
  "GHSA-86w9-cpqp-85rv": "node-forge: verificación de firma (no se usa)",
};

let out;
try {
  out = execSync("npm audit --json", { encoding: "utf8" });
} catch (e) {
  out = e.stdout?.toString() ?? "{}";
}
const report = JSON.parse(out);
const bad = [];
for (const [name, v] of Object.entries(report.vulnerabilities ?? {})) {
  if (!["high", "critical"].includes(v.severity)) continue;
  const advisories = (v.via ?? []).filter((x) => typeof x === "object");
  const unresolved = advisories.filter((a) => !ALLOW[String(a.url ?? "").split("/").pop()]);
  if (advisories.length === 0 || unresolved.length > 0) bad.push(`${name} (${v.severity})`);
}
if (bad.length) {
  console.error("Vulnerabilidades sin revisar:", bad.join(", "));
  process.exit(1);
}
console.log("npm audit: sin vulnerabilidades altas sin revisar. Excepciones:", Object.keys(ALLOW).join(", "));
