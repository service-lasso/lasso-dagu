#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

for path in \
  "$ROOT/service.json" \
  "$ROOT/verify/service-harness.json" \
  "$ROOT/docs/dagu-service-contract.md"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
done

SERVICE_ID=$(python3 - <<'PY'
import json, pathlib
print(json.loads(pathlib.Path('service.json').read_text())['id'])
PY
)
if [[ "$SERVICE_ID" != "dagu" ]]; then
  echo "service.json id mismatch" >&2
  exit 1
fi

CONTRACT_ID=$(python3 - <<'PY'
import json, pathlib
print(json.loads(pathlib.Path('verify/service-harness.json').read_text())['serviceId'])
PY
)
if [[ "$CONTRACT_ID" != "dagu" ]]; then
  echo "service-harness.json serviceId mismatch" >&2
  exit 1
fi

python3 - <<'PY'
import json, pathlib, sys
service = json.loads(pathlib.Path('service.json').read_text())
if service['execconfig']['serviceport'] != 18088:
    sys.exit('service.json Dagu port mismatch')
if 'lasso-dagu' not in service['meta']['repository']['url']:
    sys.exit('service.json repository still points at the template repo')
tags = ','.join(service['meta'].get('tags', []))
if 'template' in tags or 'example-service' in tags:
    sys.exit('service.json still carries template/sample tags')
PY

OS_NAME=$(uname -s)
case "$OS_NAME" in
  Linux*) RUNTIME="$ROOT/output/test/dagu-service-linux/runtime/dagu-service.sh"; ARTIFACT="$ROOT/dist/dagu-service-linux.tar.gz" ;;
  Darwin*) RUNTIME="$ROOT/output/test/dagu-service-darwin/runtime/dagu-service.sh"; ARTIFACT="$ROOT/dist/dagu-service-darwin.tar.gz" ;;
  *) echo "Unsupported OS for test.sh: $OS_NAME" >&2; exit 1 ;;
esac

if [[ -f "$ARTIFACT" ]]; then
  rm -rf "$ROOT/output/test"
  mkdir -p "$(dirname "$RUNTIME")"
  tar -xzf "$ARTIFACT" -C "$(dirname "$(dirname "$RUNTIME")")"
  VERSION_OUTPUT="$("$RUNTIME" --version)"
  if [[ ! "$VERSION_OUTPUT" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "packaged Dagu launcher did not report a Dagu version" >&2
    exit 1
  fi
fi

python3 "$ROOT/scripts/validate-dagu-secretref-fixtures.py"

echo "Dagu service tests passed ($OS_NAME)"
