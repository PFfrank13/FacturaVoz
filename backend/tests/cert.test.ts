import forge from "node-forge";
import { describe, expect, it } from "vitest";
import { CertError, toLycetPem } from "../src/lib/fiscal/cert";

function makeCert(cn: string, validDays = 365) {
  const keys = forge.pki.rsa.generateKeyPair(2048);
  const cert = forge.pki.createCertificate();
  cert.publicKey = keys.publicKey;
  cert.serialNumber = "01";
  cert.validity.notBefore = new Date(Date.now() - 86_400_000 * (validDays < 0 ? 400 : 1));
  cert.validity.notAfter = new Date(Date.now() + 86_400_000 * validDays);
  const attrs = [{ name: "commonName", value: cn }];
  cert.setSubject(attrs);
  cert.setIssuer(attrs);
  cert.sign(keys.privateKey, forge.md.sha256.create());
  return { keys, cert };
}
const pfxB64 = (cn: string, pass: string, days = 365) => {
  const { keys, cert } = makeCert(cn, days);
  const p12 = forge.pkcs12.toPkcs12Asn1(keys.privateKey, [cert], pass, { algorithm: "3des" });
  return Buffer.from(forge.asn1.toDer(p12).getBytes(), "binary").toString("base64");
};

describe("certificado digital", () => {
  it("convierte .pfx a PEM (clave + certificado) y expone la vigencia", () => {
    const r = toLycetPem(pfxB64("EMPRESA 20000000001", "clave"), "pfx", "clave");
    expect(r.pem).toMatch(/BEGIN RSA PRIVATE KEY/);
    expect(r.pem).toMatch(/BEGIN CERTIFICATE/);
    expect(r.subject).toContain("20000000001");
    expect(r.notAfter.getTime()).toBeGreaterThan(Date.now());
  });
  it("contraseña incorrecta", () => {
    expect(() => toLycetPem(pfxB64("X", "clave"), "pfx", "otra")).toThrow(CertError);
  });
  it("certificado vencido", () => {
    expect(() => toLycetPem(pfxB64("X", "k", -10), "pfx", "k")).toThrow(/vencido/);
  });
  it("PEM combinado", () => {
    const { keys, cert } = makeCert("EMPRESA");
    const pem = forge.pki.privateKeyToPem(keys.privateKey) + forge.pki.certificateToPem(cert);
    expect(toLycetPem(Buffer.from(pem).toString("base64"), "pem", "").pem).toMatch(/BEGIN CERTIFICATE/);
  });
  it("basura", () => {
    expect(() => toLycetPem(Buffer.from("hola").toString("base64"), "pfx", "")).toThrow(CertError);
    expect(() => toLycetPem("", "pfx", "")).toThrow(CertError);
  });
});
