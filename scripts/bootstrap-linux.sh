#!/usr/bin/env bash
set -Eeuo pipefail

GO_VERSION="${ZBXTABLE_GO_VERSION:-1.24.0}"
log() { printf '[zbxtable-env] %s\n' "$*"; }
fail() { printf '[zbxtable-env] ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

install_packages() {
  local manager="$1"
  case "$manager" in
    apt-get)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y ca-certificates curl tar gzip coreutils python3 git nodejs npm
      ;;
    dnf) dnf install -y ca-certificates curl tar gzip coreutils python3 git nodejs npm ;;
    yum) yum install -y ca-certificates curl tar gzip coreutils python3 git nodejs npm ;;
    zypper) zypper --non-interactive install ca-certificates curl tar gzip coreutils python3 git nodejs npm ;;
    apk) apk add --no-cache ca-certificates curl tar gzip coreutils python3 git nodejs npm ;;
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
  url="https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz"
  log "Installing Go ${GO_VERSION} from $url"
  curl -fsSL "$url" -o "$tmp/go.tgz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp/go.tgz"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
fi

command -v go >/dev/null 2>&1 || fail 'Go installation did not provide the go command.'
log "Environment is ready: $(go version)"
