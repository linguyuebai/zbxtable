#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${ZBXTABLE_DOCKER_IMAGE:-zbxtable:3.0.7}"
CONTAINER="${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}"
PORT="${ZBXTABLE_HTTP_PORT:-8088}"
GO_IMAGE="${ZBXTABLE_GO_IMAGE:-golang:1.24-bookworm}"
RUNTIME_IMAGE="${ZBXTABLE_RUNTIME_IMAGE:-debian:bookworm-slim}"
GO_PROXY="${ZBXTABLE_GOPROXY:-https://goproxy.cn|https://proxy.golang.org|direct}"
APP_UID=10001
CONFIG_DIR="${ZBXTABLE_DOCKER_CONFIG:-$ROOT_DIR/config}"
INSTALL_DOCKER=0
log() { printf '[zbxtable-docker] %s\n' "$*"; }
fail() { printf '[zbxtable-docker] ERROR: %s\n' "$*" >&2; exit 1; }
check_frontend_assets() {
  local base_url="http://127.0.0.1:$PORT" index_file asset_path asset_file
  index_file="$(mktemp)"
  asset_file="$(mktemp)"
  if ! curl -fsS --max-time 5 "$base_url/" -o "$index_file"; then
    rm -f "$index_file" "$asset_file"
    return 1
  fi
  asset_path="$(sed -n 's/.*src=[\"'"'"']\([^\"'"'"']*\.js\)[\"'"'"'].*/\1/p' "$index_file" | head -n 1)"
  if [[ -z "$asset_path" ]]; then
    rm -f "$index_file" "$asset_file"
    return 1
  fi
  [[ "$asset_path" == /* ]] || asset_path="/$asset_path"
  if ! curl -fsS --max-time 5 "$base_url$asset_path" -o "$asset_file"; then
    rm -f "$index_file" "$asset_file"
    return 1
  fi
  [[ -s "$asset_file" ]] && ! grep -qiE '<!doctype|<html[ >]' "$asset_file"
  local result=$?
  rm -f "$index_file" "$asset_file"
  return "$result"
}
configure_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "$1/tcp" >/dev/null || log "WARNING: could not update UFW for port $1"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$1/tcp" >/dev/null && firewall-cmd --reload >/dev/null || log "WARNING: could not update firewalld for port $1"
  else
    log "WARNING: no active UFW/firewalld detected; allow TCP port $1 manually if required."
  fi
}
for arg in "$@"; do
  case "$arg" in
    --port=*) PORT="${arg#*=}" ;;
    --image=*) IMAGE="${arg#*=}" ;;
    --container=*) CONTAINER="${arg#*=}" ;;
    --config=*) CONFIG_DIR="${arg#*=}" ;;
    --go-image=*) GO_IMAGE="${arg#*=}" ;;
    --runtime-image=*) RUNTIME_IMAGE="${arg#*=}" ;;
    --go-proxy=*) GO_PROXY="${arg#*=}" ;;
    --install-docker) INSTALL_DOCKER=1 ;;
    -h|--help) echo 'Usage: sudo bash scripts/install-docker.sh [--install-docker] [--port=8088] [--go-image=IMAGE] [--runtime-image=IMAGE] [--go-proxy=URLS]'; exit 0 ;;
    *) fail "Unknown option: $arg" ;;
  esac
done
[[ "$(id -u)" -eq 0 ]] || fail 'Run the Docker installer as root (use sudo).'
if ! command -v docker >/dev/null 2>&1; then
  [[ "$INSTALL_DOCKER" == 1 ]] || fail 'Docker is not installed. Re-run with --install-docker.'
  [[ "$(id -u)" -eq 0 ]] || fail '--install-docker must run as root.'
  command -v apt-get >/dev/null 2>&1 || fail 'Automatic Docker installation supports apt-based Linux.'
  . /etc/os-release
  distro="${ID:-}"
  case "$distro" in
    ubuntu|debian) ;;
    *) fail "Automatic Docker installation supports Ubuntu/Debian; detected: ${distro:-unknown}" ;;
  esac
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$distro/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  codename="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo noble)}"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' "$(dpkg --print-architecture)" "$distro" "$codename" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker 2>/dev/null || true
fi
command -v docker >/dev/null 2>&1 || fail 'Docker command is unavailable.'
docker info >/dev/null 2>&1 || fail 'Docker daemon is not running.'
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || fail "Invalid port: $PORT"
[[ -f "$ROOT_DIR/deployments/docker/Dockerfile.release" ]] || fail 'Dockerfile.release is missing.'
[[ -s "$ROOT_DIR/api/v1/web/web/index.html" ]] || fail 'Embedded frontend is missing from this release.'
mkdir -p "$CONFIG_DIR" "$ROOT_DIR/log" "$ROOT_DIR/download" "$ROOT_DIR/upload"
if [[ ! -f "$CONFIG_DIR/app.conf" ]]; then cp "$CONFIG_DIR/app.conf.example" "$CONFIG_DIR/app.conf"; chmod 600 "$CONFIG_DIR/app.conf"; fi
if grep -q '^dbpass=change-me$' "$CONFIG_DIR/app.conf" 2>/dev/null; then
  DB_TYPE="${ZBXTABLE_DB_TYPE:-mysql}"
  DB_HOST="${ZBXTABLE_DB_HOST:-127.0.0.1}"
  DB_PORT="${ZBXTABLE_DB_PORT:-3306}"
  DB_NAME="${ZBXTABLE_DB_NAME:-zabbix}"
  DB_USER="${ZBXTABLE_DB_USER:-zabbix}"
  DB_PASS="${ZBXTABLE_DB_PASS:-}"
  if [[ -z "$DB_PASS" ]]; then
    [[ -r /dev/tty && -w /dev/tty ]] || fail 'Database password is required; set ZBXTABLE_DB_PASS or run from an interactive terminal.'
    read -r -s -p 'Zabbix database password: ' DB_PASS < /dev/tty
    printf '\n'
  fi
  [[ -n "$DB_PASS" ]] || fail 'Database password cannot be empty.'
  cat > "$CONFIG_DIR/app.conf" <<EOF
httpport=8088
runmode=prod
timeout=12
log_level=3
log_path=log
maxlines=1000
maxsize=0
maxdays=10
daily=true
dbtype=$DB_TYPE
dbhost=$DB_HOST
dbuser=$DB_USER
dbpass=$DB_PASS
dbname=$DB_NAME
dbport=$DB_PORT
EOF
  chmod 600 "$CONFIG_DIR/app.conf"
fi
# The app always listens on 8088 inside the container; only the host-side port varies.
if grep -q '^httpport=' "$CONFIG_DIR/app.conf"; then
  sed -i 's/^httpport=.*/httpport=8088/' "$CONFIG_DIR/app.conf"
else
  printf '\nhttpport=8088\n' >> "$CONFIG_DIR/app.conf"
fi
log "Building image $IMAGE (Go base: $GO_IMAGE; runtime base: $RUNTIME_IMAGE)"
if ! docker build \
  --build-arg "GO_IMAGE=$GO_IMAGE" \
  --build-arg "RUNTIME_IMAGE=$RUNTIME_IMAGE" \
  --build-arg "APP_UID=$APP_UID" \
  --build-arg "GOPROXY=$GO_PROXY" \
  -f "$ROOT_DIR/deployments/docker/Dockerfile.release" -t "$IMAGE" "$ROOT_DIR"; then
  fail "Docker image build failed. Check access to the configured base image registries and Go proxy. You can retry with --go-image, --runtime-image and --go-proxy mirror options."
fi
chown -R "$APP_UID:$APP_UID" "$CONFIG_DIR" "$ROOT_DIR/log" "$ROOT_DIR/download" "$ROOT_DIR/upload"
chmod 0600 "$CONFIG_DIR/app.conf"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart unless-stopped -p "$PORT:8088" -v "$CONFIG_DIR:/app/config" -v "$ROOT_DIR/log:/app/log" -v "$ROOT_DIR/download:/app/download" -v "$ROOT_DIR/upload:/app/upload" "$IMAGE" >/dev/null
attempt=1
while (( attempt <= 30 )); do
  if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" | grep -qi '<html'; then
    check_frontend_assets || fail "Frontend asset health check failed: JavaScript files are not being served correctly on port $PORT."
    configure_firewall "$PORT"
    log "Installation complete: http://127.0.0.1:$PORT"
    log "Logs: docker logs -f $CONTAINER"
    exit 0
  fi
  sleep 1
  attempt=$((attempt + 1))
done
docker logs "$CONTAINER" || true
fail "Web health check failed: http://127.0.0.1:$PORT/"
