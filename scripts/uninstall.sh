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
  --purge               Remove config/app.conf/files and offer confirmed removal
                        of ZbxTable's zbxtable_ tables (never the database)
  --yes                 Skip the program removal confirmation. Database table
                        deletion always requires a separate confirmation.

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

# Read the small key=value configuration without sourcing it. This keeps
# passwords and other values from being executed as shell code.
config_value() {
  local file="$1" key="$2"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$file" | head -n 1
}

find_config() {
  local candidate
  for candidate in "$INSTALL_ROOT/config/app.conf" "$RUNTIME_ROOT/config/app.conf"; do
    if [[ -r "$candidate" ]]; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}

database_table_cleanup() {
  [[ "$PURGE" == 1 ]] || return 0
  local cfg dbtype host port user pass configured dbcli psqlcli
  cfg="$(find_config || true)"
  if [[ -z "$cfg" ]]; then
    echo '[zbxtable] No configuration found; database tables were not changed.'
    return 0
  fi
  dbtype="$(config_value "$cfg" dbtype)"; dbtype="${dbtype,,}"
  host="$(config_value "$cfg" dbhost)"; host="${host:-127.0.0.1}"
  port="$(config_value "$cfg" dbport)"
  user="$(config_value "$cfg" dbuser)"
  pass="$(config_value "$cfg" dbpass)"
  configured="$(config_value "$cfg" dbname)"
  [[ -n "$configured" ]] || { echo '[zbxtable] Database name is missing; tables were not changed.'; return 0; }

  local -a databases=() tables=()
  local candidate table line i choice confirm known duplicate
  case "$dbtype" in
    mysql|mariadb|'')
      dbcli="$(command -v mysql || true)"
      [[ -n "$dbcli" ]] || { echo '[zbxtable] mysql client is not installed; database tables were not changed.'; return 0; }
      export MYSQL_PWD="$pass"
      # The configured database is always considered. SHOW DATABASES may be
      # denied for restricted runtime accounts, which is safe and expected.
      databases+=("$configured")
      while IFS= read -r candidate; do
        [[ -n "$candidate" && "$candidate" =~ [Zz][Bb][Xx][Tt][Aa][Bb][Ll][Ee] ]] || continue
        duplicate=0
        for known in "${databases[@]}"; do [[ "$known" == "$candidate" ]] && duplicate=1 && break; done
        ((duplicate)) || databases+=("$candidate")
      done < <("$dbcli" --protocol=TCP -h "$host" -P "${port:-3306}" -u "$user" --batch --skip-column-names -e 'SHOW DATABASES' 2>/dev/null || true)
      ;;
    postgres|postgresql)
      psqlcli="$(command -v psql || true)"
      [[ -n "$psqlcli" ]] || { echo '[zbxtable] psql client is not installed; database tables were not changed.'; return 0; }
      export PGPASSWORD="$pass"
      databases+=("$configured")
      while IFS= read -r candidate; do
        [[ -n "$candidate" && "$candidate" =~ [Zz][Bb][Xx][Tt][Aa][Bb][Ll][Ee] ]] || continue
        duplicate=0
        for known in "${databases[@]}"; do [[ "$known" == "$candidate" ]] && duplicate=1 && break; done
        ((duplicate)) || databases+=("$candidate")
      done < <("$psqlcli" -h "$host" -p "${port:-5432}" -U "$user" -d postgres -Atqc "SELECT datname FROM pg_database" 2>/dev/null || true)
      ;;
    *) echo "[zbxtable] Unsupported database type '$dbtype'; tables were not changed."; return 0 ;;
  esac

  # Keep only databases that contain our own prefixed tables. Never infer a
  # table from a Zabbix table name and never issue DROP DATABASE.
  local -a usable=()
  for candidate in "${databases[@]}"; do
    [[ "$candidate" =~ ^[A-Za-z0-9_]+$ ]] || continue
    tables=()
    if [[ "$dbtype" == mysql || "$dbtype" == mariadb || -z "$dbtype" ]]; then
      while IFS= read -r table; do [[ "$table" =~ ^zbxtable_[A-Za-z0-9_]+$ ]] && tables+=("$table"); done < <("$dbcli" --protocol=TCP -h "$host" -P "${port:-3306}" -u "$user" --batch --skip-column-names --database="$candidate" -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$candidate' AND LEFT(table_name, 9) = 'zbxtable_'" 2>/dev/null || true)
    else
      while IFS= read -r table; do [[ "$table" =~ ^zbxtable_[A-Za-z0-9_]+$ ]] && tables+=("$table"); done < <("$psqlcli" -h "$host" -p "${port:-5432}" -U "$user" -d "$candidate" -Atqc "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname='public' AND LEFT(tablename, 9) = 'zbxtable_'" 2>/dev/null || true)
    fi
    if ((${#tables[@]})); then
      usable+=("$candidate")
      printf '[zbxtable] Database candidate %s:%s/%s (%d zbxtable_ tables)\n' "$host" "${port:-}" "$candidate" "${#tables[@]}"
    fi
  done
  ((${#usable[@]})) || { echo '[zbxtable] No database containing zbxtable_ tables was found; no database changes made.'; return 0; }
  choice=1
  if ((${#usable[@]} > 1)); then
    echo '[zbxtable] Select the database whose ZbxTable tables should be removed:'
    for i in "${!usable[@]}"; do printf '  %d) %s\n' "$((i+1))" "${usable[$i]}"; done
    [[ -r /dev/tty && -w /dev/tty ]] || { echo '[zbxtable] No terminal for database selection; tables were not changed.'; return 0; }
    read -r -p 'Database number (default 1): ' choice < /dev/tty || return 0
    choice="${choice:-1}"
  fi
  [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#usable[@]})) || { echo '[zbxtable] Invalid database selection; tables were not changed.'; return 0; }
  candidate="${usable[$((choice-1))]}"
  # Re-query the selected database and show every exact table before deletion.
  tables=()
  if [[ "$dbtype" == mysql || "$dbtype" == mariadb || -z "$dbtype" ]]; then
    while IFS= read -r table; do [[ "$table" =~ ^zbxtable_[A-Za-z0-9_]+$ ]] && tables+=("$table"); done < <("$dbcli" --protocol=TCP -h "$host" -P "${port:-3306}" -u "$user" --batch --skip-column-names --database="$candidate" -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$candidate' AND LEFT(table_name, 9) = 'zbxtable_'" 2>/dev/null || true)
  else
    while IFS= read -r table; do [[ "$table" =~ ^zbxtable_[A-Za-z0-9_]+$ ]] && tables+=("$table"); done < <("$psqlcli" -h "$host" -p "${port:-5432}" -U "$user" -d "$candidate" -Atqc "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname='public' AND LEFT(tablename, 9) = 'zbxtable_'" 2>/dev/null || true)
  fi
  printf '[zbxtable] Tables to delete in %s: %s\n' "$candidate" "${tables[*]}"
  [[ -r /dev/tty && -w /dev/tty ]] || { echo '[zbxtable] No terminal for destructive confirmation; tables were not changed.'; return 0; }
  read -r -p "Type DELETE TABLES to remove only these ${#tables[@]} tables (database and Zabbix tables are kept): " confirm < /dev/tty || return 0
  [[ "$confirm" == 'DELETE TABLES' ]] || { echo '[zbxtable] Database table deletion cancelled.'; return 0; }
  for table in "${tables[@]}"; do
    if [[ "$dbtype" == mysql || "$dbtype" == mariadb || -z "$dbtype" ]]; then
      "$dbcli" --protocol=TCP -h "$host" -P "${port:-3306}" -u "$user" --database="$candidate" -e "DROP TABLE IF EXISTS \`$table\`" >/dev/null
    else
      "$psqlcli" -h "$host" -p "${port:-5432}" -U "$user" -d "$candidate" -v ON_ERROR_STOP=1 -c "DROP TABLE IF EXISTS \"$table\"" >/dev/null
    fi
    echo "[zbxtable] Removed table: $candidate.$table"
  done
  unset MYSQL_PWD PGPASSWORD
}
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

if [[ "$PURGE" == 1 ]]; then
  step 'Reviewing ZbxTable database tables for optional removal'
  database_table_cleanup
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
