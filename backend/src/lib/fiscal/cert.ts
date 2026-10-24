import forge from "node-forge";

export type CertResult = { pem: string; notAfter: Date; subject: string };

/**
 * Convierte un certificado digital .pfx/.p12 (o un PEM ya combinado) al PEM único
 * (clave privada + certificado) que exige Greenter/Lycet.
 * Nada se escribe en disco ni se registra: todo queda en memoria durante la petición.
 */
export function toLycetPem(b64: string, format: "pfx" | "pem", password: string): CertResult {
  const raw = Buffer.from(b64, "base64");
  if (raw.length === 0 || raw.length > 100_000) throw new CertError("Archivo de certificado no válido");

  let keyPem: string | undefined;
  let certs: forge.pki.Certificate[] = [];

  if (format === "pem") {
    const text = raw.toString("utf8");
    const key = /-----BEGIN (?:RSA |ENCRYPTED )?PRIVATE KEY-----[\s\S]+?-----END (?:RSA |ENCRYPTED )?PRIVATE KEY-----/.exec(text);
    if (!key) throw new CertError("El PEM no contiene la clave privada");
    if (key[0].includes("ENCRYPTED")) throw new CertError("El PEM tiene la clave cifrada; usa el .pfx");
    keyPem = key[0];
    const re = /-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g;
    certs = (text.match(re) ?? []).map((c) => forge.pki.certificateFromPem(c));
  } else {
    try {
      const asn1 = forge.asn1.fromDer(forge.util.createBuffer(raw.toString("binary")));
      const p12 = forge.pkcs12.pkcs12FromAsn1(asn1, false, password);
      const keyBags = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag] ?? [];
      const plainBags = p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag] ?? [];
      const key = [...keyBags, ...plainBags][0]?.key;
      if (!key) throw new CertError("El .pfx no contiene clave privada");
      keyPem = forge.pki.privateKeyToPem(key);
      const certBags = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag] ?? [];
      certs = certBags.map((b) => b.cert).filter((c): c is forge.pki.Certificate => !!c);
    } catch (e) {
      if (e instanceof CertError) throw e;
      throw new CertError("No se pudo abrir el .pfx: revisa la contraseña del certificado");
    }
  }
  if (!keyPem || certs.length === 0) throw new CertError("El certificado está incompleto");

  // El certificado de firma es el que corresponde a la clave privada
  const leaf = certs.find((c) => {
    try {
      const pub = c.publicKey as forge.pki.rsa.PublicKey;
      const priv = forge.pki.privateKeyFromPem(keyPem!) as forge.pki.rsa.PrivateKey;
      return pub.n.compareTo(priv.n) === 0;
    } catch {
      return false;
    }
  });
  if (!leaf) throw new CertError("La clave privada no corresponde a ningún certificado del archivo");

  const now = new Date();
  if (leaf.validity.notAfter < now) throw new CertError("El certificado digital está vencido");
  if (leaf.validity.notBefore > now) throw new CertError("El certificado digital aún no es válido");

  const ordered = [leaf, ...certs.filter((c) => c !== leaf)];
  const pem = [keyPem.trim(), ...ordered.map((c) => forge.pki.certificateToPem(c).trim())].join("\n") + "\n";
  const subject = leaf.subject.attributes.map((a) => `${a.shortName ?? a.name}=${a.value}`).join(", ");
  return { pem, notAfter: leaf.validity.notAfter, subject };
}

export class CertError extends Error {}
