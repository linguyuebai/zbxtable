#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${ZBXTABLE_DOCKER_IMAGE:-zbxtable:3.0.7}"
CONTAINER="${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}"
PORT="${ZBXTABLE_HTTP_PORT:-8088}"
CONFIG_DIR="${ZBXTABLE_DOCKER_CONFIG:-$ROOT_DIR/config}"
INSTALL_DOCKER=0
log() { printf '[zbxtable-docker] %s\n' "$*"; }
fail() { printf '[zbxtable-docker] ERROR: %s\n' "$*" >&2; exit 1; }
for arg in "$@"; do
  case "$arg" in
    --port=*) PORT="${arg#*=}" ;;
    --image=*) IMAGE="${arg#*=}" ;;
    --container=*) CONTAINER="${arg#*=}" ;;
    --config=*) CONFIG_DIR="${arg#*=}" ;;
    --install-docker) INSTALL_DOCKER=1 ;;
    -h|--help) echo 'Usage: sudo bash scripts/install-docker.sh [--install-docker] [--port=8088]'; exit 0 ;;
    *) fail "Unknown option: $arg" ;;
  esac
done
if ! command -v docker >/dev/null 2>&1; then
  [[ "$INSTALL_DOCKER" == 1 ]] || fail 'Docker is not installed. Re-run with --install-docker.'
  [[ "$(id -u)" -eq 0 ]] || fail '--install-docker must run as root.'
  command -v apt-get >/dev/null 2>&1 || fail 'Automatic Docker installation supports apt-based Linux.'
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  distro="${ID:-ubuntu}"
  [[ "$distro" == ubuntu || "$distro" == debian ]] || distro=ubuntu
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
sed -i "s/^httpport=.*/httpport=$PORT/" "$CONFIG_DIR/app.conf" 2>/dev/null || true
log "Building image $IMAGE"
docker build -f "$ROOT_DIR/deployments/docker/Dockerfile.release" -t "$IMAGE" "$ROOT_DIR"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart unless-stopped -p "$PORT:8088" -v "$CONFIG_DIR:/app/config" -v "$ROOT_DIR/log:/app/log" -v "$ROOT_DIR/download:/app/download" -v "$ROOT_DIR/upload:/app/upload" "$IMAGE" >/dev/null
attempt=1
while (( attempt <= 30 )); do
  if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" | grep -qi '<html'; then
    log "Installation complete: http://127.0.0.1:$PORT"
    log "Logs: docker logs -f $CONTAINER"
    exit 0
  fi
  sleep 1
  attempt=$((attempt + 1))
done
docker logs "$CONTAINER" || true
fail "Web health check failed: http://127.0.0.1:$PORT/"
