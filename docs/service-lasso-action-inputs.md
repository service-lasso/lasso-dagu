# Service Lasso Action Inputs in Dagu

_Status: design contract for passing inputs from Dagu to Service Lasso actions._

Dagu workflows can call Service Lasso actions with inputs.

There are two supported input forms:

| Form | Use case |
| --- | --- |
| Inline payload | Small values defined directly in a generated or custom workflow task. |
| Payload references | Larger or operator-selected payloads stored in Service Lasso and passed by id. |

## Boundary

Dagu may pass inputs and run workflow tasks.

Service Lasso owns:

- action definitions
- input validation
- service context
- action execution
- action history
- audit records

Dagu must not become the source of truth for Service Lasso action implementation.

## Managed Service Lasso workflows

Generated workflows should prefer input references when the input was selected or assembled by Service Lasso.

Example generated Dagu task payload:

```json
{
  "source": "dagu",
  "actor": {
    "type": "service-account",
    "id": "dagu",
    "source": "dagu",
    "workflowId": "minecraft.restore.manual",
    "scheduleId": "manual",
    "stepId": "restore"
  },
  "workflowId": "minecraft.restore.manual",
  "scheduleId": "manual",
  "stepId": "restore",
  "parentActionId": "restore",
  "payloadRef": "restore_req_123"
}
```

This is the preferred restore pattern:

```text
Service Admin selects files
Service Lasso creates payloadRef
Dagu runs workflow tasks
Dagu task calls Service Lasso with payloadRef
Service Lasso resolves and validates the input
```

## Custom Git-controlled Dagu workflows

Custom Dagu workflows may pass explicit inline input values.

Example task payload:

```json
{
  "source": "dagu",
  "workflowId": "custom.minecraft-export-world",
  "stepId": "export-world",
  "payload": {
    "world": "survival",
    "format": "zip",
    "includeLogs": false
  }
}
```

This is useful for Git-controlled workflow files where the author intentionally supplies small values.

Service Lasso still validates the action id, input fields, permissions, and execution policy before running anything.

Generated managed workflows always include a Dagu service-account actor context in the action request. Service Lasso uses that actor for permission checks and audit; Dagu does not grant itself broader permissions by choosing a payload.

Example custom Dagu step:

```yaml
name: custom-minecraft-export-world
description: User-authored workflow that calls a Service Lasso action with small inline values.

steps:
  - name: export-world
    command: python
    args:
      - scripts/run-service-lasso-action.py
      - --url
      - http://127.0.0.1:17883/api/services/minecraft/actions/export-world/runs
      - --workflow-id
      - custom.minecraft-export-world
      - --schedule-id
      - git-controlled
      - --step-id
      - export-world
      - --service-id
      - minecraft
      - --action-id
      - export-world
      - --inline-payload
      - '{"format":"zip","includeLogs":false,"world":"survival"}'
```

Custom workflows may also pass a stored payload reference id when Service Lasso owns a larger or operator-selected request:

```yaml
name: custom-minecraft-restore-dry-run
description: User-authored workflow that reuses a stored Service Lasso payload reference.

steps:
  - name: restore-dry-run
    command: python
    args:
      - scripts/run-service-lasso-action.py
      - --url
      - http://127.0.0.1:17883/api/services/minecraft/actions/restore-world/runs
      - --workflow-id
      - custom.minecraft-restore-dry-run
      - --schedule-id
      - operator-request
      - --step-id
      - restore-dry-run
      - --service-id
      - minecraft
      - --action-id
      - restore-world
      - --payload-ref
      - restore_req_123
      - --inline-payload
      - '{"dryRun":true}'
```

Fixture examples live in `fixtures/dagu/workflows/custom-service-lasso-inline.yaml` and `fixtures/dagu/workflows/custom-service-lasso-payload-ref.yaml`.

## Mixed payloads

A task may provide both a payload reference and inline payload values when the target Service Lasso action allows it.

Recommended rule:

```text
payloadRef supplies the main payload
inline payload may override only explicitly allowed fields
```

Example:

```json
{
  "source": "dagu",
  "workflowId": "minecraft.restore.manual",
  "stepId": "restore",
  "payloadRef": "restore_req_123",
  "payload": {
    "dryRun": true
  }
}
```

## Generated workflow sync

When `lasso-dagu` syncs managed workflows from Service Lasso, registry entries may include step-level input defaults.

Generated Dagu workflow files should avoid copying large input payloads into YAML. Prefer stable ids/references for generated Service Lasso workflows.

Generated managed workflows are rewritten from the Service Lasso registry under the managed workflow output directory. User-authored Git workflows are not registry-owned, do not carry `x-service-lasso.managedBy: service-lasso`, and must remain untouched by managed sync and stale-prune operations.

## Failure behaviour

If Service Lasso rejects an input payload, the Dagu task should fail and report safe metadata:

- workflow id
- step id
- service id
- action id
- rejection reason

Dagu should not retry with modified inputs unless the workflow policy explicitly says to retry the same request.

## Related core docs

- service-lasso/service-lasso `docs/reference/service-action-inputs.md`
- service-lasso/service-lasso `schemas/service-action-inputs.schema.json`
