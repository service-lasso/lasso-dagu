#!/usr/bin/env python3
"""Validate Service Lasso registry sync generates safe, ordered Dagu workflows."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SYNC = ROOT / "scripts" / "sync-service-lasso-workflows.py"
REGISTRY = ROOT / "fixtures" / "service-lasso" / "workflow-registry.sample.json"


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def main() -> int:
    if not SYNC.is_file():
        return fail(f"Missing sync script: {SYNC}")
    if not REGISTRY.is_file():
        return fail(f"Missing sample registry: {REGISTRY}")

    with tempfile.TemporaryDirectory(prefix="lasso-dagu-sync-") as temp:
        output_dir = Path(temp) / "workflows" / "managed" / "service-lasso"
        stale_dir = output_dir / "minecraft"
        stale_dir.mkdir(parents=True, exist_ok=True)
        stale = stale_dir / "stale-managed.yaml"
        stale.write_text("x-service-lasso:\n  managedBy: service-lasso\n", encoding="utf-8")
        unmanaged = output_dir / "custom-workflow.yaml"
        unmanaged.write_text("name: custom\n", encoding="utf-8")

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

        text = generated.read_text(encoding="utf-8")
        required = [
            "managedBy: service-lasso",
            'workflowId: "minecraft.backup.nightly"',
            'checksum: "sha256:test-registry-v1"',
            "driftPolicy: overwrite",
            "http://127.0.0.1:17883/api/services/minecraft/actions/stop/runs",
            "http://127.0.0.1:17883/api/services/minecraft/actions/backup-files/runs",
            "http://127.0.0.1:17883/api/services/minecraft/actions/start/runs",
            '\\"inputRef\\":{\\"id\\":\\"backup-policy-nightly\\",\\"type\\":\\"service-lasso-action-input\\"}',
        ]
        for snippet in required:
            if snippet not in text:
                return fail(f"Generated workflow missing {snippet!r}")

        order = [text.index('name: "stop"'), text.index('name: "backup"'), text.index('name: "start"')]
        if order != sorted(order):
            return fail("Generated workflow did not preserve registry step order")

    print("Service Lasso managed workflow sync validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
