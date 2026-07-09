#!/usr/bin/env python3
"""Run one Service Lasso action from a generated Dagu task."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from typing import Any


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def safe_identifier(value: Any) -> str:
    text = str(value or "")
    return re.sub(r"[^A-Za-z0-9._:-]+", "-", text).strip("-")[:160]


def emit(event: str, **metadata: Any) -> None:
    payload = {"event": event}
    for key, value in metadata.items():
        if value is None:
            continue
        payload[key] = safe_identifier(value)
    print(json.dumps(payload, sort_keys=True), flush=True)


def response_json(body: bytes) -> Any:
    if not body:
        return None
    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def action_run_id(data: Any) -> str | None:
    if not isinstance(data, dict):
        return None
    for key in ("actionRunId", "runId", "id"):
        value = data.get(key)
        if value:
            return str(value)
    run = data.get("run")
    if isinstance(run, dict) and run.get("id"):
        return str(run["id"])
    return None


def error_code(data: Any) -> str | None:
    if not isinstance(data, dict):
        return None
    for key in ("code", "errorCode"):
        value = data.get(key)
        if value:
            return str(value)
    error = data.get("error")
    if isinstance(error, dict) and error.get("code"):
        return str(error["code"])
    if isinstance(error, str):
        return error
    return None


def error_message(data: Any) -> str | None:
    if not isinstance(data, dict):
        return None
    for key in ("message", "errorMessage", "reason"):
        value = data.get(key)
        if value:
            return str(value)
    error = data.get("error")
    if isinstance(error, dict):
        for key in ("message", "reason"):
            value = error.get(key)
            if value:
                return str(value)
    return None


def parse_payload(raw: str) -> dict[str, Any]:
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("payload must be a JSON object")
    return value


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    if args.payload:
        if args.payload_ref or args.inline_payload:
            raise ValueError("--payload cannot be combined with --payload-ref or --inline-payload")
        return parse_payload(args.payload)

    actor = {
        "type": args.actor_type,
        "id": args.actor_id,
        "source": args.actor_source,
        "workflowId": args.workflow_id,
        "scheduleId": args.schedule_id,
        "stepId": args.step_id,
    }
    payload: dict[str, Any] = {
        "source": "dagu",
        "actor": actor,
        "workflowId": args.workflow_id,
        "scheduleId": args.schedule_id,
        "stepId": args.step_id,
    }
    if args.parent_action_id:
        payload["parentActionId"] = args.parent_action_id
    if args.payload_ref:
        payload["payloadRef"] = args.payload_ref
    if args.inline_payload:
        payload["payload"] = parse_payload(args.inline_payload)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--payload")
    parser.add_argument("--payload-ref")
    parser.add_argument("--inline-payload")
    parser.add_argument("--workflow-id", required=True)
    parser.add_argument("--schedule-id", required=True)
    parser.add_argument("--step-id", required=True)
    parser.add_argument("--service-id", required=True)
    parser.add_argument("--action-id", required=True)
    parser.add_argument("--actor-type", default="service-account")
    parser.add_argument("--actor-id", default="dagu")
    parser.add_argument("--actor-source", default="dagu")
    parser.add_argument("--parent-action-id")
    args = parser.parse_args()

    try:
        payload = build_payload(args)
    except (json.JSONDecodeError, ValueError) as exc:
        return fail(f"invalid Service Lasso action payload: {exc}")

    metadata = {
        "workflowId": args.workflow_id,
        "scheduleId": args.schedule_id,
        "stepId": args.step_id,
        "serviceId": args.service_id,
        "actionId": args.action_id,
        "actorType": args.actor_type,
        "actorId": args.actor_id,
        "actorSource": args.actor_source,
        "parentActionId": args.parent_action_id,
        "payloadRef": args.payload_ref,
    }
    emit("service_lasso_action_request", **metadata)

    request = urllib.request.Request(
        args.url,
        data=json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
            data = response_json(body)
            emit(
                "service_lasso_action_accepted",
                **metadata,
                status=response.status,
                actionRunId=action_run_id(data),
            )
            return 0
    except urllib.error.HTTPError as exc:
        body = exc.read()
        data = response_json(body)
        emit(
            "service_lasso_action_failed",
            **metadata,
            status=exc.code,
            errorCode=error_code(data),
            errorMessage=error_message(data),
        )
        return 1
    except urllib.error.URLError as exc:
        emit("service_lasso_action_failed", **metadata, errorCode=exc.reason)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
