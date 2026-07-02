# Service Lasso Action Inputs in Dagu

_Status: design contract for passing inputs from Dagu to Service Lasso actions._

Dagu workflows can call Service Lasso actions with inputs.

There are two supported input forms:

| Form | Use case |
| --- | --- |
| Inline inputs | Small values defined directly in a generated or custom workflow task. |
| Input references | Larger or operator-selected payloads stored in Service Lasso and passed by id. |

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
  "workflowId": "minecraft.restore.manual",
  "scheduleId": "manual",
  "stepId": "restore",
  "parentActionId": "restore",
  "inputRef": {
    "type": "service-lasso-action-input",
    "id": "restore_req_123"
  }
}
```

This is the preferred restore pattern:

```text
Service Admin selects files
Service Lasso creates inputRef
Dagu runs workflow tasks
Dagu task calls Service Lasso with inputRef
Service Lasso resolves and validates the input
```

## Custom Git-controlled Dagu workflows

Custom Dagu workflows may pass explicit inline input values.

Example:

```json
{
  "source": "dagu",
  "workflowId": "custom.minecraft-export-world",
  "stepId": "export-world",
  "inputs": {
    "world": "survival",
    "format": "zip",
    "includeLogs": false
  }
}
```

This is useful for Git-controlled workflow files where the author intentionally supplies small values.

Service Lasso still validates the action id, input fields, permissions, and execution policy before running anything.

## Mixed inputs

A task may provide both an input reference and inline inputs when the target Service Lasso action allows it.

Recommended rule:

```text
inputRef supplies the main payload
inline inputs may override only explicitly allowed fields
```

Example:

```json
{
  "source": "dagu",
  "workflowId": "minecraft.restore.manual",
  "stepId": "restore",
  "inputRef": {
    "type": "service-lasso-action-input",
    "id": "restore_req_123"
  },
  "inputs": {
    "dryRun": true
  }
}
```

## Generated workflow sync

When `lasso-dagu` syncs managed workflows from Service Lasso, registry entries may include step-level input defaults.

Generated Dagu workflow files should avoid copying large input payloads into YAML. Prefer stable ids/references for generated Service Lasso workflows.

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
