# Dagu Service Contract

`lasso-dagu` packages the upstream Dagu single-binary workflow runner as the `dagu` managed Service Lasso service.

## Runtime

- Upstream source: `dagucloud/dagu`
- Pinned upstream binary: `v2.10.1`
- Managed command: `dagu start-all --host ${DAGU_HOST} --port ${DAGU_PORT}`
- Default bind: `127.0.0.1:18088`
- Default UI/API URL: `http://127.0.0.1:18088/`
- Default MCP URL: `http://127.0.0.1:18088/mcp`

The package contains a small Service Lasso launcher script for each supported OS and the upstream Dagu binary under `vendor/dagu/`.

## Managed Directories

The launcher creates these directories inside the extracted service root when they do not already exist:

- `data/` for Dagu file-backed state
- `workflows/` for local workflow YAML
- `logs/` for Service Lasso/Dagu runtime logs
- `config/` for managed runtime config inputs

Example workflow fixtures are packaged under `workflows/examples/`.

## Service Lasso Environment

The root `service.json` exports these runtime values:

- `DAGU_HOST`
- `DAGU_PORT`
- `DAGU_HOME`
- `DAGU_WORKFLOWS_DIR`
- `DAGU_LOG_DIR`
- `DAGU_CONFIG`

It also exports global values for dependants and admin UI integrations:

- `DAGU_URL`
- `DAGU_MCP_URL`
- `DAGU_WORKFLOWS_DIR`

## Health

The Service Lasso healthcheck is HTTP-based and targets the Dagu UI/API root:

```json
{
  "type": "http",
  "url": "http://127.0.0.1:${HTTP_PORT}/",
  "expected_status": 200
}
```

## Packaging

`scripts/package.ps1` builds `dist/dagu-service-win32.zip`.

`scripts/package.sh` builds `dist/dagu-service-linux.tar.gz` or `dist/dagu-service-darwin.tar.gz`, depending on the host OS.

Both scripts download the pinned upstream Dagu release asset into `.tmp/dagu/`, stage the service wrapper, config, workflow examples, and binary, then create the Service Lasso release archive.
