#!/usr/bin/env bash
# Build the operator app beside the Next.js ERP, using the same Supabase project.
set -euo pipefail

backend_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$backend_dir/../app"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
version=3.47.9
revision=c197ca5199e9ee5661e865596c9c07294dfab51c

# Pass only public client parameters to dart2js, never the build environment.
node - "$work_dir/defines.json" <<'NODE'
const { writeFileSync } = require('node:fs');
const project = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL);
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';
const api = new URL(process.env.PUBLIC_BASE_URL || 'https://factura-voz-two.vercel.app');
function isPublicKey() {
  if (/^sb_publishable_[A-Za-z0-9_-]{10,}$/.test(key)) return true;
  if (!/^[\w-]+\.[\w-]+\.[\w-]+$/.test(key)) return false;
  try {
    const claims = JSON.parse(Buffer.from(key.split('.')[1], 'base64url'));
    return claims.role === 'anon' &&
      (!claims.ref || !project.hostname.endsWith('.supabase.co') || project.hostname === claims.ref + '.supabase.co');
  } catch {
    return false;
  }
}
for (const url of [project, api]) {
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw new Error('La configuración del cliente requiere orígenes HTTPS.');
  }
}
if (!isPublicKey()) throw new Error('La app requiere una clave pública de Supabase del mismo proyecto.');
writeFileSync(process.argv[2], JSON.stringify({
  SUPABASE_URL: project.origin, SUPABASE_ANON_KEY: key, API_BASE_URL: api.origin,
}), { mode: 0o600 });
NODE

# Some Vercel projects mount only their configured root directory. Use the
# exact deployment commit in that case, including when building PR previews.
if [[ ! -f "$app_dir/pubspec.yaml" ]]; then
  commit="${VERCEL_GIT_COMMIT_SHA:-$(git -C "$backend_dir" rev-parse HEAD)}"
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'Falta el SHA del despliegue.' >&2; exit 1; }
  app_dir="$work_dir/app"
  mkdir -p "$app_dir"
  if git -C "$backend_dir" cat-file -e "$commit:app/pubspec.yaml" 2>/dev/null; then
    repo_dir="$(git -C "$backend_dir" rev-parse --show-toplevel)"
    git -C "$repo_dir" archive "$commit:app" | tar -xf - -C "$app_dir"
  else
    curl --fail --silent --show-error --location --retry 3 \
      "https://codeload.github.com/PFfrank13/FacturaVoz/tar.gz/$commit" -o "$work_dir/source.tar.gz"
    tar -xzf "$work_dir/source.tar.gz" -C "$app_dir" --strip-components=2 "FacturaVoz-$commit/app"
  fi
  test -s "$app_dir/lib/main.dart"
fi

flutter_bin="$(command -v flutter || true)"
sdk_dir=""
if [[ -n "$flutter_bin" ]]; then
  sdk_dir="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
fi
if [[ -z "$sdk_dir" || "$(git -C "$sdk_dir" rev-parse HEAD 2>/dev/null || true)" != "$revision" ]]; then
  sdk_dir="$work_dir/flutter"
  git init -q "$sdk_dir"
  git -C "$sdk_dir" remote add origin https://github.com/flutter/flutter.git
  for attempt in 1 2 3; do
    if git -C "$sdk_dir" fetch --quiet --depth 1 origin "refs/tags/$version:refs/tags/$version"; then break; fi
    if [[ "$attempt" == 3 ]]; then exit 1; fi
    sleep "$((attempt * 2))"
  done
  [[ "$(git -C "$sdk_dir" rev-parse "$version^{commit}")" == "$revision" ]]
  git -C "$sdk_dir" checkout -q -b stable "$revision"
fi
export PATH="$sdk_dir/bin:$PATH"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true
if [[ "${VERCEL:-}" == 1 ]]; then
  export PUB_CACHE="$backend_dir/.next/cache/flutter-pub"
fi

cd "$app_dir"
flutter pub get --enforce-lockfile
flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn \
  --base-href=/app/ --target=lib/main.dart --output="$work_dir/web" \
  --dart-define-from-file="$work_dir/defines.json"
test -s "$work_dir/web/main.dart.js"
grep -Fq '<base href="/app/">' "$work_dir/web/index.html"

# Replace the complete generated bundle so retired assets disappear on rebuild.
mkdir -p "$backend_dir/public"
destination="$backend_dir/public/app"
if [[ -e "$destination" ]]; then
  [[ -f "$destination/flutter_bootstrap.js" ]] || { echo 'El destino ya existe y no es un build Flutter.' >&2; exit 1; }
  mv "$destination" "$work_dir/previous"
fi
if ! mv "$work_dir/web" "$destination"; then
  if [[ -d "$work_dir/previous" ]]; then mv "$work_dir/previous" "$destination"; fi
  exit 1
fi
