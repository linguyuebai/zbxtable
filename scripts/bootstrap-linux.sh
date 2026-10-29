#!/usr/bin/env bash
set -Eeuo pipefail

GO_VERSION="${ZBXTABLE_GO_VERSION:-1.24.0}"
GO_DOWNLOAD_BASE="${ZBXTABLE_GO_DOWNLOAD_BASE:-https://go.dev/dl}"
log() { printf '[zbxtable-env] %s\n' "$*"; }
fail() { printf '[zbxtable-env] ERROR: %s\n' "$*" >&2; exit 1; }

repair_docker_apt_mirrors() {
  local source_file
  while IFS= read -r -d '' source_file; do
    if grep -qE 'https?://mirrors\.aliyun\.com/docker-ce/linux/' "$source_file"; then
      sed -i.bak -E 's#https?://mirrors\.aliyun\.com/docker-ce/linux/#https://download.docker.com/linux/#g' "$source_file"
      log "Replaced the out-of-sync Aliyun Docker CE mirror in $source_file with the official Docker repository."
    fi
  done < <(find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null)
  rm -f /var/lib/apt/lists/*mirrors.aliyun.com_docker-ce* /var/lib/apt/lists/*download.docker.com*
  rm -f /var/lib/apt/lists/partial/*mirrors.aliyun.com_docker-ce* /var/lib/apt/lists/partial/*download.docker.com*
}

apt_update_with_docker_mirror_fallback() {
  if apt-get update; then return 0; fi
  log 'APT index update failed; refreshing Docker CE repository metadata and retrying.'
  repair_docker_apt_mirrors
  apt-get clean
  rm -f /var/lib/apt/lists/partial/*
  apt-get update || fail 'APT update still fails after refreshing Docker CE mirror metadata. Check other configured repositories and retry.'
}

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

install_packages() {
  local manager="$1"
  case "$manager" in
    apt-get)
      export DEBIAN_FRONTEND=noninteractive
      apt_update_with_docker_mirror_fallback
      apt-get install -y ca-certificates curl tar gzip coreutils python3
      ;;
    dnf) dnf install -y ca-certificates curl tar gzip coreutils python3 ;;
    yum) yum install -y ca-certificates curl tar gzip coreutils python3 ;;
    zypper) zypper --non-interactive install ca-certificates curl tar gzip coreutils python3 ;;
    apk) apk add --no-cache ca-certificates curl tar gzip coreutils python3 ;;
    *) fail 'Supported package manager not found (apt-get, dnf, yum, zypper or apk).' ;;
  esac
}

manager=''
for candidate in apt-get dnf yum zypper apk; do
  if command -v "$candidate" >/dev/null 2>&1; then manager="$candidate"; break; fi
done
[[ -n "$manager" ]] || fail 'No supported Linux package manager found.'
log "Installing base packages with $manager"
install_packages "$manager"

if [[ "${ZBXTABLE_NEED_FRONTEND_BUILD:-0}" == "1" ]]; then
  case "$manager" in
    apt-get) apt-get install -y git nodejs npm ;;
    dnf) dnf install -y git nodejs npm ;;
    yum) yum install -y git nodejs npm ;;
    zypper) zypper --non-interactive install git nodejs npm ;;
    apk) apk add --no-cache git nodejs npm ;;
  esac
fi

# Docker builds use Go inside the builder image. When this bootstrap is only
# preparing Node/Git for the frontend, avoid an unnecessary host Go download.
if [[ "${ZBXTABLE_SKIP_GO_INSTALL:-0}" == "1" ]]; then
  log 'Skipping host Go installation; the application will be built in Docker.'
  exit 0
fi

go_ok=0
if command -v go >/dev/null 2>&1; then
  version="$(go version | awk '{print $3}' | sed 's/^go//')"
  major="${version%%.*}"; rest="${version#*.}"; minor="${rest%%.*}"
  if [[ "${major:-0}" -gt 1 || ( "${major:-0}" -eq 1 && "${minor:-0}" -ge 24 ) ]]; then go_ok=1; log "Go $version already satisfies Go 1.24+"; fi
fi

if [[ "$go_ok" != 1 ]]; then
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) go_arch=amd64 ;;
    aarch64|arm64) go_arch=arm64 ;;
    *) fail "Unsupported CPU architecture for automatic Go installation: $arch" ;;
  esac
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  urls=("$GO_DOWNLOAD_BASE/go${GO_VERSION}.linux-${go_arch}.tar.gz")
  [[ "$GO_DOWNLOAD_BASE" == 'https://go.dev/dl' ]] && urls+=("https://golang.google.cn/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz")
  downloaded=0
  for url in "${urls[@]}"; do
    log "Installing Go ${GO_VERSION} from $url"
    if curl --connect-timeout 10 --max-time 180 -fsSL "$url" -o "$tmp/go.tgz"; then
      downloaded=1
      break
    fi
    log "Go download failed from $url; trying the next mirror."
  done
  [[ "$downloaded" == 1 ]] || fail "Unable to download Go ${GO_VERSION}. Set ZBXTABLE_GO_DOWNLOAD_BASE to an accessible mirror."
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp/go.tgz"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
fi

command -v go >/dev/null 2>&1 || fail 'Go installation did not provide the go command.'
log "Environment is ready: $(go version)"
