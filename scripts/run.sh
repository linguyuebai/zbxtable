#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${ZBXTABLE_BIN:-$APP_DIR/build/zbxtable}"
[[ -x "$BIN" ]] || BIN="$APP_DIR/zbxtable"
[[ -x "$BIN" ]] || { printf 'Executable not found; run scripts/install.sh first.\n' >&2; exit 1; }

mkdir -p "$APP_DIR/log" "$APP_DIR/download" "$APP_DIR/upload"
cd "$APP_DIR"
exec "$BIN" web "$@"
