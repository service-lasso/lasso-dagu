# Optional Dagu Integration Contract for Secrets Broker Refs

Status: implemented contract slice
Issue: #2
Service: `@dagu` / optional Dagu integration

## Purpose

Dagu can run Service Lasso workflows, but it must remain optional. Normal services can resolve runtime configuration through Service Lasso and `@secretsbroker` without installing or starting Dagu.

This contract defines how Dagu workflow YAML can reference Secrets Broker refs safely, how Service Lasso injects scoped runtime material at run time, and how run status maps back to broker/source/audit outcomes without exposing secret values.

## Architecture boundary

```text
Dagu workflow YAML -> declarative secret refs only
Service Lasso runner/adapter -> scoped resolution request
@secretsbroker -> policy/source/key checks and value resolution
Dagu run process -> receives scoped runtime env/config material
Dagu logs/status/artifacts -> metadata and outcomes only
```

Rules:

- Dagu is a workflow runner, not the authority for provider credentials or policy decisions.
- `@secretsbroker` owns source auth, policy checks, key/lock state, reveal decisions, and write-back policy.
- Service Lasso owns the adapter that turns workflow ref declarations into scoped broker requests.
- Workflow YAML, run params, run logs, artifacts, UI summaries, issue comments, and diagnostics must never contain raw secret values.

## Workflow ref syntax

Workflow YAML declares secret dependencies under a Service Lasso extension block:

```yaml
x-service-lasso:
  secrets:
    - name: DATABASE_URL
      ref: services/api/runtime/DATABASE_URL
      target: env
      required: true
      purpose: dagu-run
```

Field meanings:

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | Runtime env/config key visible to the task. This is not a secret value. |
| `ref` | yes | Secrets Broker ref. Must be a safe ref identifier, not a URI containing credentials. |
| `target` | yes | Runtime materialization target such as `env`, `file`, or `stdin`. |
| `required` | no | Whether this ref blocks the run when unresolved. Defaults to `true`. |
| `purpose` | no | Audit purpose. Defaults to `dagu-run`. |

The workflow step should consume `${DATABASE_URL}` or a generated file path only after Service Lasso materializes it for the process. The YAML must not include a fallback plaintext secret.

## Runtime resolution flow

1. Service Lasso loads the Dagu workflow and extracts `x-service-lasso.secrets`.
2. Service Lasso validates refs and targets before the Dagu run starts.
3. Service Lasso calls `@secretsbroker` with:
   - workflow id
   - run id
   - service/workspace id
   - purpose `dagu-run`
   - requested refs
4. `@secretsbroker` enforces lock/key/source auth/policy state.
5. Service Lasso injects resolved values into the child process environment or scoped temp files.
6. Service Lasso records audit correlation metadata and passes only safe metadata to Dagu run labels/status.
7. Dagu logs and artifacts receive redacted placeholders and typed outcomes only.

## Failure states

| Broker outcome | Dagu run state | Safe run message | Retry guidance |
| --- | --- | --- | --- |
| `locked` | blocked | `secrets_broker_locked` | unlock/import/re-wrap the broker key outside Dagu |
| `setup_needed` | blocked | `secrets_broker_setup_needed` | initialize broker/store outside Dagu |
| `source_auth_required` | blocked or degraded | `secret_source_auth_required` | reconnect the named source in Secrets Broker |
| `policy_denied` | failed | `secret_policy_denied` | update policy/audit reason outside Dagu |
| `missing_ref` | failed | `secret_ref_missing` | correct the ref or source mapping |
| `source_unavailable` | retryable | `secret_source_unavailable` | retry after source recovers |
| `degraded` | failed | `secrets_resolution_degraded` | inspect broker diagnostics without revealing values |

Messages may include safe ref identifiers and source ids. They must not include raw values, provider tokens, portable master keys, wrapper plaintext, cookies, passwords, private keys, or raw env values.

## Audit correlation

Each run should carry stable metadata:

```json
{
  "workflowId": "service-lasso.example.secretref",
  "runId": "dagu-run-0001",
  "brokerRequestId": "sb-dagu-run-0001",
  "purpose": "dagu-run",
  "refs": ["services/api/runtime/DATABASE_URL"],
  "outcome": "ready"
}
```

This metadata is safe for Dagu status/log summaries because it contains identifiers and outcomes only.

## Dagu optionality

Dagu-specific support must not become a required path for Secrets Broker or normal service startup.

Required non-Dagu paths remain valid:

- `secretsbroker admin secrets ...` for headless operators
- Service Lasso service startup/env materialization
- direct local API resolve calls behind Service Lasso policy
- optional Service Admin UI flows

If Dagu is not installed, Service Lasso should report Dagu workflow features as unavailable without changing Secrets Broker readiness or blocking non-Dagu services.

## Fixtures and validation

Safe examples live under `fixtures/dagu/`:

- `workflows/secretsbroker-ref-example.yaml`
- `run-logs/safe-success.log`
- `run-logs/safe-failure.log`
- `artifacts/safe-run-summary.json`

The repo test scripts validate these fixtures to ensure they use ref identifiers, safe redaction markers, and typed outcomes only.
