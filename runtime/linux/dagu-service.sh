#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DAGU_BIN="$SERVICE_ROOT/vendor/dagu/dagu"

if [[ ! -x "$DAGU_BIN" ]]; then
  echo "Dagu binary not found or not executable at $DAGU_BIN. Run scripts/package.sh to build the service artifact." >&2
  exit 1
fi

if [[ "${1:-}" == "--version" ]]; then
  exec "$DAGU_BIN" version
fi

DAGU_HOST="${DAGU_HOST:-127.0.0.1}"
DAGU_PORT="${DAGU_PORT:-18088}"
export DAGU_HOME="${DAGU_HOME:-$SERVICE_ROOT/data}"
export DAGU_WORKFLOWS_DIR="${DAGU_WORKFLOWS_DIR:-$SERVICE_ROOT/workflows}"
export DAGU_LOG_DIR="${DAGU_LOG_DIR:-$SERVICE_ROOT/logs}"
export SERVICE_ROOT

mkdir -p "$DAGU_HOME" "$DAGU_WORKFLOWS_DIR" "$DAGU_LOG_DIR"

exec "$DAGU_BIN" start-all --host "$DAGU_HOST" --port "$DAGU_PORT"
