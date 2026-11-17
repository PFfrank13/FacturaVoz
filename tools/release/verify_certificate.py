#!/usr/bin/env python3
"""Compare APK/AAB signer fingerprints against the operator-approved identity.

This checks certificate continuity only. The build script must first verify
actual APK/JAR signatures using Android SDK apksigner and JDK jarsigner.
Certificate fingerprints are public, never private keystore material.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_HEX64 = re.compile(r"^[0-9A-Fa-f]{64}$")
_APK = re.compile(
    r"^Signer\s+#\d+\s+certificate\s+SHA-256\s+digest:\s*([0-9A-Fa-f]{64})\s*$",
    re.I | re.M,
)
_AAB = re.compile(
    r"^\s*SHA256:\s*((?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}|[0-9A-Fa-f]{64})\s*$",
    re.I | re.M,
)


def fingerprint(raw: str) -> str:
    """Accept Android hex or separated hex fingerprints, nothing else."""
    if not isinstance(raw, str):
        raise ValueError("La huella SHA-256 debe ser una cadena.")
    clean = raw.replace(":", "").strip()
    if not _HEX64.fullmatch(clean):
        raise ValueError("Huella inválida: se esperan 64 caracteres hexadecimales SHA-256.")
    return clean.upper()


def parse_apk_signers(output: str) -> set[str]:
    return {fingerprint(s) for s in _APK.findall(output)}


def parse_aab_signers(output: str) -> set[str]:
    return {fingerprint(s) for s in _AAB.findall(output)}


def verify(expected: str, apk_output: str, aab_output: str) -> str:
    """Require exactly one APK signer and one AAB signer, both approved."""
    allowed = fingerprint(expected)
    apk = parse_apk_signers(apk_output)
    aab = parse_aab_signers(aab_output)
    if len(apk) != 1 or len(aab) != 1:
        raise ValueError(
            "No se pudo verificar una identidad de firma única para APK y AAB; distribución bloqueada."
        )
    if allowed not in apk or allowed not in aab:
        raise ValueError(
            "El certificado APK/AAB no coincide con la huella autorizada; distribución bloqueada."
        )
    return allowed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True, help="Huella SHA-256 aprobada (sin contraseñas).")
    parser.add_argument("--apk-log", type=Path, required=True)
    parser.add_argument("--aab-log", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify(
            args.expected,
            args.apk_log.read_text(encoding="utf-8"),
            args.aab_log.read_text(encoding="utf-8"),
        )
    except (ValueError, OSError, UnicodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"OK: ambos artefactos están firmados por el certificado aprobado SHA-256 {result}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
