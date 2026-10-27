#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="zbxtable"
BUILD_DIR="$APP_DIR/build"
CONFIG_DIR="$APP_DIR/config"
CONFIG_FILE="$CONFIG_DIR/app.conf"
RUNTIME_ROOT="${ZBXTABLE_RUNTIME_ROOT:-/usr/local/zbxtable}"

log() { printf '[zbxtable] %s\n' "$*"; }
fail() { printf '[zbxtable] ERROR: %s\n' "$*" >&2; exit 1; }

# Do not let Go silently fetch a different toolchain than the one installed.
export GOTOOLCHAIN=local
export GOPROXY="${ZBXTABLE_GOPROXY:-https://goproxy.cn|https://proxy.golang.org|direct}"

if [[ "${ZBXTABLE_INSTALL_DEPS:-0}" == "1" ]]; then
  bash "$APP_DIR/scripts/bootstrap-linux.sh"
fi

command -v go >/dev/null 2>&1 || fail 'Go 1.24 or newer is required.'

GO_VERSION="$(go version | awk '{print $3}' | sed 's/^go//')"
GO_MAJOR="${GO_VERSION%%.*}"
GO_REST="${GO_VERSION#*.}"
GO_MINOR="${GO_REST%%.*}"
if [[ "${GO_MAJOR:-0}" -lt 1 || ( "${GO_MAJOR:-0}" -eq 1 && "${GO_MINOR:-0}" -lt 24 ) ]]; then
  fail "Go $GO_VERSION is too old; Go 1.24 or newer is required."
fi
log "Environment check passed: $(uname -s) $(uname -m), Go $GO_VERSION"

check_port() {
  local host="$1" port="$2" label="$3"
  if command -v timeout >/dev/null 2>&1 && timeout 3 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1; then
    log "$label reachable: $host:$port"
  else
    log "WARNING: could not reach $label at $host:$port; installation continues."
  fi
}

if [[ -f "$CONFIG_FILE" && "${FORCE_CONFIG:-0}" != "1" ]]; then
  log "Existing configuration found; keeping $CONFIG_FILE"
  HTTP_PORT="$(sed -n 's/^httpport=//p' "$CONFIG_FILE" | head -n 1)"
  HTTP_PORT="${HTTP_PORT:-8088}"
else
  DB_TYPE="${ZBXTABLE_DB_TYPE:-mysql}"
  DB_HOST="${ZBXTABLE_DB_HOST:-127.0.0.1}"
  DB_PORT="${ZBXTABLE_DB_PORT:-3306}"
  DB_NAME="${ZBXTABLE_DB_NAME:-zabbix}"
  DB_USER="${ZBXTABLE_DB_USER:-zabbix}"
  DB_PASS="${ZBXTABLE_DB_PASS:-}"
  HTTP_PORT="${ZBXTABLE_HTTP_PORT:-8088}"
  RUN_MODE="${ZBXTABLE_RUN_MODE:-prod}"

  if [[ -z "$DB_PASS" ]]; then
    [[ -r /dev/tty && -w /dev/tty ]] || fail 'Database password is required; set ZBXTABLE_DB_PASS or run from an interactive terminal.'
    read -r -s -p 'Zabbix database password: ' DB_PASS < /dev/tty
    printf '\n'
  fi
  [[ -n "$DB_PASS" ]] || fail 'Database password cannot be empty.'

  check_port "$DB_HOST" "$DB_PORT" 'database'
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
httpport=$HTTP_PORT
runmode=$RUN_MODE
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
  chmod 600 "$CONFIG_FILE"
  log "Wrote shared-database configuration: $DB_TYPE $DB_HOST:$DB_PORT/$DB_NAME"
fi

mkdir -p "$BUILD_DIR" "$APP_DIR/log" "$APP_DIR/download" "$APP_DIR/upload"
if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$HTTP_PORT" | grep -q ":$HTTP_PORT"; then
  if command -v systemctl >/dev/null 2>&1 && [[ "$(id -u)" -eq 0 ]] && systemctl is-active --quiet zbxtable.service; then
    log 'Stopping the existing zbxtable service before reinstalling.'
    systemctl stop zbxtable.service
    sleep 1
  else
    fail "HTTP port $HTTP_PORT is already in use; choose another port. Existing Zabbix services are not modified."
  fi
fi

cd "$APP_DIR"
if [[ -s "$APP_DIR/api/v1/web/web/index.html" ]]; then
  log 'Embedded frontend found; skipping frontend build.'
elif [[ "${ZBXTABLE_SKIP_FRONTEND:-0}" != "1" ]]; then
  bash "$APP_DIR/scripts/prepare-frontend.sh"
  [[ -s "$APP_DIR/api/v1/web/web/index.html" ]] || fail 'Frontend index.html is missing after preparation.'
fi
log "Downloading Go dependencies (GOPROXY=$GOPROXY)"
if ! go mod download; then
  fail "Go dependency download failed. Check server network/DNS or configure ZBXTABLE_GOPROXY (current: $GOPROXY), then rerun the installer."
fi
log "Building $APP_NAME"
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$BUILD_DIR/$APP_NAME" ./main.go
chmod +x "$BUILD_DIR/$APP_NAME"
[[ -x "$BUILD_DIR/$APP_NAME" ]] || fail "Build output was not created: $BUILD_DIR/$APP_NAME"

if command -v systemctl >/dev/null 2>&1 && [[ "$(id -u)" -eq 0 ]]; then
  log 'Registering systemd service'
  if ! id zbxtable >/dev/null 2>&1; then
    useradd --system --home-dir "$RUNTIME_ROOT" --shell /usr/sbin/nologin zbxtable
  fi
  install -d -o zbxtable -g zbxtable "$RUNTIME_ROOT"
  install -m 0755 "$BUILD_DIR/$APP_NAME" "$RUNTIME_ROOT/$APP_NAME"
  rm -rf "$RUNTIME_ROOT/config"
  cp -a "$APP_DIR/config" "$RUNTIME_ROOT/config"
  install -d -o zbxtable -g zbxtable "$RUNTIME_ROOT/log" "$RUNTIME_ROOT/download" "$RUNTIME_ROOT/upload"
  chown -R zbxtable:zbxtable "$RUNTIME_ROOT/config"
  [[ -f "$APP_DIR/zbxtable.service" ]] || fail "Service template is missing: $APP_DIR/zbxtable.service"
  sed "s|/usr/local/zbxtable|$RUNTIME_ROOT|g" "$APP_DIR/zbxtable.service" > /etc/systemd/system/zbxtable.service
  chmod 0644 /etc/systemd/system/zbxtable.service
  systemctl daemon-reload
  systemctl enable zbxtable.service
  systemctl cat zbxtable.service >/dev/null || fail 'systemd service registration failed.'
  log 'Installed systemd service; start it with: systemctl start zbxtable'
else
  log "systemd not installed; run $APP_DIR/scripts/run.sh to start the application."
fi

log "Installation complete. Open http://127.0.0.1:$HTTP_PORT after startup."
