# ABPIV private n8n OpenTofu

This root models the steady-state private Compute runtime, shared-host resources, and n8n edge controls. State remains in the private `abpiv-personal-brand-opentofu-state` bucket under `infra/n8n`.

## Managed resources

- Existing-project API enablement needed by the current private runtime
- Dedicated VPC/subnet, Cloud Router/NAT, IAP-only SSH firewall, and private deletion-protected shared VM
- Independent non-auto-delete n8n and Plausible data disks
- Shared-host runtime identity, narrowed GitHub OIDC deployer roles, and exact service-account-user bindings
- n8n and Plausible secret containers plus least-privilege VM access
- Private versioned backup bucket with seven-day retention and lifecycle
- Logging metrics and monitoring alert policies
- Cloudflare Tunnel, fixed proxied CNAMEs, forms WAF/rate limits, editor Access, and the MCP service token

There is no alternate n8n origin selector and no source for the retired serverless service, managed database, private-service connection, connector, load balancer, certificates, binary-data bucket, old identities, or old permissions.

Removing the five retired `google_project_service.required` addresses from this source does not disable those APIs because every service resource used `disable_on_destroy=false`. The first reviewed steady-state cleanup plan may therefore contain only those five state-removal actions. Disabling a project API is a separate project-wide decision and is intentionally outside this n8n cleanup because unrelated resources may use it.

## State and apply contract

Live plans and applies use `n8n-apply.yml`; do not operate this backend from a local shell.

1. Dispatch `mode=plan` from exact `main` with `confirm_plan=plan-private-n8n-infrastructure` and approve the protected `production-plan` gate.
2. The workflow first verifies the private runtime and public editor/forms controls. It then publishes the redacted plan, sorted action list, canonical redacted prior and desired values plus transition metadata, exact commit, and a combined manifest SHA-256.
3. Give the exact artifact, commit, and manifest digest to an independent rigorous reviewer. Require `COMPLIANT / APPROVED / READY` for that evidence.
4. In a later dispatch on the same exact commit, use `mode=apply`, `confirm_apply=apply-reviewed-private-n8n-infrastructure`, the review decision and reviewer identity, the reviewed commit, and the reviewed manifest digest.
5. Approve the protected `production` gate only after all inputs and the live state still match. The workflow regenerates the plan, reproduces the manifest, applies only the saved reviewed plan, proves a full-root no-op, and reverifies private/public health.

An empty action list is valid plan evidence and hashes deterministically. Apply cannot proceed from plan evidence with a different commit, action set, resolved non-sensitive value, or unknown-value structure. Sensitive values are replaced by structural markers before hashing.

## Authentication and secrets

Google uses Application Default Credentials locally for offline validation or repository-scoped Workload Identity Federation in Actions. Cloudflare reads `CLOUDFLARE_API_TOKEN` from the environment. Never use service-account key files.

OpenTofu creates secret containers and IAM only. It does not contain secret versions, output the Tunnel token, or persist secret values in source. The Cloudflare Access client-secret output is marked sensitive.

## Offline checks

```bash
tofu fmt -check -recursive infra/n8n/opentofu
export TF_DATA_DIR="$(mktemp -d)"
tofu -chdir=infra/n8n/opentofu init -backend=false -input=false
tofu -chdir=infra/n8n/opentofu validate
tofu -chdir=infra/n8n/opentofu test
```

Provider downloads belong only in the external `TF_DATA_DIR`. A local validation must not contact the production backend, generate a live plan, or mutate infrastructure.
