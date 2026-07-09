# lasso-dagu

`lasso-dagu` packages Dagu as an optional managed Service Lasso workflow-runner service.

The root `service.json` is the canonical Service Lasso manifest for the `dagu` service. It declares the packaged Dagu runtime, local UI/API and MCP endpoints, healthchecks, managed data/config/workflow directories, and exported environment values used by downstream integrations.

## What This Service Provides

- Dagu Web UI/API exposed on `http://127.0.0.1:18088/` by default.
- Dagu MCP endpoint exposed on `http://127.0.0.1:18088/mcp`.
- Service Lasso launcher wrappers for Windows, Linux, and macOS.
- Packaged upstream Dagu binary pinned to `v2.10.1`.
- Managed local directories for Dagu state, workflows, logs, and config.
- Safe Dagu/Secrets Broker workflow contract fixtures.

## Local Package

Windows:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\package.ps1
```

Linux/macOS:

```bash
bash ./scripts/package.sh
```

The package scripts download the pinned upstream Dagu release asset into `.tmp/dagu/` and create a Service Lasso release artifact under `dist/`.

## Local Tests

Windows:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\test.ps1
```

Linux/macOS:

```bash
bash ./scripts/test.sh
```

When a platform package exists under `dist/`, the test script expands it and verifies the packaged launcher can invoke the bundled Dagu binary's version command. The scripts also validate the Dagu/Secrets Broker fixture contract.

## Harness Verify

The Service Lasso harness contract lives at `verify/service-harness.json`.

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\verify.ps1
```

```bash
bash ./scripts/verify.sh
```

Set `SERVICE_LASSO_HARNESS_BIN` when the harness binary is not on `PATH`.

## Runtime Contract

The managed launcher runs:

```text
dagu start-all --host ${DAGU_HOST} --port ${DAGU_PORT}
```

Default runtime values:

- `DAGU_HOST=127.0.0.1`
- `DAGU_PORT=18088`
- `DAGU_HOME=${SERVICE_ROOT}/data`
- `DAGU_WORKFLOWS_DIR=${SERVICE_ROOT}/workflows`
- `DAGU_LOG_DIR=${SERVICE_ROOT}/logs`
- `DAGU_CONFIG=${SERVICE_ROOT}/config/dagu.yaml`

Global values exported for dependants/admin UI integrations:

- `DAGU_URL`
- `DAGU_MCP_URL`
- `DAGU_WORKFLOWS_DIR`

The manifest authors these interfaces through canonical `endpoints[]` entries:

- `http`: local inbound TCP/HTTP listener on `127.0.0.1:18088`
- `ui`: URL endpoint selecting `${endpoint.http.bind}` and `${endpoint.http.port}`
- `mcp`: URL endpoint selecting `${endpoint.http.bind}` and `${endpoint.http.port}`

Legacy `ports` and top-level `urls` authoring are intentionally absent. The current `execconfig.serviceport` value is retained only as a compatibility alias for runtimes that still normalize legacy manifests while service-lasso/service-lasso#810 lands.

See `docs/dagu-service-contract.md` for the detailed Service Lasso contract.

## Dagu / Secrets Broker Contract

The optional Dagu integration contract for Secrets Broker refs is documented in `docs/secretsbroker-ref-contract.md`.

Key boundary:

- Dagu workflow YAML references broker refs only, never secret values.
- Service Lasso resolves refs through `@secretsbroker` at run time.
- Dagu run logs, params, artifacts, and UI-visible summaries remain metadata-only/redacted.
- Dagu remains optional; normal Service Lasso service startup and Secrets Broker usage do not depend on Dagu.

Safe contract fixtures live under `fixtures/dagu/` and are checked by the repo test scripts.

## Managed Workflow Sync

`scripts/sync-service-lasso-workflows.py` consumes a Service Lasso workflow registry JSON file or URL and writes generated Dagu workflow YAML under a managed directory:

```powershell
python .\scripts\sync-service-lasso-workflows.py `
  --registry .\fixtures\service-lasso\workflow-registry.sample.json `
  --output-dir .\workflows\managed\service-lasso `
  --action-api-url http://127.0.0.1:17883 `
  --prune-stale
```

Generated files carry `x-service-lasso.managedBy: service-lasso`, preserve registry step order, call the Service Lasso action run API for each step through `scripts/run-service-lasso-action.py`, and use an overwrite drift policy. The runner logs safe workflow/action metadata and the Service Lasso action run id when returned. Disabled registry entries are omitted; with `--prune-stale`, old generated files are removed while unmanaged workflow files are left untouched.

## Design Context

Read in this order if you need the broader Service Lasso service-package context:

1. `docs/dagu-service-contract.md`
2. `docs/service-contract.md`
3. `docs/service-json-reference.md`
4. `docs/packaging.md`
5. `docs/validation.md`
6. `docs/runtime-extension-points.md`
7. `docs/service-lasso-managed-workflows.md`
8. `docs/service-lasso-action-inputs.md`
