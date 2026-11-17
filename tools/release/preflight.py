#!/usr/bin/env python3
"""Fail-closed, secret-safe Android release preflight for FacturaVoz.

This does not sign software. Source checks run in CI without private keys;
--release must run on the owner's signing computer with real credentials.
"""
from __future__ import annotations

import argparse
import base64
import ipaddress
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

APP_ID = "dev.solvexsoftware.facturavoz"
ALLOWED_DEFINES = frozenset({
    "SUPABASE_URL", "SUPABASE_ANON_KEY", "API_BASE_URL",
    "APP_VERSION", "SUPPORT_WHATSAPP", "PRIVACY_URL", "TERMS_URL",
    "GOOGLE_LOGIN",
})
SIGN_KEYS = ("storeFile", "storePassword", "keyAlias", "keyPassword")
VERSION = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.M)
APP_ID_RE = re.compile(r'applicationId\s*=\s*"([^"]+)"')


def _file(path: Path, problems: list[str]) -> str:
    if not path.is_file():
        problems.append(f"Falta archivo obligatorio: {path.name}")
        return ""
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        problems.append(f"No se pudo leer el archivo: {path.name}")
        return ""


def source_errors(project: Path) -> list[str]:
    """Check distribution invariants without requesting secrets or keystores."""
    problems: list[str] = []
    pubspec = _file(project / "pubspec.yaml", problems)
    gradle = _file(project / "android/app/build.gradle.kts", problems)
    manifest = _file(project / "android/app/src/main/AndroidManifest.xml", problems)

    match = VERSION.search(pubspec)
    if match is None or int(match.group(2)) < 1:
        problems.append("pubspec.yaml requiere version X.Y.Z+codigo positivo.")
    id_match = APP_ID_RE.search(gradle)
    if id_match is None or id_match.group(1) != APP_ID:
        problems.append("El applicationId Android no corresponde al producto autorizado.")
    if "hasSafeReleaseSigning" not in gradle or 'signingConfigs.getByName("release")' not in gradle:
        problems.append("Falta la firma release explícita de Gradle.")
    # Never permit a distribution signed with Android's default debug key.
    if 'signingConfig = signingConfigs.getByName("debug")' in gradle:
        problems.append("Prohibido reutilizar firma debug para release.")
    if 'android:allowBackup="false"' not in manifest:
        problems.append("El backup Android debe permanecer deshabilitado.")
    if 'android:usesCleartextTraffic="false"' not in manifest:
        problems.append("No se permite tráfico HTTP sin cifrar en release.")
    if 'android:exported="true"' not in manifest:
        problems.append("La Activity de inicio debe declarar android:exported.")
    return problems


def _public_jwt(value: str) -> bool:
    try:
        parts = value.split(".")
        if len(parts) != 3:
            return False
        raw = base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4))
        payload = json.loads(raw.decode("utf-8"))
        return isinstance(payload, dict) and payload.get("role") == "anon"
    except (ValueError, UnicodeError, KeyError, TypeError):
        return False


def _https_public(url: str) -> bool:
    """Reject test, local and credential-bearing endpoints in distributed apps.

    This checks URL syntax and obvious reserved/private destinations; it does
    not claim DNS ownership, deployment health or TLS certificate verification.
    """
    try:
        if not isinstance(url, str) or url != url.strip() or any(ch.isspace() for ch in url):
            return False
        parts = urlsplit(url)
        host = (parts.hostname or "").lower().rstrip(".")
        # No username, query tokens, fragments, cleartext or protocol-relative URLs.
        if (parts.scheme != "https" or not parts.netloc or not host or
                "@" in parts.netloc or parts.query or parts.fragment):
            return False
        port = parts.port  # raises ValueError on invalid ports
        if port is not None and (port < 1 or port > 65535):
            return False
        try:
            ip = ipaddress.ip_address(host)
        except ValueError:
            ip = None
        if ip is not None:
            return ip.is_global
        if "." not in host or not all(
            re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
            for label in host.split(".")
        ):
            return False
        reserved_suffixes = (
            "example", "example.com", "example.net", "example.org",
            "test", "invalid", "localhost", "local", "internal", "home.arpa",
        )
        return not any(host == suffix or host.endswith("." + suffix)
                       for suffix in reserved_suffixes)
    except (ValueError, TypeError):
        return False


def defines_errors(path: Path, expected_version: str) -> list[str]:
    problems: list[str] = []
    raw = _file(path, problems)
    if not raw:
        return problems
    try:
        values = json.loads(raw)
    except (ValueError, UnicodeError):
        return ["El archivo de configuración de compilación no es JSON válido."]
    if not isinstance(values, dict):
        return ["La configuración de compilación debe ser un objeto JSON."]
    unexpected = set(values) - ALLOWED_DEFINES
    if unexpected:
        # Do not echo unknown keys or their values; they may reveal secret names.
        problems.append("Se encontraron defines no autorizados para incluir en el APK.")
    if not all(isinstance(v, (str, bool)) for v in values.values()):
        problems.append("Los defines deben ser cadenas o booleanos.")
    for key in ("SUPABASE_URL", "API_BASE_URL"):
        if not isinstance(values.get(key), str) or not _https_public(values[key]):
            problems.append(f"{key}: requiere URL HTTPS pública, real y sin credenciales.")
    key = values.get("SUPABASE_ANON_KEY", "")
    if not isinstance(key, str) or not (
        (re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{10,}", key) is not None)
        or _public_jwt(key)
    ):
        problems.append("SUPABASE_ANON_KEY debe ser una clave publicable o JWT con rol anon.")
    if values.get("APP_VERSION") != expected_version:
        problems.append("APP_VERSION debe coincidir con la versión de pubspec.yaml.")
    if "GOOGLE_LOGIN" in values and str(values["GOOGLE_LOGIN"]).lower() not in ("true", "false"):
        problems.append("GOOGLE_LOGIN debe ser booleano.")
    return problems


def read_sign_properties(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for row in text.splitlines():
        row = row.strip()
        if not row or row.startswith(("#", "!")):
            continue
        if "=" in row:
            k, v = row.split("=", 1)
        elif ":" in row:
            k, v = row.split(":", 1)
        else:
            continue
        result[k.strip()] = v.strip()
    return result


def signing_errors(project: Path, signing_dir: Path) -> list[str]:
    problems: list[str] = []
    home = signing_dir.resolve()
    root = project.resolve()
    if home.is_relative_to(root):
        problems.append("Los secretos de firma deben permanecer fuera del repositorio.")
    props = home / "signing.properties"
    data = _file(props, problems)
    if not data:
        return problems
    values = read_sign_properties(data)
    if any(not values.get(k) for k in SIGN_KEYS):
        problems.append("La configuración privada de firma está incompleta.")
        return problems
    alias = values["keyAlias"].strip().lower()
    if alias in {"androiddebugkey", "debug", "test"}:
        problems.append("La distribución no puede usar alias de desarrollo.")
    address = Path(values["storeFile"])
    resolved = (address if address.is_absolute() else project / "android/app" / address).resolve()
    if root == resolved or resolved.is_relative_to(root):
        problems.append("El keystore privado no debe almacenarse dentro del proyecto.")
    if "debug.keystore" in resolved.name.lower():
        problems.append("Está prohibido usar debug.keystore para releases.")
    if not resolved.is_file():
        problems.append("No se encuentra el keystore de release.")
    return problems


def check(project: Path, *, release: bool = False, defines: Path | None = None,
          signing_dir: Path | None = None) -> list[str]:
    problems = source_errors(project)
    if release:
        pubspec = (project / "pubspec.yaml")
        version = VERSION.search(pubspec.read_text(encoding="utf-8")) if pubspec.is_file() else None
        if defines is None:
            problems.append("Debe indicar --defines para una compilación release.")
        elif version is not None:
            problems.extend(defines_errors(defines, version.group(1)))
        if signing_dir is None:
            signing_dir = Path.home() / "FacturaVoz-Signing"
        problems.extend(signing_errors(project, signing_dir))
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--source", action="store_true", help="Validar invariantes de código sin secretos (CI).")
    group.add_argument("--release", action="store_true", help="Validar la configuración real en equipo de firma.")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2] / "app")
    parser.add_argument("--defines", type=Path, help="JSON local de defines públicos para el release.")
    parser.add_argument("--signing-dir", type=Path, help="Directorio privado ~/FacturaVoz-Signing.")
    opts = parser.parse_args()
    problems = check(opts.project.resolve(), release=opts.release,
                     defines=opts.defines, signing_dir=opts.signing_dir)
    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        print("Release bloqueada; no se generó autorización de distribución.", file=sys.stderr)
        return 1
    print("OK: preflight de código" if opts.source else "OK: requisitos locales de release comprobados.")
    print("La firma criptográfica del artefacto debe verificarse después de compilar.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
