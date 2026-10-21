#!/usr/bin/env python3
"""Emit deterministic, non-sensitive value evidence for actionable plan changes."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


SENSITIVE_MARKER = {"sensitive": True}


def redact_sensitive(value: Any, sensitivity: Any) -> Any:
    if sensitivity is True:
        return SENSITIVE_MARKER

    if isinstance(value, dict):
        sensitive_fields = sensitivity if isinstance(sensitivity, dict) else {}
        return {
            key: redact_sensitive(value[key], sensitive_fields.get(key, False))
            for key in sorted(value)
        }

    if isinstance(value, list):
        sensitive_items = sensitivity if isinstance(sensitivity, list) else []
        return [
            redact_sensitive(
                item,
                sensitive_items[index] if index < len(sensitive_items) else False,
            )
            for index, item in enumerate(value)
        ]

    return value


def canonical_document(plan: dict[str, Any]) -> dict[str, Any]:
    actionable: list[dict[str, Any]] = []
    for resource_change in plan.get("resource_changes", []):
        change = resource_change.get("change", {})
        actions = change.get("actions", [])
        if actions in (["no-op"], ["read"]):
            continue

        actionable.append(
            {
                "address": resource_change["address"],
                "previous_address": resource_change.get("previous_address"),
                "deposed": resource_change.get("deposed"),
                "mode": resource_change.get("mode"),
                "type": resource_change.get("type"),
                "name": resource_change.get("name"),
                "index": resource_change.get("index"),
                "provider_name": resource_change.get("provider_name"),
                "action_reason": resource_change.get("action_reason"),
                "actions": actions,
                "before": redact_sensitive(
                    change.get("before"), change.get("before_sensitive", False)
                ),
                "after": redact_sensitive(
                    change.get("after"), change.get("after_sensitive", False)
                ),
                "after_unknown": change.get("after_unknown", {}),
                "replace_paths": change.get("replace_paths", []),
            }
        )

    actionable.sort(key=lambda item: item["address"])
    return {"schema_version": 2, "resource_changes": actionable}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan_json", type=Path)
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args()

    with args.plan_json.open("r", encoding="utf-8") as source:
        plan = json.load(source)

    encoded = (
        json.dumps(
            canonical_document(plan),
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")
    args.output_json.write_bytes(encoded)
    print(hashlib.sha256(encoded).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
