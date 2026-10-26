#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="latest"
REPOSITORY="${ZBXTABLE_REPOSITORY:-canghai908/zbxtable}"
INSTALL_ROOT="${ZBXTABLE_INSTALL_ROOT:-/opt/zbxtable}"
FORCE=0
SKIP_CHECKSUM=0
SKIP_FRONTEND=0
INSTALL_DEPS=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'EOF'
Usage: bash install-release.sh [options]
  --version=TAG       Release tag, default: latest
  --repository=ORG/REPO
  --install-root=PATH Default: /opt/zbxtable
  --install-deps       Install missing Linux packages and Go 1.24.0
  --force               Replace an existing install directory
  --skip-checksum       Skip SHA256 verification (not recommended)
  --skip-frontend       Do not build/download the frontend
EOF
      exit 0
      ;;
    --version=*) VERSION="${arg#*=}" ;;
    --repository=*) REPOSITORY="${arg#*=}" ;;
    --install-root=*) INSTALL_ROOT="${arg#*=}" ;;
    --force) FORCE=1 ;;
    --skip-checksum) SKIP_CHECKSUM=1 ;;
    --skip-frontend) SKIP_FRONTEND=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

for command in curl tar sha256sum python3; do command -v "$command" >/dev/null 2>&1 || { echo "Required command not found: $command" >&2; exit 1; }; done
if [[ "$VERSION" == latest ]]; then API_URL="https://api.github.com/repos/$REPOSITORY/releases/latest"; else API_URL="https://api.github.com/repos/$REPOSITORY/releases/tags/$VERSION"; fi
TEMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT
release_json="$TEMP_DIR/release.json"
curl -fsSL -H 'User-Agent: zbxtable-installer' "$API_URL" -o "$release_json"
ARCHIVE_NAME="$(python3 - "$release_json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1], encoding='utf-8'))
for asset in data.get('assets', []):
    if asset['name'].endswith('-source.tar.gz'):
        print(asset['name']); break
PY
)"
[[ -n "$ARCHIVE_NAME" ]] || { echo 'No source tar.gz asset found in the release.' >&2; exit 1; }
BASE_URL="$(python3 - "$release_json" "$ARCHIVE_NAME" <<'PY'
import json, sys
data=json.load(open(sys.argv[1], encoding='utf-8'))
for asset in data.get('assets', []):
    if asset['name'] == sys.argv[2]: print(asset['browser_download_url']); break
PY
)"
ARCHIVE="$TEMP_DIR/$ARCHIVE_NAME"
curl -fL "$BASE_URL" -o "$ARCHIVE"
if [[ "$SKIP_CHECKSUM" != 1 ]]; then
  HASH_URL="${BASE_URL}.sha256"
  curl -fsSL "$HASH_URL" -o "$ARCHIVE.sha256" || { echo 'Release checksum is missing; refusing an unverified installation.' >&2; exit 1; }
  (cd "$TEMP_DIR" && sha256sum -c "$(basename "$ARCHIVE.sha256")")
fi

if [[ -e "$INSTALL_ROOT" && "$FORCE" != 1 ]]; then echo "Install directory exists: $INSTALL_ROOT (use --force)." >&2; exit 1; fi
if [[ -e "$INSTALL_ROOT/config/app.conf" ]]; then cp "$INSTALL_ROOT/config/app.conf" "$TEMP_DIR/app.conf.saved"; fi
rm -rf "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"
tar -xzf "$ARCHIVE" -C "$TEMP_DIR"
SOURCE_DIR="$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'zbxtable-*' | head -n 1)"
[[ -n "$SOURCE_DIR" ]] || { echo 'Archive has no zbxtable source directory.' >&2; exit 1; }
cp -a "$SOURCE_DIR"/. "$INSTALL_ROOT/"
if [[ -f "$TEMP_DIR/app.conf.saved" ]]; then install -D -m 600 "$TEMP_DIR/app.conf.saved" "$INSTALL_ROOT/config/app.conf"; fi
if [[ "$INSTALL_DEPS" == 1 ]]; then bash "$INSTALL_ROOT/scripts/bootstrap-linux.sh"; fi
if [[ "$SKIP_FRONTEND" == 1 ]]; then export ZBXTABLE_SKIP_FRONTEND=1; fi
bash "$INSTALL_ROOT/scripts/install.sh"
echo "ZbxTable installed to $INSTALL_ROOT"
