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
if 'ports' in service:
    sys.exit('service.json still declares legacy top-level ports')
if 'urls' in service:
    sys.exit('service.json still declares legacy top-level urls')
endpoints = {endpoint.get('id'): endpoint for endpoint in service.get('endpoints', [])}
http = endpoints.get('http')
if not http or http.get('kind') != 'network':
    sys.exit('service.json missing canonical http network endpoint')
if http.get('port', {}).get('default') != 18088 or http.get('protocol') != 'http' or http.get('bind') != '127.0.0.1':
    sys.exit('service.json http endpoint does not preserve Dagu bind/port/protocol')
if endpoints.get('ui', {}).get('kind') != 'url' or endpoints.get('mcp', {}).get('kind') != 'url':
    sys.exit('service.json missing canonical Dagu URL endpoints')
if service['execconfig']['env']['DAGU_PORT'] != '${endpoint.http.port}':
    sys.exit('service.json DAGU_PORT does not use endpoint selector')
if service['execconfig']['globalenv']['DAGU_URL'] != '${endpoint.ui.url}':
    sys.exit('service.json DAGU_URL does not use endpoint selector')
if service['execconfig']['globalenv']['DAGU_MCP_URL'] != '${endpoint.mcp.url}':
    sys.exit('service.json DAGU_MCP_URL does not use endpoint selector')
healthchecks = {check.get('id'): check for check in service['execconfig'].get('healthchecks', [])}
ui_healthcheck = healthchecks.get('ui')
if not ui_healthcheck:
    sys.exit('service.json missing canonical ui healthcheck')
if ui_healthcheck.get('url') != '${endpoint.ui.url}':
    sys.exit('service.json ui healthcheck does not use endpoint selector')
import subprocess
tracked_manifests = subprocess.check_output(
    ['git', 'ls-files', '*service.json'],
    text=True,
).splitlines()
for manifest_name in tracked_manifests:
    manifest_path = pathlib.Path(manifest_name)
    manifest = json.loads(manifest_path.read_text())
    if 'healthcheck' in manifest or 'healthcheck' in manifest.get('execconfig', {}):
        sys.exit(f'singular healthcheck field remains in manifest: {manifest_path}')
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
python3 "$ROOT/scripts/validate-managed-workflow-sync.py"

echo "Dagu service tests passed ($OS_NAME)"
