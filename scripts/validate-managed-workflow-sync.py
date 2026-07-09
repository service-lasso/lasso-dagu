#!/usr/bin/env python3
"""Validate Service Lasso registry sync generates safe, ordered Dagu workflows."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SYNC = ROOT / "scripts" / "sync-service-lasso-workflows.py"
RUNNER = ROOT / "scripts" / "run-service-lasso-action.py"
REGISTRY = ROOT / "fixtures" / "service-lasso" / "workflow-registry.sample.json"
CUSTOM_INLINE = ROOT / "fixtures" / "dagu" / "workflows" / "custom-service-lasso-inline.yaml"
CUSTOM_PAYLOAD_REF = ROOT / "fixtures" / "dagu" / "workflows" / "custom-service-lasso-payload-ref.yaml"


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


class ActionHandler(BaseHTTPRequestHandler):
    status_code = 200
    response_body: dict[str, object] = {"actionRunId": "run-test-123"}

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API.
        length = int(self.headers.get("Content-Length", "0"))
        self.server.last_body = self.rfile.read(length).decode("utf-8")  # type: ignore[attr-defined]
        self.send_response(self.status_code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(self.response_body).encode("utf-8"))

    def log_message(self, *_args: object) -> None:
        return


def run_action_server(status_code: int, response_body: dict[str, object]) -> tuple[ThreadingHTTPServer, str]:
    class Handler(ActionHandler):
        pass

    Handler.status_code = status_code
    Handler.response_body = response_body
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address
    return server, f"http://{host}:{port}/api/services/minecraft/actions/backup/runs"


def run_runner(url: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--url",
            url,
            "--payload",
            '{"source":"dagu","workflowId":"minecraft.backup.nightly","scheduleId":"nightly","stepId":"backup","parentActionId":"backup"}',
            "--workflow-id",
            "minecraft.backup.nightly",
            "--schedule-id",
            "nightly",
            "--step-id",
            "backup",
            "--service-id",
            "minecraft",
            "--action-id",
            "backup",
        ],
        check=False,
        text=True,
        capture_output=True,
    )


def run_runner_with_payload_args(url: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--url",
            url,
            "--workflow-id",
            "minecraft.backup.nightly",
            "--schedule-id",
            "nightly",
            "--step-id",
            "backup",
            "--service-id",
            "minecraft",
            "--action-id",
            "backup",
            "--parent-action-id",
            "backup",
            "--payload-ref",
            "backup-policy-nightly",
            "--inline-payload",
            '{"mode":"incremental"}',
        ],
        check=False,
        text=True,
        capture_output=True,
    )


def main() -> int:
    if not SYNC.is_file():
        return fail(f"Missing sync script: {SYNC}")
    if not RUNNER.is_file():
        return fail(f"Missing action runner: {RUNNER}")
    if not REGISTRY.is_file():
        return fail(f"Missing sample registry: {REGISTRY}")
    if not CUSTOM_INLINE.is_file():
        return fail(f"Missing custom inline workflow fixture: {CUSTOM_INLINE}")
    if not CUSTOM_PAYLOAD_REF.is_file():
        return fail(f"Missing custom payload-ref workflow fixture: {CUSTOM_PAYLOAD_REF}")

    custom_inline_text = CUSTOM_INLINE.read_text(encoding="utf-8")
    if "--inline-payload" not in custom_inline_text or '"world":"survival"' not in custom_inline_text:
        return fail("custom inline workflow fixture must call Service Lasso with inline payload values")
    if "managedBy: service-lasso" in custom_inline_text:
        return fail("custom inline workflow fixture must not be marked as Service Lasso managed")

    custom_ref_text = CUSTOM_PAYLOAD_REF.read_text(encoding="utf-8")
    if "--payload-ref" not in custom_ref_text or "restore_req_123" not in custom_ref_text:
        return fail("custom payload-ref workflow fixture must call Service Lasso with a stored payload reference id")
    if '"dryRun":true' not in custom_ref_text:
        return fail("custom payload-ref workflow fixture must show allowed inline override values")
    if "managedBy: service-lasso" in custom_ref_text:
        return fail("custom payload-ref workflow fixture must not be marked as Service Lasso managed")

    with tempfile.TemporaryDirectory(prefix="lasso-dagu-sync-") as temp:
        output_dir = Path(temp) / "workflows" / "managed" / "service-lasso"
        stale_dir = output_dir / "minecraft"
        stale_dir.mkdir(parents=True, exist_ok=True)
        stale = stale_dir / "stale-managed.yaml"
        stale.write_text("x-service-lasso:\n  managedBy: service-lasso\n", encoding="utf-8")
        unmanaged = output_dir / "custom-workflow.yaml"
        unmanaged.write_text(custom_inline_text, encoding="utf-8")
        custom_dir = Path(temp) / "workflows" / "custom" / "minecraft"
        custom_dir.mkdir(parents=True, exist_ok=True)
        custom_workflow = custom_dir / CUSTOM_PAYLOAD_REF.name
        custom_workflow.write_text(custom_ref_text, encoding="utf-8")

        result = subprocess.run(
            [
                sys.executable,
                str(SYNC),
                "--registry",
                str(REGISTRY),
                "--output-dir",
                str(output_dir),
                "--action-api-url",
                "http://127.0.0.1:17883",
                "--prune-stale",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            return fail(result.stderr.strip() or result.stdout.strip())

        summary = json.loads(result.stdout)
        if summary.get("driftPolicy") != "overwrite":
            return fail("sync summary must report overwrite drift policy")
        if summary.get("disabledPolicy") != "omit-and-prune":
            return fail("sync summary must report disabled workflow pruning policy")

        generated = output_dir / "minecraft" / "minecraft.backup.nightly.yaml"
        if not generated.is_file():
            return fail(f"Expected generated workflow missing: {generated}")
        if stale.exists():
            return fail("stale generated workflow was not pruned")
        if not unmanaged.exists():
            return fail("unmanaged workflow was incorrectly removed")
        if unmanaged.read_text(encoding="utf-8") != custom_inline_text:
            return fail("unmanaged workflow under the output directory was modified")
        if not custom_workflow.exists():
            return fail("user-authored workflow outside the managed output directory was removed")
        if custom_workflow.read_text(encoding="utf-8") != custom_ref_text:
            return fail("user-authored workflow outside the managed output directory was modified")

        text = generated.read_text(encoding="utf-8")
        required = [
            "managedBy: service-lasso",
            'workflowId: "minecraft.backup.nightly"',
            'checksum: "sha256:test-registry-v1"',
            "driftPolicy: overwrite",
            "command: python",
            "scripts/run-service-lasso-action.py",
            "--workflow-id",
            "--schedule-id",
            "--step-id",
            "--service-id",
            "--action-id",
            "--parent-action-id",
            "--payload-ref",
            "backup-policy-nightly",
            "--inline-payload",
            "http://127.0.0.1:17883/api/services/minecraft/actions/stop/runs",
            "http://127.0.0.1:17883/api/services/minecraft/actions/backup-files/runs",
            "http://127.0.0.1:17883/api/services/minecraft/actions/start/runs",
            '{\\"mode\\":\\"incremental\\"}',
        ]
        for snippet in required:
            if snippet not in text:
                return fail(f"Generated workflow missing {snippet!r}")

        order = [text.index('name: "stop"'), text.index('name: "backup"'), text.index('name: "start"')]
        if order != sorted(order):
            return fail("Generated workflow did not preserve registry step order")

        bad_registry = Path(temp) / "missing-action-metadata.json"
        bad_registry.write_text(
            json.dumps(
                {
                    "workflows": [
                        {
                            "id": "missing.action",
                            "managedBy": "service-lasso",
                            "serviceId": "minecraft",
                            "scheduleId": "nightly",
                            "steps": [{"id": "backup", "serviceId": "minecraft", "actionId": "backup"}],
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        bad_result = subprocess.run(
            [
                sys.executable,
                str(SYNC),
                "--registry",
                str(bad_registry),
                "--output-dir",
                str(output_dir),
            ],
            check=False,
            text=True,
            capture_output=True,
        )
        if bad_result.returncode == 0 or "missing required fields: actionId" not in bad_result.stderr:
            return fail("sync must fail when workflow action metadata is missing")

    success_server, success_url = run_action_server(200, {"actionRunId": "run-test-123"})
    try:
        success = run_runner(success_url)
    finally:
        success_server.shutdown()
    if success.returncode != 0:
        return fail(success.stderr.strip() or success.stdout.strip())
    if "service_lasso_action_accepted" not in success.stdout or "run-test-123" not in success.stdout:
        return fail("action runner must log accepted Service Lasso action run id")

    payload_server, payload_url = run_action_server(200, {"actionRunId": "run-test-456"})
    try:
        payload_result = run_runner_with_payload_args(payload_url)
        posted_payload = json.loads(payload_server.last_body)  # type: ignore[attr-defined]
    finally:
        payload_server.shutdown()
    if payload_result.returncode != 0:
        return fail(payload_result.stderr.strip() or payload_result.stdout.strip())
    if posted_payload.get("payloadRef") != "backup-policy-nightly":
        return fail("action runner must post stored payloadRef ids")
    if posted_payload.get("payload") != {"mode": "incremental"}:
        return fail("action runner must post custom inline payload values")
    if posted_payload.get("parentActionId") != "backup":
        return fail("action runner must post parent action metadata")

    failure_server, failure_url = run_action_server(500, {"error": {"code": "action_failed"}})
    try:
        failure = run_runner(failure_url)
    finally:
        failure_server.shutdown()
    if failure.returncode == 0:
        return fail("action runner must fail when Service Lasso API returns an error")
    if "service_lasso_action_failed" not in failure.stdout or "action_failed" not in failure.stdout:
        return fail("action runner must log safe failure metadata for Service Lasso API errors")

    print("Service Lasso managed workflow sync validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
