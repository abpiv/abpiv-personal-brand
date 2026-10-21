from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SCRIPT = REPOSITORY_ROOT / "infra" / "n8n" / "tools" / "canonical-plan-values.py"


class CanonicalPlanValuesTests(unittest.TestCase):
    def canonicalize(self, plan: dict[str, object]) -> tuple[bytes, str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            plan_path = Path(temporary_directory) / "plan.json"
            output_path = Path(temporary_directory) / "values.json"
            plan_path.write_text(json.dumps(plan), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(plan_path), str(output_path)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = output_path.read_bytes()
            return payload, result.stdout.strip()

    @staticmethod
    def create_change(
        address: str,
        after: dict[str, object],
        *,
        before: dict[str, object] | None = None,
        after_unknown: dict[str, object] | None = None,
        after_sensitive: dict[str, object] | None = None,
        before_sensitive: dict[str, object] | None = None,
    ) -> dict[str, object]:
        return {
            "address": address,
            "mode": "managed",
            "type": address.split(".", 1)[0],
            "name": address.split(".", 1)[1],
            "provider_name": "registry.opentofu.org/example/provider",
            "change": {
                "actions": ["create"],
                "before": before,
                "after": after,
                "after_unknown": after_unknown or {},
                "after_sensitive": after_sensitive or {},
                "before_sensitive": before_sensitive or {},
            },
        }

    def test_binds_resolved_values_unknown_structure_and_resource_identity(self) -> None:
        first = self.create_change(
            "google_compute_instance.n8n",
            {
                "name": "abpiv-runtime-vm",
                "zone": "us-east1-c",
                "credentials": {"token": "must-not-leak"},
            },
            after_unknown={"id": True},
            after_sensitive={"credentials": {"token": True}},
        )
        second = self.create_change(
            "cloudflare_zero_trust_tunnel_cloudflared.n8n[0]",
            {"account_id": "account-a", "name": "abpiv-n8n-compute"},
            after_unknown={"id": True},
        )
        no_op = {
            "address": "google_compute_network.n8n",
            "change": {"actions": ["no-op"], "after": {"name": "abpiv-n8n-network"}},
        }

        payload, digest = self.canonicalize(
            {"resource_changes": [first, no_op, second]}
        )
        document = json.loads(payload)

        self.assertEqual(document["schema_version"], 2)
        self.assertEqual(
            [resource["address"] for resource in document["resource_changes"]],
            [
                "cloudflare_zero_trust_tunnel_cloudflared.n8n[0]",
                "google_compute_instance.n8n",
            ],
        )
        self.assertNotIn(b"must-not-leak", payload)
        self.assertEqual(
            document["resource_changes"][1]["after"]["credentials"]["token"],
            {"sensitive": True},
        )
        self.assertEqual(digest, hashlib.sha256(payload).hexdigest())

        reordered_payload, reordered_digest = self.canonicalize(
            {"resource_changes": [second, first, no_op]}
        )
        self.assertEqual(reordered_payload, payload)
        self.assertEqual(reordered_digest, digest)

        changed = json.loads(json.dumps(first))
        changed["change"]["after"]["zone"] = "us-east1-b"
        _, changed_digest = self.canonicalize(
            {"resource_changes": [changed, second, no_op]}
        )
        self.assertNotEqual(changed_digest, digest)

        sensitive_changed = json.loads(json.dumps(first))
        sensitive_changed["change"]["after"]["credentials"]["token"] = "rotated"
        sensitive_payload, sensitive_digest = self.canonicalize(
            {"resource_changes": [sensitive_changed, second, no_op]}
        )
        self.assertEqual(sensitive_payload, payload)
        self.assertEqual(sensitive_digest, digest)

        unknown_changed = json.loads(json.dumps(first))
        unknown_changed["change"]["after_unknown"] = {"id": True, "uri": True}
        _, unknown_digest = self.canonicalize(
            {"resource_changes": [unknown_changed, second, no_op]}
        )
        self.assertNotEqual(unknown_digest, digest)

    def test_binds_redacted_before_state_and_transition_metadata(self) -> None:
        transition = self.create_change(
            "google_compute_instance.n8n",
            {
                "machine_type": "e2-standard-2",
                "credentials": {"token": "new-secret-must-not-leak"},
            },
            before={
                "machine_type": "e2-custom-medium-6144",
                "credentials": {"token": "old-secret-must-not-leak"},
            },
            before_sensitive={"credentials": {"token": True}},
            after_sensitive={"credentials": {"token": True}},
        )
        transition["change"]["actions"] = ["delete", "create"]
        transition["change"]["replace_paths"] = [["machine_type"]]
        transition["action_reason"] = "replace_because_cannot_update"

        payload, digest = self.canonicalize({"resource_changes": [transition]})
        document = json.loads(payload)
        evidence = document["resource_changes"][0]
        self.assertEqual(
            evidence["before"]["machine_type"], "e2-custom-medium-6144"
        )
        self.assertEqual(
            evidence["before"]["credentials"]["token"], {"sensitive": True}
        )
        self.assertNotIn(b"old-secret-must-not-leak", payload)
        self.assertNotIn(b"new-secret-must-not-leak", payload)

        before_changed = json.loads(json.dumps(transition))
        before_changed["change"]["before"]["machine_type"] = "e2-standard-4"
        _, before_changed_digest = self.canonicalize(
            {"resource_changes": [before_changed]}
        )
        self.assertNotEqual(before_changed_digest, digest)

        sensitive_before_changed = json.loads(json.dumps(transition))
        sensitive_before_changed["change"]["before"]["credentials"][
            "token"
        ] = "rotated-old-secret"
        sensitive_payload, sensitive_before_digest = self.canonicalize(
            {"resource_changes": [sensitive_before_changed]}
        )
        self.assertEqual(sensitive_payload, payload)
        self.assertEqual(sensitive_before_digest, digest)

        reason_changed = json.loads(json.dumps(transition))
        reason_changed["action_reason"] = "replace_by_request"
        _, reason_changed_digest = self.canonicalize(
            {"resource_changes": [reason_changed]}
        )
        self.assertNotEqual(reason_changed_digest, digest)

        path_changed = json.loads(json.dumps(transition))
        path_changed["change"]["replace_paths"] = [["boot_disk"]]
        _, path_changed_digest = self.canonicalize(
            {"resource_changes": [path_changed]}
        )
        self.assertNotEqual(path_changed_digest, digest)


if __name__ == "__main__":
    unittest.main()
