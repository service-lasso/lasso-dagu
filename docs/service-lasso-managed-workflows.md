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
      "actionId": "backup-files"
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
  "parentActionId": "backup"
}
```

Dagu should record the Service Lasso action run id when the API returns one.

## Drift policy

Generated workflows are owned by Service Lasso. If a generated workflow file changes outside the sync loop, `lasso-dagu` should either:

- overwrite it from the registry on the next sync, or
- report drift clearly and refuse to run the drifted managed workflow until reconciled.

The first implementation should choose one policy and document it.

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
