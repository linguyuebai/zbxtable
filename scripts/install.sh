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

set_config_value() {
  local file="$1" key="$2" value="$3"
  CONFIG_KEY="$key" CONFIG_VALUE="$value" python3 - "$file" <<'PY'
import os, sys
from pathlib import Path
path = Path(sys.argv[1])
lines = path.read_text(encoding='utf-8').splitlines()
key = os.environ['CONFIG_KEY']
value = os.environ['CONFIG_VALUE']
for i, line in enumerate(lines):
    if line.lstrip().startswith(key + '='):
        lines[i] = key + '=' + value
        break
else:
    lines.append(key + '=' + value)
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
}

if [[ -f "$CONFIG_FILE" && "${FORCE_CONFIG:-0}" != "1" ]]; then
  log "Existing configuration found; keeping $CONFIG_FILE"
  HTTP_PORT="$(sed -n 's/^httpport=//p' "$CONFIG_FILE" | head -n 1)"
  HTTP_PORT="${HTTP_PORT:-8089}"
else
  DB_TYPE="${ZBXTABLE_DB_TYPE:-mysql}"
  DB_HOST="${ZBXTABLE_DB_HOST:-127.0.0.1}"
  DB_PORT="${ZBXTABLE_DB_PORT:-3306}"
  DB_NAME="${ZBXTABLE_DB_NAME:-zbxtable}"
  DB_USER="${ZBXTABLE_DB_USER:-zbxtable}"
  DB_PASS="${ZBXTABLE_DB_PASS:-}"
  HTTP_PORT="${ZBXTABLE_HTTP_PORT:-8089}"
  RUN_MODE="${ZBXTABLE_RUN_MODE:-prod}"

  if [[ -z "$DB_PASS" ]]; then
    [[ -r /dev/tty && -w /dev/tty ]] || fail 'Database password is required; set ZBXTABLE_DB_PASS or run from an interactive terminal.'
    read -r -s -p 'Zabbix database password: ' DB_PASS < /dev/tty
    printf '\n'
  fi
  [[ -n "$DB_PASS" ]] || fail 'Database password cannot be empty.'

  check_port "$DB_HOST" "$DB_PORT" 'database'
  mkdir -p "$CONFIG_DIR"
  printf 'httpport=%s\nrunmode=%s\ntimeout=12\nlog_level=3\nlog_path=log\nmaxlines=1000\nmaxsize=0\nmaxdays=10\ndaily=true\ndbtype=%s\ndbhost=%s\ndbuser=%s\ndbpass=%s\ndbname=%s\ndbport=%s\n' \
    "$HTTP_PORT" "$RUN_MODE" "$DB_TYPE" "$DB_HOST" "$DB_USER" "$DB_PASS" "$DB_NAME" "$DB_PORT" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log "Wrote shared-database configuration: $DB_TYPE $DB_HOST:$DB_PORT/$DB_NAME"
fi

[[ "$HTTP_PORT" =~ ^[0-9]+$ ]] && (( HTTP_PORT >= 1 && HTTP_PORT <= 65535 )) || fail "Invalid HTTP port in configuration: $HTTP_PORT"

# Recreate a missing runtime configuration from the release template, and
# normalize access even when an older install left permissive file modes.
if [[ ! -f "$CONFIG_FILE" ]]; then
  [[ -f "$APP_DIR/config/app.conf.example" ]] || fail "Configuration template is missing: $APP_DIR/config/app.conf.example"
  install -D -m 0600 "$APP_DIR/config/app.conf.example" "$CONFIG_FILE"
  log "Restored missing configuration from $APP_DIR/config/app.conf.example"
fi
# Backfill newly introduced settings without replacing site-specific values.
while IFS='=' read -r key value; do
  [[ -n "$key" && "$key" != \#* ]] || continue
  if ! grep -q "^[[:space:]]*$key[[:space:]]*=" "$CONFIG_FILE"; then
    printf '\n%s=%s\n' "$key" "$value" >> "$CONFIG_FILE"
    log "Added missing configuration setting: $key"
  fi
done < "$APP_DIR/config/app.conf.example"
if [[ -n "${ZBXTABLE_HTTP_PORT:-}" ]]; then
  set_config_value "$CONFIG_FILE" httpport "$ZBXTABLE_HTTP_PORT"
  HTTP_PORT="$ZBXTABLE_HTTP_PORT"
fi
if grep -q '^[[:space:]]*dbpass[[:space:]]*=change-me[[:space:]]*$' "$CONFIG_FILE"; then
  DB_PASS="${ZBXTABLE_DB_PASS:-}"
  if [[ -z "$DB_PASS" ]]; then
    [[ -r /dev/tty && -w /dev/tty ]] || fail 'Database password is not configured; set ZBXTABLE_DB_PASS or run from an interactive terminal.'
    read -r -s -p 'Zabbix database password: ' DB_PASS < /dev/tty
    printf '\n'
  fi
  [[ -n "$DB_PASS" ]] || fail 'Database password cannot be empty.'
  DB_PASS_FOR_CONFIG="$DB_PASS" python3 - "$CONFIG_FILE" <<'PY'
import os, sys
from pathlib import Path
path = Path(sys.argv[1])
lines = path.read_text(encoding='utf-8').splitlines()
updated = False
for i, line in enumerate(lines):
    if line.lstrip().startswith('dbpass='):
        lines[i] = 'dbpass=' + os.environ['DB_PASS_FOR_CONFIG']
        updated = True
        break
if not updated:
    lines.append('dbpass=' + os.environ['DB_PASS_FOR_CONFIG'])
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
fi
chmod 0600 "$CONFIG_FILE"
mkdir -p "$BUILD_DIR" "$APP_DIR/log" "$APP_DIR/download" "$APP_DIR/upload"
chmod 0750 "$CONFIG_DIR" "$APP_DIR/log" "$APP_DIR/download" "$APP_DIR/upload"

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
  install -d -o zbxtable -g zbxtable -m 0750 "$RUNTIME_ROOT"
  install -m 0755 "$BUILD_DIR/$APP_NAME" "$RUNTIME_ROOT/$APP_NAME"
  # A repair or direct reinstall must not replace a live configuration with
  # a stale copy from the source tree. Release installs seed APP_DIR/config
  # from the saved runtime config; only initialize runtime config when absent.
  if [[ ! -f "$RUNTIME_ROOT/config/app.conf" ]]; then
    install -d -o zbxtable -g zbxtable -m 0750 "$RUNTIME_ROOT/config"
    cp -a "$APP_DIR/config/." "$RUNTIME_ROOT/config/"
  fi
  # The explicit --port selection must apply to the config actually read by
  # systemd, including an existing runtime config preserved during repair.
  if [[ -n "${ZBXTABLE_HTTP_PORT:-}" ]]; then
    set_config_value "$RUNTIME_ROOT/config/app.conf" httpport "$ZBXTABLE_HTTP_PORT"
  fi
  install -d -o zbxtable -g zbxtable -m 0750 "$RUNTIME_ROOT/log" "$RUNTIME_ROOT/download" "$RUNTIME_ROOT/upload"
  chown -R zbxtable:zbxtable "$RUNTIME_ROOT/config" "$RUNTIME_ROOT/log" "$RUNTIME_ROOT/download" "$RUNTIME_ROOT/upload"
  chmod 0750 "$RUNTIME_ROOT/config"
  chmod 0600 "$RUNTIME_ROOT/config/app.conf"
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

log "Installation complete. Open http://127.0.0.1:$HTTP_PORT/?v=$(date +%s) to load the latest frontend."
