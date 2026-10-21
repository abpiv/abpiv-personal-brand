from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


class SteadyStateSourceContractTests(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")

    def test_retired_transition_source_is_absent(self) -> None:
        retired_paths = (
            ".github/workflows/n8n-iam-bootstrap.yml",
            ".github/workflows/n8n-cutover.yml",
            ".github/workflows/n8n-fresh-cutover.yml",
            ".github/workflows/n8n-decommission.yml",
            ".github/workflows/n8n-fresh-decommission.yml",
            ".github/workflows/n8n-fresh-residual-cleanup.yml",
            "infra/n8n/compute/CUTOVER-REVIEW.md",
            "infra/n8n/compute/nginx/precommit.conf",
            "infra/n8n/compute/scripts/assert-fresh-runtime.sh",
            "infra/n8n/compute/scripts/export-cloud-sql.sh",
            "infra/n8n/compute/scripts/fresh-runtime-baseline.sql",
            "infra/n8n/compute/scripts/migrate-from-cloud-sql.sh",
            "infra/n8n/compute/scripts/prepare-cutover-runtime.sh",
            "infra/n8n/compute/scripts/verify-database-counts.sh",
            "infra/n8n/compute/scripts/verify-migration-dump.sh",
            "infra/n8n/compute/scripts/verify-restored-runtime.sh",
            "infra/n8n/opentofu/migrations.tf",
            "infra/n8n/tests/test_bootstrap_evidence.py",
            "infra/n8n/tests/test_fresh_decommission_contract.py",
            "infra/n8n/tests/test_fresh_residual_cleanup_contract.py",
            "infra/n8n/tests/test_plan_allowlist.py",
            "infra/n8n/tools/assert-bootstrap-evidence.py",
            "infra/n8n/tools/assert-plan-allowlist.py",
            "infra/n8n/tools/wait-cloud-run-zero.sh",
        )

        surviving = [path for path in retired_paths if (REPOSITORY_ROOT / path).exists()]
        self.assertEqual([], surviving, f"retired source still exists: {surviving}")

    def test_opentofu_models_only_the_private_runtime(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted((REPOSITORY_ROOT / "infra/n8n/opentofu").glob("*.tf"))
        )
        retired_tokens = (
            "legacy_",
            "runtime_origin",
            "google_cloud_run_v2_service",
            "google_sql_",
            "google_vpc_access_connector",
            "google_service_networking_connection",
            "google_certificate_manager_",
            "google_compute_region_network_endpoint_group",
            "google_compute_backend_service",
            "google_compute_url_map",
            "google_compute_target_https_proxy",
            "google_compute_global_forwarding_rule",
            'google_compute_global_address" "private_services',
            'google_compute_global_address" "n8n_lb',
            'google_storage_bucket" "binary_data',
            'google_service_account" "n8n_runtime',
            "runtime_binary_data_object_user",
            "runtime_cloudsql_client",
            "certificate_authorization",
            "cloud_run_service",
            "cloud_sql_",
            "binary_data_bucket_name",
        )
        for token in retired_tokens:
            self.assertNotIn(token, source, f"retired OpenTofu token remains: {token}")

        cloudflare = self.read("infra/n8n/opentofu/cloudflare.tf")
        self.assertRegex(
            cloudflare,
            r'content\s*=\s*"\$\{cloudflare_zero_trust_tunnel_cloudflared\.n8n\[0\]\.id\}\.cfargotunnel\.com"',
        )
        self.assertEqual(2, len(re.findall(r'(?m)^\s*type\s*=\s*"CNAME"\s*$', cloudflare)))

    def test_only_steady_state_n8n_workflows_remain(self) -> None:
        names = {
            path.name for path in (REPOSITORY_ROOT / ".github/workflows").glob("n8n-*.yml")
        }
        self.assertEqual(
            {"n8n-apply.yml", "n8n-redeploy.yml", "n8n-validate.yml"}, names
        )

        apply_workflow = self.read(".github/workflows/n8n-apply.yml")
        self.assertNotRegex(
            apply_workflow,
            r"legacy|cloud.?run|cloud.?sql|cutover|decommission|migration",
        )
        for required in (
            "COMPLIANT / APPROVED / READY",
            "reviewed_commit_sha",
            "reviewed_manifest_sha256",
            "production-plan",
            "production",
        ):
            self.assertIn(required, apply_workflow)


if __name__ == "__main__":
    unittest.main()
