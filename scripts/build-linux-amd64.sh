#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${ZBXTABLE_WEB_DIR:-}" ]]; then
  FRONTEND_DIR="$(cd "${ZBXTABLE_WEB_DIR}" && pwd)"
elif [[ -d "${ROOT_DIR}/../zbxtable-web" ]]; then
  FRONTEND_DIR="$(cd "${ROOT_DIR}/../zbxtable-web" && pwd)"
elif [[ -d "${ROOT_DIR}/../zbxtable-web-master/zbxtable-web-master" ]]; then
  FRONTEND_DIR="$(cd "${ROOT_DIR}/../zbxtable-web-master/zbxtable-web-master" && pwd)"
else
  echo 'Frontend source not found. Set ZBXTABLE_WEB_DIR or place zbxtable-web beside the backend.' >&2
  exit 1
fi
EMBED_DIR="${ROOT_DIR}/api/v1/web/web"
APP_NAME="zbxtable"
DIST_DIR="${ROOT_DIR}/dist"
OUTPUT="${DIST_DIR}/${APP_NAME}-linux-amd64"

VERSION="$(git -C "${ROOT_DIR}" describe --tags --exact-match 2>/dev/null || echo dev)"
GIT_HASH="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_TIME="$(date -u '+%Y-%m-%d_%H:%M:%S')"
LDFLAGS="-X main.version=${VERSION} -X main.gitHash=${GIT_HASH} -X main.buildTime=${BUILD_TIME} -w -s"

mkdir -p "${DIST_DIR}"
echo 'Building frontend bundle...'
node "${ROOT_DIR}/scripts/patch-frontend-zabbix.js" "${FRONTEND_DIR}"
(
  cd "${FRONTEND_DIR}"
  if command -v yarn >/dev/null 2>&1 && [[ -f yarn.lock ]]; then
    yarn install --frozen-lockfile
    yarn build
  else
    npm ci
    npm run build
  fi
)

echo 'Syncing frontend bundle into embedded web directory...'
if [[ -d "${FRONTEND_DIR}/web" ]]; then
  FRONTEND_OUTPUT="${FRONTEND_DIR}/web"
elif [[ -d "${FRONTEND_DIR}/app/build" ]]; then
  FRONTEND_OUTPUT="${FRONTEND_DIR}/app/build"
else
  echo 'Frontend build completed but neither web nor app/build was found.' >&2
  exit 1
fi
TEMP_EMBED_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_EMBED_DIR}"' EXIT
cp -R "${FRONTEND_OUTPUT}/." "${TEMP_EMBED_DIR}/"
rm -rf "${EMBED_DIR}"
mkdir -p "${EMBED_DIR}"
cp -R "${TEMP_EMBED_DIR}/." "${EMBED_DIR}/"

echo "Building ${APP_NAME} for linux/amd64..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags "${LDFLAGS}" -o "${OUTPUT}" "${ROOT_DIR}/main.go"

echo "Build complete: ${OUTPUT}"
