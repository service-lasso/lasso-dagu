# Service Lasso Managed Workflows

_Status: design contract for `lasso-dagu` managed workflow sync._

`lasso-dagu` mirrors scheduled Service Lasso actions into Dagu workflows.

Service Lasso is the source of truth. Dagu is the scheduler and workflow task runner.

## Boundary

```text
Service Lasso
  owns service action definitions
  owns workflow registry
  owns action execution API
  owns service context, workspace, env, permissions, audit and action history

lasso-dagu
  consumes the workflow registry
  creates/updates/removes generated Dagu workflows
  runs generated workflow tasks on schedule
  records Dagu workflow/task status
```

Dagu tasks call Service Lasso action APIs. They do not own the service action implementation.

## Sync flow

```text
lasso-dagu starts
  fetch Service Lasso workflow registry
  generate Dagu workflow files for managed entries
  update changed generated workflows
  remove or disable stale generated workflows
  leave user-authored workflows untouched
  reload/reconcile Dagu
```

The sync loop should run at startup and periodically, or through a later Service Lasso change notification.

## Registry entry

Service Lasso publishes entries like:

```json
{
  "id": "minecraft.backup.nightly",
  "managedBy": "service-lasso",
  "serviceId": "minecraft",
  "actionId": "backup",
  "scheduleId": "nightly",
  "cron": "0 2 * * *",
  "enabled": true,
  "checksum": "sha256:example",
  "steps": [
    {
      "id": "stop",
      "type": "service-lasso-action",
      "serviceId": "minecraft",
      "actionId": "stop"
    },
    {
      "id": "backup",
      "type": "service-lasso-action",
      "serviceId": "minecraft",
      "actionId": "backup-files",
      "payloadRef": "nightly-backup",
      "payload": {
        "mode": "incremental"
      }
    },
    {
      "id": "start",
      "type": "service-lasso-action",
      "serviceId": "minecraft",
      "actionId": "start",
      "run": "always",
      "condition": "was-running-before-workflow"
    }
  ]
}
```

## Generated workflow metadata

Generated Dagu workflows should carry metadata so they can be synced safely:

```yaml
managedBy: service-lasso
workflowId: minecraft.backup.nightly
serviceId: minecraft
actionId: backup
scheduleId: nightly
checksum: sha256:example
```

Manual Dagu workflows must remain separate from generated Service Lasso workflows.

Recommended generated path direction:

```text
workflows/managed/service-lasso/<serviceId>/<workflowId>.yaml
```

User-authored workflows can live beside the managed tree, for example:

```text
workflows/custom/<team-or-service>/<workflow>.yaml
```

Those custom workflows may call the same Service Lasso action runner, but they are Git-authored workflow definitions rather than registry-generated files. They should not include `x-service-lasso.managedBy: service-lasso`, and the managed sync/prune loop must leave them unchanged.

## Generated task behaviour

Each generated Dagu task calls:

```text
POST /api/services/:serviceId/actions/:actionId/runs
```

Example task payload:

```json
{
  "source": "dagu",
  "workflowId": "minecraft.backup.nightly",
  "scheduleId": "nightly",
  "stepId": "backup",
  "parentActionId": "backup",
  "payloadRef": "nightly-backup"
}
```

Dagu should record the Service Lasso action run id when the API returns one. Generated tasks call `scripts/run-service-lasso-action.py`, which posts the request, fails the task on Service Lasso API errors, and emits redacted JSON log lines containing workflow id, step id, service id, action id, parent action id, schedule id, HTTP status, safe error metadata, payload reference id, and the action run id when available.

## Drift policy

Generated workflows are owned by Service Lasso. If a generated workflow file changes outside the sync loop, `lasso-dagu` should either:

- overwrite it from the registry on the next sync, or
- report drift clearly and refuse to run the drifted managed workflow until reconciled.

The first implementation uses an overwrite policy. `scripts/sync-service-lasso-workflows.py` rewrites generated workflow files from the registry on every sync. When `--prune-stale` is set, it removes stale files only when they carry `managedBy: service-lasso`; unmanaged/user Dagu workflows are left untouched. Disabled registry entries are omitted and pruned from the generated set.

The initial sync utility is intentionally file/API boundary focused:

```text
registry JSON file or URL
  -> workflows/managed/service-lasso/<serviceId>/<workflowId>.yaml
```

Each generated Dagu task calls the Service Lasso action run API in registry step order. Later launcher integration can call the same utility at Dagu startup and on the configured sync interval.

`fixtures/dagu/workflows/custom-service-lasso-inline.yaml` and `fixtures/dagu/workflows/custom-service-lasso-payload-ref.yaml` show custom Git-controlled workflows that call Service Lasso actions with inline payload values and stored payload reference ids. `scripts/validate-managed-workflow-sync.py` verifies that managed sync preserves user-authored workflow files during stale pruning.

## Failure handling

If Service Lasso is unavailable, `lasso-dagu` should keep Dagu healthy enough to report sync failure, but generated Service Lasso workflows should not silently run stale or partial actions.

If a Service Lasso action API call fails, the Dagu task should fail and preserve safe metadata:

- workflow id
- step id
- service id
- action id
- schedule id
- Service Lasso error code/message

Runtime values that may contain secrets must not be written into generated Dagu workflows or Dagu logs.

## Related issues

- service-lasso/service-lasso#782
- service-lasso/service-lasso#783
- service-lasso/service-lasso#784
- service-lasso/lasso-dagu#5
- service-lasso/lasso-dagu#6
