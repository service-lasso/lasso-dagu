#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
CACHE="$ROOT/.tmp/dagu"
DAGU_VERSION="${DAGU_VERSION:-2.10.1}"
DAGU_VERSION="${DAGU_VERSION#v}"

OS_NAME=$(uname -s)
case "$OS_NAME" in
  Linux*) PLATFORM="linux" ;;
  Darwin*) PLATFORM="darwin" ;;
  *) echo "Unsupported OS for package.sh: $OS_NAME" >&2; exit 1 ;;
esac

ARCH_NAME=$(uname -m)
case "$ARCH_NAME" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture for package.sh: $ARCH_NAME" >&2; exit 1 ;;
esac

ASSET="dagu_${DAGU_VERSION}_${PLATFORM}_${ARCH}.tar.gz"
ARCHIVE="$CACHE/$ASSET"
EXTRACT="$CACHE/${PLATFORM}_${ARCH}_${DAGU_VERSION}"
STAGING="$DIST/dagu-service-$PLATFORM"
TAR_PATH="$DIST/dagu-service-$PLATFORM.tar.gz"
DOWNLOAD_URL="https://github.com/dagucloud/dagu/releases/download/v$DAGU_VERSION/$ASSET"

mkdir -p "$DIST" "$CACHE"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Downloading Dagu $DAGU_VERSION for $PLATFORM $ARCH"
  curl -fsSL "$DOWNLOAD_URL" -o "$ARCHIVE"
fi

rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"
tar -xzf "$ARCHIVE" -C "$EXTRACT"
DAGU_BIN="$(find "$EXTRACT" -type f -name dagu | head -n 1)"
if [[ -z "$DAGU_BIN" ]]; then
  echo "Dagu executable not found in $ARCHIVE" >&2
  exit 1
fi

rm -rf "$STAGING"
mkdir -p "$STAGING/vendor/dagu" "$STAGING/data" "$STAGING/logs" "$STAGING/workflows" "$STAGING/scripts"

cp "$ROOT/service.json" "$STAGING/service.json"
cp -R "$ROOT/runtime/$PLATFORM" "$STAGING/runtime"
cp -R "$ROOT/config" "$STAGING/config"
cp -R "$ROOT/fixtures/dagu/workflows" "$STAGING/workflows/examples"
cp "$ROOT/scripts/run-service-lasso-action.py" "$STAGING/scripts/run-service-lasso-action.py"
cp "$DAGU_BIN" "$STAGING/vendor/dagu/dagu"
chmod +x "$STAGING/vendor/dagu/dagu" "$STAGING/runtime/dagu-service.sh"

rm -f "$TAR_PATH"
tar -czf "$TAR_PATH" -C "$STAGING" .
echo "Created $TAR_PATH"
