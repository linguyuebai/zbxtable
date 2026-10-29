#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${ZBXTABLE_VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)}"
SAFE_VERSION="${VERSION//\//-}"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$(mktemp -d)"
PACKAGE_DIR="$STAGE_DIR/zbxtable-$SAFE_VERSION"
RELEASE_DIR="$DIST_DIR/zbxtable-$SAFE_VERSION"
ARCHIVE="$DIST_DIR/zbxtable-$SAFE_VERSION-source.tar.gz"
cleanup() { rm -rf "$STAGE_DIR"; }
trap cleanup EXIT

mkdir -p "$PACKAGE_DIR" "$DIST_DIR"
cd "$ROOT_DIR"

# Include tracked and untracked files, while respecting .gitignore.
git ls-files -co --exclude-standard -z | while IFS= read -r -d '' file; do
  [[ "$file" == dist/* || "$file" == build/* || "$file" == config/app.conf ]] && continue
  if [[ ! -e "$file" ]]; then
    printf 'WARNING: missing file skipped: %s\n' "$file" >&2
    continue
  fi
  mkdir -p "$PACKAGE_DIR/$(dirname "$file")"
  cp -p "$file" "$PACKAGE_DIR/$file"
done

# Include an existing frontend bundle when one was built locally. The bundle
# is ignored by Git, but a Linux source archive can still be self-contained.
if [[ -f "$ROOT_DIR/api/v1/web/web/index.html" ]]; then
  mkdir -p "$PACKAGE_DIR/api/v1/web/web"
  cp -R "$ROOT_DIR/api/v1/web/web/." "$PACKAGE_DIR/api/v1/web/web/"
fi

# Source files copied from a Windows checkout may have CRLF endings. Keep
# bundled shell scripts executable by Bash on Linux regardless of packager OS.
find "$PACKAGE_DIR" -type f -name '*.sh' -exec sed -i 's/\r$//' {} +

cat > "$PACKAGE_DIR/RELEASE-MANIFEST.txt" <<EOF
ZbxTable release: $VERSION
Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Contents: source code, documentation, installation scripts, example configuration
Database: uses the existing Zabbix database; runtime config is intentionally excluded
EOF

rm -rf "$RELEASE_DIR"
cp -a "$PACKAGE_DIR" "$RELEASE_DIR"

tar -C "$STAGE_DIR" -czf "$ARCHIVE" "zbxtable-$SAFE_VERSION"
(cd "$DIST_DIR" && sha256sum "$(basename "$ARCHIVE")") > "$ARCHIVE.sha256"
printf 'Created: %s\nChecksum: %s\n' "$ARCHIVE" "$ARCHIVE.sha256"
