#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

VERSION="latest"
REPOSITORY="${ZBXTABLE_REPOSITORY:-linguyuebai/zbxtable}"
INSTALL_ROOT="${ZBXTABLE_INSTALL_ROOT:-/opt/zbxtable}"
RUNTIME_ROOT="${ZBXTABLE_RUNTIME_ROOT:-/usr/local/zbxtable}"
FORCE=1
SKIP_CHECKSUM=0
SKIP_FRONTEND=0
INSTALL_DEPS=0
NO_START=0
DOCKER=0
DOCKER_INSTALL=0
DOCKER_PORT="${ZBXTABLE_HTTP_PORT:-8088}"
PORT_SET=0
ENV_READY=0
NO_FIREWALL=0
STEP=0
if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_CYAN=$'\033[36m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_CYAN=''; C_YELLOW=''; C_RESET=''
fi
fail() { printf '\033[31m[zbxtable] ERROR: %s\033[0m\n' "$*" >&2; exit 1; }
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<'EOF'
Usage: bash install-release.sh [options]
  --version=TAG       Release tag, default: latest
  --repository=ORG/REPO
  --install-root=PATH Default: /opt/zbxtable
  --runtime-root=PATH Default systemd runtime: /usr/local/zbxtable
  --install-deps       Install missing Linux packages and Go 1.24.0
  --force               Replace an existing install directory (default)
  --no-overwrite        Refuse to replace an existing install directory
  --skip-checksum       Skip SHA256 verification (not recommended)
  --skip-frontend       Do not build/download the frontend
  --no-start            Install but do not start the systemd service
  --docker              Install and run with Docker instead of systemd
  --docker-install      Install Docker if it is missing (apt-based Linux)
  --port=PORT           Web/Docker port (default: 8088)
  --no-firewall         Do not add the web port to an active firewall
EOF
      exit 0
      ;;
    --version=*) VERSION="${arg#*=}" ;;
    --repository=*) REPOSITORY="${arg#*=}" ;;
    --install-root=*) INSTALL_ROOT="${arg#*=}" ;;
    --runtime-root=*) RUNTIME_ROOT="${arg#*=}" ;;
    --force) FORCE=1 ;;
    --no-overwrite) FORCE=0 ;;
    --skip-checksum) SKIP_CHECKSUM=1 ;;
    --skip-frontend) SKIP_FRONTEND=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
    --no-start) NO_START=1 ;;
    --docker) DOCKER=1 ;;
    --docker-install) DOCKER=1; DOCKER_INSTALL=1 ;;
    --port=*) DOCKER_PORT="${arg#*=}"; PORT_SET=1 ;;
    --no-firewall) NO_FIREWALL=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ "$(id -u)" -eq 0 ]] || fail 'Run this installer as root (for example: curl ... | sudo bash -s -- ...).'
[[ "$DOCKER_PORT" =~ ^[0-9]+$ ]] && (( DOCKER_PORT >= 1 && DOCKER_PORT <= 65535 )) || fail "Invalid port: $DOCKER_PORT"

command -v curl >/dev/null 2>&1 || { echo 'Required command not found: curl' >&2; exit 1; }
TEMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

log() { printf '%s[zbxtable] %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
step() { STEP=$((STEP + 1)); printf '%s[%02d] %s%s\n' "$C_GREEN" "$STEP" "$*" "$C_RESET"; }
warn() { printf '%s[zbxtable] WARNING: %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }

configure_firewall() {
  local port="$1"
  [[ "$NO_FIREWALL" == 1 ]] && { warn 'Firewall update skipped (--no-firewall).'; return; }
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "$port/tcp" >/dev/null && log "UFW allowed TCP port $port" || warn "Could not update UFW for port $port"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$port/tcp" >/dev/null && firewall-cmd --reload >/dev/null && log "firewalld allowed TCP port $port" || warn "Could not update firewalld for port $port"
  else
    warn "No active UFW/firewalld detected; add TCP port $port to your firewall if needed."
  fi
}

if [[ "$INSTALL_DEPS" == 1 && "$DOCKER" != 1 ]]; then
  step 'Checking and preparing the Linux environment'
  BOOTSTRAP_URL="https://github.com/$REPOSITORY/releases/latest/download/bootstrap-linux.sh"
  [[ "$VERSION" == latest ]] || BOOTSTRAP_URL="https://github.com/$REPOSITORY/releases/download/$VERSION/bootstrap-linux.sh"
  log "Preparing Linux environment from $BOOTSTRAP_URL"
  curl -fsSL "$BOOTSTRAP_URL" -o "$TEMP_DIR/bootstrap-linux.sh" || fail 'Unable to download bootstrap-linux.sh.'
  chmod +x "$TEMP_DIR/bootstrap-linux.sh"
  bash "$TEMP_DIR/bootstrap-linux.sh"
  ENV_READY=1
fi

step 'Checking required commands and release metadata'
for command in tar sha256sum python3; do command -v "$command" >/dev/null 2>&1 || fail "Required command not found: $command"; done
if [[ "$VERSION" == latest ]]; then API_URL="https://api.github.com/repos/$REPOSITORY/releases/latest"; else API_URL="https://api.github.com/repos/$REPOSITORY/releases/tags/$VERSION"; fi
release_json="$TEMP_DIR/release.json"
log "Checking release metadata: $API_URL"
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
log "Release archive: $ARCHIVE_NAME"
BASE_URL="$(python3 - "$release_json" "$ARCHIVE_NAME" <<'PY'
import json, sys
data=json.load(open(sys.argv[1], encoding='utf-8'))
for asset in data.get('assets', []):
    if asset['name'] == sys.argv[2]: print(asset['browser_download_url']); break
PY
)"
ARCHIVE="$TEMP_DIR/$ARCHIVE_NAME"
step "Downloading $ARCHIVE_NAME"
curl -fL "$BASE_URL" -o "$ARCHIVE"
[[ -s "$ARCHIVE" ]] || fail 'Downloaded archive is empty.'
if [[ "$SKIP_CHECKSUM" != 1 ]]; then
  HASH_URL="${BASE_URL}.sha256"
  curl -fsSL "$HASH_URL" -o "$ARCHIVE.sha256" || { echo 'Release checksum is missing; refusing an unverified installation.' >&2; exit 1; }
  (cd "$TEMP_DIR" && sha256sum -c "$(basename "$ARCHIVE.sha256")")
  log 'SHA256 verification passed.'
else
  log 'WARNING: SHA256 verification skipped.'
fi

step 'Preparing the installation directory and preserving configuration'
if [[ -e "$INSTALL_ROOT" && "$FORCE" != 1 ]]; then echo "Install directory exists: $INSTALL_ROOT (use --force)." >&2; exit 1; fi
log "Installing to $INSTALL_ROOT"
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet zbxtable.service; then
  log 'Stopping existing zbxtable.service before replacement.'
  systemctl stop zbxtable.service
fi
if [[ -f "$RUNTIME_ROOT/config/app.conf" ]]; then cp -p "$RUNTIME_ROOT/config/app.conf" "$TEMP_DIR/app.conf.saved"; fi
if [[ ! -f "$TEMP_DIR/app.conf.saved" && -f "$INSTALL_ROOT/config/app.conf" ]]; then cp -p "$INSTALL_ROOT/config/app.conf" "$TEMP_DIR/app.conf.saved"; fi
rm -rf "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"
tar -xzf "$ARCHIVE" -C "$TEMP_DIR"
SOURCE_DIR="$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'zbxtable-*' | head -n 1)"
[[ -n "$SOURCE_DIR" ]] || { echo 'Archive has no zbxtable source directory.' >&2; exit 1; }
cp -a "$SOURCE_DIR"/. "$INSTALL_ROOT/"
for required_file in scripts/install.sh scripts/run.sh scripts/uninstall.sh scripts/install-docker.sh config/app.conf.example; do
  [[ -f "$INSTALL_ROOT/$required_file" ]] || fail "Release is missing required file: $required_file"
done
if [[ -f "$TEMP_DIR/app.conf.saved" ]]; then install -D -m 600 "$TEMP_DIR/app.conf.saved" "$INSTALL_ROOT/config/app.conf"; fi
if [[ "$PORT_SET" == 1 && "$DOCKER" != 1 ]]; then
  if grep -q '^httpport=' "$INSTALL_ROOT/config/app.conf"; then
    sed -i "s/^httpport=.*/httpport=$DOCKER_PORT/" "$INSTALL_ROOT/config/app.conf"
  else
    printf '\nhttpport=%s\n' "$DOCKER_PORT" >> "$INSTALL_ROOT/config/app.conf"
  fi
  log "Configured Web port: $DOCKER_PORT"
fi
if [[ "$DOCKER" == 1 ]]; then
  step 'Installing and starting Docker container'
  docker_args=("--port=$DOCKER_PORT")
  [[ "$DOCKER_INSTALL" == 1 ]] && docker_args+=(--install-docker)
  bash "$INSTALL_ROOT/scripts/install-docker.sh" "${docker_args[@]}"
  configure_firewall "$DOCKER_PORT"
  printf '\n%sZbxTable Docker installation complete%s\n' "$C_GREEN" "$C_RESET"
  printf '  Web:      http://%s:%s\n  Container: %s\n  Account:   admin\n  Password:  Zbxtable (first login; change it immediately)\n' "$(hostname -I 2>/dev/null | awk '{print $1}')" "$DOCKER_PORT" "${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}"
  exit 0
fi
if [[ "$SKIP_FRONTEND" != 1 && ! -s "$INSTALL_ROOT/api/v1/web/web/index.html" ]]; then
  log 'Release has no embedded frontend; installing frontend build prerequisites.'
  export ZBXTABLE_NEED_FRONTEND_BUILD=1
  bash "$INSTALL_ROOT/scripts/bootstrap-linux.sh"
  unset ZBXTABLE_NEED_FRONTEND_BUILD
fi
if [[ "$INSTALL_DEPS" == 1 && "$ENV_READY" != 1 ]]; then step 'Verifying Go and runtime dependencies'; bash "$INSTALL_ROOT/scripts/bootstrap-linux.sh"; fi
if [[ "$SKIP_FRONTEND" == 1 ]]; then export ZBXTABLE_SKIP_FRONTEND=1; fi
step 'Building the application and registering the systemd service'
export ZBXTABLE_RUNTIME_ROOT="$RUNTIME_ROOT"
bash "$INSTALL_ROOT/scripts/install.sh"
if [[ "$NO_START" != 1 && -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
  systemctl enable zbxtable.service >/dev/null 2>&1 || true
  systemctl start zbxtable.service
  if ! systemctl is-active --quiet zbxtable.service; then
    systemctl --no-pager --full status zbxtable.service || true
    journalctl -u zbxtable.service -n 80 --no-pager || true
    fail 'zbxtable.service did not start. See the service log above.'
  fi
  systemctl --no-pager --full status zbxtable.service
  HTTP_PORT="$(sed -n 's/^httpport=//p' "$RUNTIME_ROOT/config/app.conf" | head -n 1)"
  HTTP_PORT="${HTTP_PORT:-8088}"
  if command -v curl >/dev/null 2>&1; then
    healthy=0
    for attempt in $(seq 1 30); do
      if curl -fsS --max-time 2 "http://127.0.0.1:$HTTP_PORT/" | grep -qi '<html'; then healthy=1; break; fi
      sleep 1
    done
    [[ "$healthy" == 1 ]] || fail "Web interface health check failed: http://127.0.0.1:$HTTP_PORT/"
    log 'Web interface health check passed.'
  fi
  configure_firewall "$HTTP_PORT"
  printf '\n%sZbxTable installation complete%s\n' "$C_GREEN" "$C_RESET"
  printf '  Web:      http://%s:%s\n  Service:  zbxtable.service (enabled)\n  Account:  admin\n  Password: Zbxtable (first login; change it immediately)\n' "$(hostname -I 2>/dev/null | awk '{print $1}')" "$HTTP_PORT"
  log "Installation complete. Open http://127.0.0.1:$HTTP_PORT"
else
  log "Installation complete. Start with: bash $INSTALL_ROOT/scripts/run.sh"
fi
