#!/usr/bin/env bash
# Build the operator app beside the Next.js ERP, using the same Supabase project.
set -euo pipefail

backend_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$backend_dir/../app"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
version=3.47.9
revision=c197ca5199e9ee5661e865596c9c07294dfab51c

archive_dir="$backend_dir/flutter-web"
config_tool="$backend_dir/scripts/flutter-web-config.mjs"
source_repo="$(git -C "$backend_dir" rev-parse --show-toplevel 2>/dev/null || true)"

source_fingerprint() {
  local entries
  [[ -n "$source_repo" ]] || return 1
  entries="$(git -C "$source_repo" ls-tree -r HEAD -- app/lib app/assets app/packages app/web app/pubspec.yaml app/pubspec.lock)" || return 1
  [[ "$entries" == *'app/lib/main.dart'* && "$entries" == *'app/pubspec.lock'* ]] || return 1
  printf '%s\n' "$entries" | grep -Ev $'\tapp/packages/[^/]+/(test|tool)/' | sha256sum | cut -d' ' -f1
}

check_web() {
  local dir="$1"
  for file in index.html main.dart.js flutter_bootstrap.js flutter.js manifest.json favicon.png \
      icons/Icon-192.png assets/FontManifest.json canvaskit/canvaskit.wasm; do
    test -s "$dir/$file" || { echo "Build web incompleto: falta $file" >&2; return 1; }
  done
  grep -Fq '<base href="/app/">' "$dir/index.html"
}

fingerprint="$(source_fingerprint || true)"
if [[ -z "$fingerprint" && "${VERCEL_GIT_COMMIT_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
  # Some builders omit Git history. A tree-only fetch identifies the deployed
  # app without downloading the Flutter SDK or checking out production files.
  source_repo="$work_dir/source-git"
  git init -q "$source_repo"
  git -C "$source_repo" fetch -q --filter=blob:none --depth 1 https://github.com/PFfrank13/FacturaVoz.git "$VERCEL_GIT_COMMIT_SHA"
  git -C "$source_repo" update-ref HEAD "$VERCEL_GIT_COMMIT_SHA"
  fingerprint="$(source_fingerprint)"
fi
if [[ "${1:-}" == --pack ]]; then
  bundle="${2:?Indica la carpeta del build con marcadores públicos.}"
  [[ -n "$fingerprint" ]] || { echo 'No se pudo identificar el código de la web.' >&2; exit 1; }
  repo_dir="$(git -C "$backend_dir" rev-parse --show-toplevel)"
  git -C "$repo_dir" diff --quiet HEAD -- app/lib app/assets app/packages app/web app/pubspec.yaml app/pubspec.lock || {
    echo 'Guarda los cambios de la app en Git antes de empaquetar su build.' >&2; exit 1;
  }
  check_web "$bundle"
  node "$config_tool" verify "$bundle/main.dart.js"
  # Normalize archive headers and omit the build-host timestamp, caches and SDK.
  mkdir -p "$archive_dir"
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --exclude='./.last_build_id' -cf - -C "$bundle" . | gzip -n -9 > "$work_dir/client.tar.gz"
  mv "$work_dir/client.tar.gz" "$archive_dir/client.tar.gz"
  printf '%s\n' "$fingerprint" > "$archive_dir/source.sha256"
  (cd "$archive_dir" && sha256sum client.tar.gz > client.sha256)
  exit 0
fi

node "$config_tool" config "$work_dir/defines.json"
if [[ -n "$fingerprint" && -f "$archive_dir/source.sha256" && "$fingerprint" == "$(cat "$archive_dir/source.sha256")" ]]; then
  echo 'Usando el cliente web verificado para este código.'
  (cd "$archive_dir" && sha256sum -c client.sha256)
  mkdir "$work_dir/web"
  tar -xzf "$archive_dir/client.tar.gz" -C "$work_dir/web"
  check_web "$work_dir/web"
  node "$config_tool" bind "$work_dir/web/main.dart.js" "$work_dir/defines.json"
else
  echo 'El código de la app cambió. Compilando el cliente con el SDK fijado.'
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
  check_web "$work_dir/web"
fi

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
