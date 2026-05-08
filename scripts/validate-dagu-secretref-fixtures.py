#!/usr/bin/env python3
"""Validate Dagu/Secrets Broker contract fixtures stay metadata-only."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs" / "secretsbroker-ref-contract.md"
FIXTURE_ROOT = ROOT / "fixtures" / "dagu"
WORKFLOW = FIXTURE_ROOT / "workflows" / "secretsbroker-ref-example.yaml"
SUMMARY = FIXTURE_ROOT / "artifacts" / "safe-run-summary.json"

REQUIRED = [
    DOC,
    WORKFLOW,
    FIXTURE_ROOT / "run-logs" / "safe-success.log",
    FIXTURE_ROOT / "run-logs" / "safe-failure.log",
    SUMMARY,
]

FORBIDDEN_PATTERNS = [
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----"),
    re.compile(r"(?i)password\s*[:=]\s*[^\s<][^\s]*"),
    re.compile(r"(?i)(?:token|secret|api[_-]?key)\s*[:=]\s*(?!<redacted|broker-resolved)[A-Za-z0-9_./+=:-]{8,}"),
    re.compile(r"(?i)postgres(?:ql)?://[^\s]+:[^\s]+@"),
    re.compile(r"(?i)bearer\s+[A-Za-z0-9._-]{12,}"),
]

REQUIRED_TEXT = {
    DOC: ["Dagu is a workflow runner, not the authority", "Dagu optionality", "must never contain raw secret values"],
    WORKFLOW: ["x-service-lasso:", "ref: services/api/runtime/DATABASE_URL", "<redacted-by-service-lasso>"],
}


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def main() -> int:
    for path in REQUIRED:
        if not path.is_file():
            return fail(f"Missing required Dagu secret-ref contract fixture: {path}")

    for path in REQUIRED:
        text = path.read_text(encoding="utf-8")
        for pattern in FORBIDDEN_PATTERNS:
            match = pattern.search(text)
            if match:
                return fail(f"Potential secret material in {path}: {match.group(0)!r}")
        if "raw-secret" in text.lower() or "actual-secret" in text.lower():
            return fail(f"Unsafe placeholder wording in {path}; use redacted metadata wording instead")

    for path, snippets in REQUIRED_TEXT.items():
        text = path.read_text(encoding="utf-8")
        for snippet in snippets:
            if snippet not in text:
                return fail(f"Missing required contract text {snippet!r} in {path}")

    summary = json.loads(SUMMARY.read_text(encoding="utf-8"))
    if summary.get("daguOptional") is not True:
        return fail("safe-run-summary.json must explicitly preserve daguOptional=true")
    if summary.get("values") != "<redacted>":
        return fail("safe-run-summary.json must keep values redacted")
    if summary.get("audit", {}).get("containsSecretMaterial") is not False:
        return fail("safe-run-summary.json audit metadata must assert no secret material")

    print("Dagu Secrets Broker ref fixtures passed metadata-only validation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
