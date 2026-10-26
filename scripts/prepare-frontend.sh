#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMBED_DIR="$ROOT_DIR/api/v1/web/web"
WEB_DIR="${ZBXTABLE_WEB_DIR:-}"
WEB_REPO="${ZBXTABLE_WEB_REPO:-https://github.com/canghai908/zbxtable-web.git}"
WEB_REF="${ZBXTABLE_WEB_REF:-3.0}"
TEMP_DIR=""
cleanup() { [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

if [[ "${ZBXTABLE_SKIP_FRONTEND:-0}" == "1" ]]; then
  echo 'Skipping frontend build (ZBXTABLE_SKIP_FRONTEND=1).'
  exit 0
fi
if [[ -f "$EMBED_DIR/index.html" ]]; then
  echo "Embedded frontend already exists: $EMBED_DIR"
  exit 0
fi

for candidate in "$ROOT_DIR/../zbxtable-web" "$ROOT_DIR/../zbxtable-web-master/zbxtable-web-master"; do
  if [[ -z "$WEB_DIR" && -f "$candidate/package.json" ]]; then WEB_DIR="$candidate"; fi
done
if [[ -z "$WEB_DIR" ]]; then
  command -v git >/dev/null 2>&1 || { echo 'Git is required to download the frontend. Set ZBXTABLE_WEB_DIR or use ZBXTABLE_SKIP_FRONTEND=1.' >&2; exit 1; }
  TEMP_DIR="$(mktemp -d)"
  echo "Downloading frontend: $WEB_REPO ($WEB_REF)"
  if ! git clone --depth 1 --branch "$WEB_REF" "$WEB_REPO" "$TEMP_DIR/web" 2>/dev/null; then
    git clone --depth 1 "$WEB_REPO" "$TEMP_DIR/web"
  fi
  WEB_DIR="$TEMP_DIR/web"
fi
[[ -f "$WEB_DIR/package.json" ]] || { echo "Frontend package.json not found: $WEB_DIR" >&2; exit 1; }
cd "$WEB_DIR"
if command -v yarn >/dev/null 2>&1 && [[ -f yarn.lock ]]; then
  yarn install --frozen-lockfile
  yarn build
else
  npm ci
  npm run build
fi
if [[ -d "$WEB_DIR/web" ]]; then OUTPUT_DIR="$WEB_DIR/web"
elif [[ -d "$WEB_DIR/app/build" ]]; then OUTPUT_DIR="$WEB_DIR/app/build"
else echo 'Frontend build completed but neither web nor app/build was found.' >&2; exit 1; fi

TEMP_OUTPUT="$(mktemp -d)"
cp -R "$OUTPUT_DIR/." "$TEMP_OUTPUT/"
rm -rf "$EMBED_DIR"
mkdir -p "$EMBED_DIR"
cp -R "$TEMP_OUTPUT/." "$EMBED_DIR/"
rm -rf "$TEMP_OUTPUT"
echo "Frontend embedded: $EMBED_DIR"
