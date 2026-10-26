#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${ZBXTABLE_RELEASE_BRANCH:-3.0}"
REPOSITORY="${ZBXTABLE_RELEASE_REPOSITORY:-}"
UPLOAD=0
DRAFT=0
SKIP_CHECKS=0
for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    --draft) DRAFT=1 ;;
    --skip-checks) SKIP_CHECKS=1 ;;
    --branch=*) BRANCH="${arg#*=}" ;;
    --repository=*) REPOSITORY="${arg#*=}" ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo 'Required command not found: git' >&2; exit 1; }
required=(README.md README.zh-CN.md go.mod go.sum .gitignore config/app.conf.example scripts/install.sh scripts/install.ps1 scripts/install-release.sh scripts/install-release.ps1 scripts/bootstrap-linux.sh scripts/install-docker.sh deployments/docker/Dockerfile.release scripts/uninstall.sh scripts/uninstall.ps1 docs/README.md)
if [[ "$SKIP_CHECKS" != 1 ]]; then
  missing=()
  for file in "${required[@]}"; do [[ -f "$ROOT_DIR/$file" ]] || missing+=("$file"); done
  ((${#missing[@]} == 0)) || { printf 'Required files are missing: %s\n' "${missing[*]}" >&2; exit 1; }
  sensitive="$(cd "$ROOT_DIR" && git ls-files -co --exclude-standard | grep -E '(^|/)(app\.conf|\.env($|\.)|log|logs|download|upload|build|dist)(/|$)' || true)"
  [[ -z "$sensitive" ]] || { printf 'Sensitive or generated paths would be published:\n%s\n' "$sensitive" >&2; exit 1; }
  (cd "$ROOT_DIR" && git diff --check)
fi

VERSION="${ZBXTABLE_VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)}"
TAG="$VERSION"; [[ "$TAG" == v* ]] || TAG="v$TAG"
export ZBXTABLE_VERSION="$VERSION"
"$ROOT_DIR/scripts/package-release.sh"
SAFE_VERSION="${VERSION//\//-}"
ARCHIVE="$ROOT_DIR/dist/zbxtable-$SAFE_VERSION-source.tar.gz"
CHECKSUM="$ARCHIVE.sha256"
[[ -f "$ARCHIVE" && -f "$CHECKSUM" ]] || { echo 'Source archive or checksum was not created.' >&2; exit 1; }

assets=("$ARCHIVE" "$CHECKSUM")
for name in install-release.sh install-release.ps1 install-release.bat install.sh install.ps1 install.bat bootstrap-linux.sh install-docker.sh uninstall.sh uninstall.ps1 uninstall.bat; do
  [[ -f "$ROOT_DIR/scripts/$name" ]] && assets+=("$ROOT_DIR/scripts/$name")
done
printf 'Package: %s\nChecksum: %s\nInstaller assets: %d\n' "$ARCHIVE" "$CHECKSUM" "$((${#assets[@]} - 2))"
if [[ "$UPLOAD" != 1 ]]; then
  echo 'Upload not requested. Re-run with --upload after running gh auth login.'
  exit 0
fi
command -v gh >/dev/null 2>&1 || { echo 'Required command not found: gh' >&2; exit 1; }
gh auth status
args=(release create "$TAG" "${assets[@]}" --target "$BRANCH" --title "ZbxTable $TAG" --generate-notes)
[[ -n "$REPOSITORY" ]] && args+=(--repo "$REPOSITORY")
[[ "$DRAFT" == 1 ]] && args+=(--draft)
gh "${args[@]}"
