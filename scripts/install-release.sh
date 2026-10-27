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
REPAIR=0
DOCKER=0
DOCKER_INSTALL=0
DOCKER_PORT="${ZBXTABLE_HTTP_PORT:-8088}"
GO_IMAGE="${ZBXTABLE_GO_IMAGE:-golang:1.24-bookworm}"
RUNTIME_IMAGE="${ZBXTABLE_RUNTIME_IMAGE:-debian:bookworm-slim}"
GO_PROXY="${ZBXTABLE_GOPROXY:-https://goproxy.cn|https://proxy.golang.org|direct}"
GO_DOWNLOAD_BASE="${ZBXTABLE_GO_DOWNLOAD_BASE:-https://go.dev/dl}"
PORT_SET=0
ENV_READY=0
NO_FIREWALL=0
INTERACTIVE=0
MENU_PURGE=0
ASSUME_YES=0
STEP=0
SERVICE_WAS_ACTIVE=0
INSTALL_SUCCEEDED=0
if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_CYAN=$'\033[36m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_CYAN=''; C_YELLOW=''; C_RESET=''
fi
# Keep logging helpers before argument parsing and the interactive menu.  The
# repair menu emits diagnostics before the temporary directory is created; a
# late definition made `log` resolve as an external command on bash 5.
log() { printf '%s[zbxtable] %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
step() { STEP=$((STEP + 1)); printf '%s[%02d] %s%s\n' "$C_GREEN" "$STEP" "$*" "$C_RESET"; }
warn() { printf '%s[zbxtable] WARNING: %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
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
  --go-image=IMAGE      Docker Go builder image (allow a registry mirror)
  --runtime-image=IMAGE Docker runtime image (allow a registry mirror)
  --go-proxy=URLS       Go module proxy chain for source builds
  --go-download-base=URL Go archive mirror directory
  --no-firewall         Do not add the web port to an active firewall
  --menu                Show the interactive install/uninstall menu (default without options)
  --repair              Repair the current systemd or Docker installation using the latest release
  --uninstall           Uninstall systemd service and ZbxTable container
  --purge               With --uninstall, also remove saved configuration
  --yes                 With --uninstall, skip the confirmation prompt
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
    --go-image=*) GO_IMAGE="${arg#*=}" ;;
    --runtime-image=*) RUNTIME_IMAGE="${arg#*=}" ;;
    --go-proxy=*) GO_PROXY="${arg#*=}" ;;
    --go-download-base=*) GO_DOWNLOAD_BASE="${arg#*=}" ;;
    --no-firewall) NO_FIREWALL=1 ;;
    --menu) INTERACTIVE=1 ;;
    --repair) REPAIR=1 ;;
    --uninstall) ACTION=uninstall ;;
    --purge) MENU_PURGE=1 ;;
    --yes) ASSUME_YES=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$REPAIR" == 1 && "${ACTION:-}" != uninstall ]]; then
  VERSION=latest
  if [[ "$DOCKER" != 1 ]] && command -v docker >/dev/null 2>&1 && docker container inspect "${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}" >/dev/null 2>&1; then
    DOCKER=1
  fi
  if [[ "$DOCKER" != 1 ]]; then
    INSTALL_DEPS=1
  fi
fi

if [[ "$#" == 0 || "$INTERACTIVE" == 1 ]]; then
  [[ -r /dev/tty && -w /dev/tty ]] || fail 'Interactive menu needs a terminal. Run with --help and pass install options directly.'
  printf '\nZbxTable 安装管理器\n  1) 系统服务安装（systemd）\n  2) Docker 安装（缺少 Docker 时自动安装）\n  3) 修复当前安装（保留配置并使用最新 Release 重装）\n  4) 卸载 ZbxTable（系统服务和 Docker 容器）\n  5) 退出\n\n' > /dev/tty
  printf '请选择 [1-5]: ' > /dev/tty
  IFS= read -r MENU_CHOICE < /dev/tty || fail 'Could not read menu selection.'
  case "$MENU_CHOICE" in
    1) DOCKER=0; INSTALL_DEPS=1 ;;
    2) DOCKER=1; DOCKER_INSTALL=1 ;;
    3)
      REPAIR=1
      VERSION=latest
      if command -v docker >/dev/null 2>&1 && docker container inspect "${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}" >/dev/null 2>&1; then
        DOCKER=1
        log 'Detected existing Docker container; repair will rebuild and replace that container.'
      else
        DOCKER=0
        INSTALL_DEPS=1
        log 'Repair mode will rebuild and replace the systemd application while preserving configuration.'
      fi
      ;;
    4) ACTION=uninstall ;;
    5) printf '已退出。\n' > /dev/tty; exit 0 ;;
    *) fail 'Invalid selection. Choose 1, 2, 3, 4, or 5.' ;;
  esac
  if [[ "${ACTION:-}" == uninstall ]]; then
    printf '卸载选项：\n  1) 保留配置文件\n  2) 删除配置和程序文件\n请选择 [1-2]（默认 1）: ' > /dev/tty
    IFS= read -r PURGE_CHOICE < /dev/tty || fail 'Could not read uninstall selection.'
    case "$PURGE_CHOICE" in
      ''|1) MENU_PURGE=0 ;;
      2) MENU_PURGE=1 ;;
      *) fail 'Invalid selection. Choose 1 or 2.' ;;
    esac
    printf '卸载会停止并移除 ZbxTable systemd 服务及其 Docker 容器；不会删除 Zabbix 服务或数据库。输入 DELETE 确认: ' > /dev/tty
    IFS= read -r CONFIRM_UNINSTALL < /dev/tty || fail 'Could not read uninstall confirmation.'
    [[ "$CONFIRM_UNINSTALL" == DELETE ]] || { printf '已取消卸载。\n' > /dev/tty; exit 0; }
    ASSUME_YES=1
  elif [[ "$REPAIR" != 1 ]]; then
    printf '选择版本：\n  1) 最新正式 Release（latest）\n  2) 固定版本 v3.0.7\n  3) 输入其他版本标签\n请选择 [1-3]（默认 1）: ' > /dev/tty
    IFS= read -r MENU_VERSION_CHOICE < /dev/tty || fail 'Could not read version selection.'
    case "${MENU_VERSION_CHOICE:-1}" in
      1) VERSION=latest ;;
      2) VERSION=v3.0.7 ;;
      3)
        printf '请输入版本标签（例如 v3.0.7）: ' > /dev/tty
        IFS= read -r VERSION < /dev/tty || fail 'Could not read version tag.'
        [[ -n "$VERSION" ]] || fail 'Version tag cannot be empty.'
        ;;
      *) fail 'Invalid selection. Choose 1, 2, or 3.' ;;
    esac
    printf 'Web 端口 [默认 %s]: ' "$DOCKER_PORT" > /dev/tty
    IFS= read -r MENU_PORT < /dev/tty || fail 'Could not read port.'
    DOCKER_PORT="${MENU_PORT:-$DOCKER_PORT}"
    PORT_SET=1
    if [[ "$DOCKER" == 1 ]]; then
      printf 'Go 构建镜像 [默认 %s；可填内网镜像地址]: ' "$GO_IMAGE" > /dev/tty
      IFS= read -r MENU_GO_IMAGE < /dev/tty || fail 'Could not read Go builder image.'
      GO_IMAGE="${MENU_GO_IMAGE:-$GO_IMAGE}"
      printf '运行时镜像 [默认 %s；可填内网镜像地址]: ' "$RUNTIME_IMAGE" > /dev/tty
      IFS= read -r MENU_RUNTIME_IMAGE < /dev/tty || fail 'Could not read runtime image.'
      RUNTIME_IMAGE="${MENU_RUNTIME_IMAGE:-$RUNTIME_IMAGE}"
      printf 'Go 模块代理 [默认 %s]: ' "$GO_PROXY" > /dev/tty
      IFS= read -r MENU_GO_PROXY < /dev/tty || fail 'Could not read Go module proxy.'
      GO_PROXY="${MENU_GO_PROXY:-$GO_PROXY}"
    fi
  fi
fi

if [[ "${ACTION:-}" == uninstall && "$INTERACTIVE" != 1 && "$ASSUME_YES" != 1 ]]; then
  [[ -r /dev/tty && -w /dev/tty ]] || fail 'Uninstall needs a terminal confirmation. Use --yes to confirm explicitly in automation.'
  printf '卸载将移除 ZbxTable systemd 服务、Docker 容器和程序文件，不会删除 Zabbix 或共享数据库。' > /dev/tty
  [[ "$MENU_PURGE" == 1 ]] && printf ' 同时删除 ZbxTable 配置。' > /dev/tty
  printf '\n输入 DELETE 确认: ' > /dev/tty
  IFS= read -r CONFIRM_UNINSTALL < /dev/tty || fail 'Could not read uninstall confirmation.'
  [[ "$CONFIRM_UNINSTALL" == DELETE ]] || { printf '已取消卸载。\n' > /dev/tty; exit 0; }
  ASSUME_YES=1
fi

[[ "$(id -u)" -eq 0 ]] || fail 'Run this installer as root (for example: curl ... | sudo bash -s -- ...).'
[[ "$DOCKER_PORT" =~ ^[0-9]+$ ]] && (( DOCKER_PORT >= 1 && DOCKER_PORT <= 65535 )) || fail "Invalid port: $DOCKER_PORT"
export ZBXTABLE_GOPROXY="$GO_PROXY"
export ZBXTABLE_GO_DOWNLOAD_BASE="$GO_DOWNLOAD_BASE"

command -v curl >/dev/null 2>&1 || { echo 'Required command not found: curl' >&2; exit 1; }
TEMP_DIR="$(mktemp -d)"
cleanup() {
  local exit_code=$?
  rm -rf "$TEMP_DIR"
  if [[ "$SERVICE_WAS_ACTIVE" == 1 && "$INSTALL_SUCCEEDED" != 1 ]]; then
    systemctl start zbxtable.service >/dev/null 2>&1 || true
    printf '[zbxtable] WARNING: installation did not finish; attempted to restore the previously running service.\n' >&2
  fi
  return "$exit_code"
}
trap cleanup EXIT

check_frontend_assets() {
  local base_url="$1" index_file="$TEMP_DIR/frontend-index.html" asset_path asset_file
  curl -fsS --max-time 5 "$base_url/" -o "$index_file" || return 1
  asset_path="$(sed -n 's/.*src=[\"'"'"']\([^\"'"'"']*\.js\)[\"'"'"'].*/\1/p' "$index_file" | head -n 1)"
  [[ -n "$asset_path" ]] || return 1
  [[ "$asset_path" == /* ]] || asset_path="/$asset_path"
  asset_file="$TEMP_DIR/frontend-asset.js"
  curl -fsS --max-time 5 "$base_url$asset_path" -o "$asset_file" || return 1
  [[ -s "$asset_file" ]] || return 1
  ! grep -qiE '<!doctype|<html[ >]' "$asset_file"
}

if [[ "${ACTION:-}" == uninstall ]]; then
  step 'Downloading the verified release uninstaller'
  if [[ "$VERSION" == latest ]]; then UNINSTALL_URL="https://github.com/$REPOSITORY/releases/latest/download/uninstall.sh"; else UNINSTALL_URL="https://github.com/$REPOSITORY/releases/download/$VERSION/uninstall.sh"; fi
  curl -fsSL "$UNINSTALL_URL" -o "$TEMP_DIR/uninstall.sh" || fail "Unable to download uninstaller: $UNINSTALL_URL"
  chmod 700 "$TEMP_DIR/uninstall.sh"
  uninstall_args=("--install-root=$INSTALL_ROOT" "--runtime-root=$RUNTIME_ROOT")
  [[ "$MENU_PURGE" == 1 ]] && uninstall_args+=(--purge)
  [[ "$ASSUME_YES" == 1 || "$INTERACTIVE" == 1 ]] && uninstall_args+=(--yes)
  bash "$TEMP_DIR/uninstall.sh" "${uninstall_args[@]}"
  exit $?
fi

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
  SERVICE_WAS_ACTIVE=1
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
  export ZBXTABLE_HTTP_PORT="$DOCKER_PORT"
  if [[ -f "$INSTALL_ROOT/config/app.conf" ]]; then
    if grep -q '^httpport=' "$INSTALL_ROOT/config/app.conf"; then
      sed -i "s/^httpport=.*/httpport=$DOCKER_PORT/" "$INSTALL_ROOT/config/app.conf"
    else
      printf '\nhttpport=%s\n' "$DOCKER_PORT" >> "$INSTALL_ROOT/config/app.conf"
    fi
  else
    log "No saved configuration found; the first-run setup will use Web port $DOCKER_PORT."
  fi
  log "Configured Web port: $DOCKER_PORT"
fi
if [[ "$DOCKER" == 1 ]]; then
  if [[ "$REPAIR" == 1 && "$PORT_SET" != 1 ]] && command -v docker >/dev/null 2>&1; then
    detected_port="$(docker port "${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}" 8088/tcp 2>/dev/null | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | head -n 1)"
    if [[ "$detected_port" =~ ^[0-9]+$ ]]; then
      DOCKER_PORT="$detected_port"
      log "Detected existing Docker Web port: $DOCKER_PORT"
    fi
  fi
  step 'Installing and starting Docker container'
  docker_args=("--port=$DOCKER_PORT")
  docker_args+=("--go-image=$GO_IMAGE" "--runtime-image=$RUNTIME_IMAGE" "--go-proxy=$GO_PROXY")
  [[ "$DOCKER_INSTALL" == 1 ]] && docker_args+=(--install-docker)
  bash "$INSTALL_ROOT/scripts/install-docker.sh" "${docker_args[@]}"
  if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled --quiet zbxtable.service 2>/dev/null; then
    systemctl disable zbxtable.service >/dev/null 2>&1 || warn 'Could not disable the previous systemd installation.'
  fi
  configure_firewall "$DOCKER_PORT"
  printf '\n%sZbxTable Docker installation complete%s\n' "$C_GREEN" "$C_RESET"
  printf '  Web:      http://%s:%s\n  Container: %s\n  Account:   admin\n  Password:  Zbxtable (first login; change it immediately)\n' "$(hostname -I 2>/dev/null | awk '{print $1}')" "$DOCKER_PORT" "${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}"
  INSTALL_SUCCEEDED=1
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
    check_frontend_assets "http://127.0.0.1:$HTTP_PORT" || fail "Frontend asset health check failed: JavaScript files are not being served correctly on port $HTTP_PORT."
    log 'Web interface health check passed.'
  fi
  configure_firewall "$HTTP_PORT"
  INSTALL_SUCCEEDED=1
  printf '\n%sZbxTable installation complete%s\n' "$C_GREEN" "$C_RESET"
  printf '  Web:      http://%s:%s\n  Service:  zbxtable.service (enabled)\n  Account:  admin\n  Password: Zbxtable (first login; change it immediately)\n' "$(hostname -I 2>/dev/null | awk '{print $1}')" "$HTTP_PORT"
  log "Installation complete. Open http://127.0.0.1:$HTTP_PORT"
else
  INSTALL_SUCCEEDED=1
  log "Installation complete. Start with: bash $INSTALL_ROOT/scripts/run.sh"
fi
