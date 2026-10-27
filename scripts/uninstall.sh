#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_ROOT="${ZBXTABLE_INSTALL_ROOT:-/opt/zbxtable}"
RUNTIME_ROOT="${ZBXTABLE_RUNTIME_ROOT:-/usr/local/zbxtable}"
PURGE=0
YES=0
DOCKER_CONTAINER="${ZBXTABLE_DOCKER_CONTAINER:-zbxtable}"

for arg in "$@"; do
  case "$arg" in
    --install-root=*) INSTALL_ROOT="${arg#*=}" ;;
    --runtime-root=*) RUNTIME_ROOT="${arg#*=}" ;;
    --docker-container=*) DOCKER_CONTAINER="${arg#*=}" ;;
    --purge) PURGE=1 ;;
    --yes) YES=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: sudo bash scripts/uninstall.sh [options]
  --install-root=PATH  Source/install directory (default: /opt/zbxtable)
  --runtime-root=PATH  systemd runtime directory (default: /usr/local/zbxtable)
  --purge               Also remove config/app.conf and the install directory
  --yes                 Do not ask for confirmation

Without --purge, the application and runtime files are removed while
config/app.conf is kept under the install directory. Zabbix services and
the shared Zabbix database are never stopped or deleted.
EOF
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

fail() { echo "[zbxtable] ERROR: $*" >&2; exit 1; }
step() { STEP=$((STEP + 1)); printf '[%02d] %s\n' "$STEP" "$*"; }
STEP=0
validate_path() {
  local path="$1"
  [[ "$path" == /* ]] || fail "Path must be absolute: $path"
  case "$path" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/root|/sbin|/srv|/sys|/tmp|/usr|/var|/usr/local)
      fail "Refusing to remove a system directory: $path" ;;
  esac
}
validate_path "$INSTALL_ROOT"
validate_path "$RUNTIME_ROOT"

if [[ "$YES" != 1 ]]; then
  if [[ "$PURGE" == 1 ]]; then
    read -r -p "This removes ZbxTable, configuration and runtime files under $INSTALL_ROOT and $RUNTIME_ROOT. Type DELETE to continue: " answer
  else
    read -r -p "This removes the ZbxTable program and runtime files, while keeping config/app.conf. Type DELETE to continue: " answer
  fi
  [[ "$answer" == DELETE ]] || { echo 'Uninstall cancelled.'; exit 0; }
fi

step 'Stopping and removing the ZbxTable systemd service'
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop zbxtable.service 2>/dev/null || true
  systemctl disable zbxtable.service 2>/dev/null || true
  rm -f /etc/systemd/system/zbxtable.service
  systemctl daemon-reload 2>/dev/null || true
fi

step 'Removing the ZbxTable Docker container, if present'
if command -v docker >/dev/null 2>&1 && docker container inspect "$DOCKER_CONTAINER" >/dev/null 2>&1; then
  echo "[zbxtable] Removing container: $DOCKER_CONTAINER"
  docker rm -f "$DOCKER_CONTAINER" >/dev/null
else
  echo '[zbxtable] No ZbxTable Docker container found.'
fi

step 'Saving configuration when requested'
CONFIG_BACKUP=""
if [[ "$PURGE" != 1 ]]; then
  if [[ -f "$INSTALL_ROOT/config/app.conf" ]]; then
    CONFIG_BACKUP="$(mktemp)"
    cp -p "$INSTALL_ROOT/config/app.conf" "$CONFIG_BACKUP"
  elif [[ -f "$RUNTIME_ROOT/config/app.conf" ]]; then
    CONFIG_BACKUP="$(mktemp)"
    cp -p "$RUNTIME_ROOT/config/app.conf" "$CONFIG_BACKUP"
  fi
fi

step 'Removing ZbxTable program and runtime files'
[[ "$RUNTIME_ROOT" == "$INSTALL_ROOT" ]] || rm -rf -- "$RUNTIME_ROOT"
rm -rf -- "$INSTALL_ROOT"

if [[ "$PURGE" != 1 && -n "$CONFIG_BACKUP" ]]; then
  step 'Restoring preserved configuration'
  install -d "$INSTALL_ROOT/config"
  install -m 600 "$CONFIG_BACKUP" "$INSTALL_ROOT/config/app.conf"
  rm -f "$CONFIG_BACKUP"
  echo "Preserved configuration: $INSTALL_ROOT/config/app.conf"
fi

step 'Uninstall finished'
echo 'ZbxTable has been removed. Zabbix services and the shared database were not modified.'
if id zbxtable >/dev/null 2>&1; then
  echo 'The system user zbxtable was kept. Remove it manually only if it is not used elsewhere.'
fi
