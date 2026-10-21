# ABPIV n8n infrastructure

This directory owns the production n8n service on the private shared Compute Engine host. The host is `abpiv-runtime-vm` in `us-east1-c`; n8n and Plausible run as isolated Docker Compose projects with independent data disks, networks, loopback listeners, Tunnel connectors, secrets, backups, and runtime modes.

The production n8n path is:

```text
Cloudflare DNS, WAF, rate limits, and Access
                    |
             Cloudflare Tunnel
                    |
        127.0.0.1:8080 Nginx on the private VM
                    |
             internal Docker network
                |             |
               n8n       PostgreSQL 16
```

The VM has no public IP. Cloud NAT is outbound-only, IAP with OS Login is the sole SSH path, and Cloudflare Tunnel is the sole application ingress path. `forms.allanbpediniv.com` permits only public form and production-webhook routes; `workflows.lobst3rs.com` is protected by Cloudflare Access and n8n authentication.

The retired serverless n8n runtime, database, load balancer, connector, binary-data bucket, identities, permissions, transition workflows, and state-move source are not modeled here. The current source cannot select or recreate that path.

## Source layout

- [`opentofu/`](opentofu/): private VM, network/NAT, durable disks, backup bucket, secret containers and IAM, monitoring, Tunnel, DNS, WAF, rate limiting, and Access.
- [`compute/`](compute/): pinned Compose model, Nginx modes, systemd units, release deployment, backup/restore, runtime checks, and host controls.
- [`tests/`](tests/): steady-state source, runtime, shared-host, and plan-evidence contracts.
- [`tools/canonical-plan-values.py`](tools/canonical-plan-values.py): deterministic redacted value evidence for reviewed infrastructure plans.

## Workflows

- `n8n-validate.yml` runs source contracts, shell/static checks, Compose validation, OpenTofu formatting/validation/tests, and the pinned Plausible restore rehearsal.
- `n8n-apply.yml` separates live `plan` and `apply` dispatches. Plan publishes an exact commit-bound manifest of actions, redacted prior and desired values, and transition metadata. Apply requires the same commit and manifest hash, an independent `COMPLIANT / APPROVED / READY` decision, a durable reviewer identity, the `production` approval gate, a freshly regenerated match, and a final full-root no-op proof. Both modes require the private runtime and public controls to be healthy.
- `n8n-redeploy.yml` either provisions a stopped host with a purpose-limited Tunnel-token confirmation or deploys an in-place release while preserving the current runtime mode. Deployment reloads runtime secrets only with its separate typed confirmation.

All live workflows authenticate to Google through repository-scoped OIDC, serialize shared-host changes, refuse non-`main` dispatches, and use protected environments. No service-account key belongs in GitHub or this repository.

## Required repository configuration

| Name | Type | Expected purpose |
| --- | --- | --- |
| `N8N_GCP_PROJECT_ID` | variable | `abpiv-personal-brand` |
| `N8N_GCP_REGION` | variable | `us-east1` |
| `N8N_GCP_ZONE` | optional variable | `us-east1-c`; workflows use this fallback when absent |
| `N8N_GCP_SERVICE_ACCOUNT` | variable | Dedicated `n8n-github-deployer` OIDC identity |
| `N8N_GCP_WORKLOAD_IDENTITY_PROVIDER` | variable | Workload Identity provider resource name |
| `N8N_GITHUB_OIDC_PRINCIPAL_SET` | variable | Exact repository-scoped principal set |
| `CLOUDFLARE_ACCOUNT_ID` | variable | Account that owns Tunnel and Access |
| `CLOUDFLARE_ZONE_ID_ALLANBPEDINIV` | variable | Forms-hostname zone |
| `CLOUDFLARE_ZONE_ID_LOBST3RS` | variable | Editor-hostname zone fallback |
| `N8N_EDITOR_HOSTNAME` | variable | `workflows.lobst3rs.com` |
| `N8N_EDITOR_ZONE_ID` | optional variable | Editor zone ID; falls back to the Lobst3rs zone variable |
| `N8N_EDITOR_ACCESS_ALLOWED_EMAILS` | variable | Reviewed JSON operator allowlist |
| `CLOUDFLARE_API_TOKEN` | secret | Cloudflare resource-management credential |

Optional Access-organization, group, and zone-name variables are documented in [`opentofu/variables.tf`](opentofu/variables.tf).

The protected `production-plan` environment gates live plan evidence. The protected `production` environment gates infrastructure applies plus host provisioning and release deployment. Every live workflow also checks `main` directly.

## Secret boundary

Runtime values remain only in Secret Manager:

- `abpiv-n8n-encryption-key`
- `abpiv-n8n-postgres-password`
- `abpiv-n8n-cloudflare-tunnel-token`
- the four Plausible runtime/backup secret containers used by the shared host

OpenTofu manages containers and IAM, never secret versions. The VM loads values through its metadata identity into root-only tmpfs files. Provisioning obtains the n8n Tunnel token directly from Cloudflare, writes it through a mode-0600 temporary file, stores it in Secret Manager, and removes the temporary file through a trap.

## Local verification

Use an external OpenTofu data directory so provider artifacts never enter the repository:

```bash
pwsh -File infra/n8n/tests/compute-runtime-contract.ps1
pwsh -File infra/analytics/tests/shared-runtime-contract.ps1
python -m unittest discover -s infra/n8n/tests -p 'test_*.py'
tofu fmt -check -recursive infra/n8n/opentofu
export TF_DATA_DIR="$(mktemp -d)"
tofu -chdir=infra/n8n/opentofu init -backend=false -input=false
tofu -chdir=infra/n8n/opentofu validate
tofu -chdir=infra/n8n/opentofu test
find infra/n8n/compute/scripts infra/analytics/compute/scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
shellcheck infra/n8n/compute/scripts/*.sh infra/analytics/compute/scripts/*.sh
docker compose --project-directory infra/n8n/compute --file infra/n8n/compute/docker-compose.yml config --quiet
```

Do not run a live plan, apply, secret operation, DNS change, release deployment, restore, or form submission without its recorded gate and authority.
