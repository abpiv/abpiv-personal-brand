$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Read-RepositoryFile {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $repositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing required file: $RelativePath")
        return ""
    }

    return Get-Content -LiteralPath $path -Raw
}

function Assert-Match {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Content -notmatch $Pattern) {
        $failures.Add($Message)
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Content -match $Pattern) {
        $failures.Add($Message)
    }
}

$variables = Read-RepositoryFile "infra/n8n/opentofu/variables.tf"
$locals = Read-RepositoryFile "infra/n8n/opentofu/locals.tf"
$gcp = Read-RepositoryFile "infra/n8n/opentofu/gcp.tf"
$compute = Read-RepositoryFile "infra/n8n/opentofu/compute.tf"
$iam = Read-RepositoryFile "infra/n8n/opentofu/iam.tf"
$cloudflare = Read-RepositoryFile "infra/n8n/opentofu/cloudflare.tf"
$outputs = Read-RepositoryFile "infra/n8n/opentofu/outputs.tf"
$compose = Read-RepositoryFile "infra/n8n/compute/docker-compose.yml"
$provision = Read-RepositoryFile "infra/n8n/compute/scripts/provision-host.sh"
$backup = Read-RepositoryFile "infra/n8n/compute/scripts/backup.sh"
$restore = Read-RepositoryFile "infra/n8n/compute/scripts/restore-backup.sh"
$secretLoader = Read-RepositoryFile "infra/n8n/compute/scripts/load-runtime-secrets.sh"
$runtimeBoot = Read-RepositoryFile "infra/n8n/compute/scripts/start-on-boot.sh"
$observation = Read-RepositoryFile "infra/n8n/compute/scripts/observe-runtime.sh"
$monitor = Read-RepositoryFile "infra/n8n/compute/scripts/monitor-runtime.sh"
$runtimeService = Read-RepositoryFile "infra/n8n/compute/systemd/abpiv-n8n.service"
$tunnelService = Read-RepositoryFile "infra/n8n/compute/systemd/abpiv-cloudflared.service"
$firewall = Read-RepositoryFile "infra/n8n/compute/scripts/configure-container-firewall.sh"
$runtimeMode = Read-RepositoryFile "infra/n8n/compute/scripts/runtime-mode.sh"
$backupTimer = Read-RepositoryFile "infra/n8n/compute/systemd/abpiv-n8n-backup.timer"
$deployRelease = Read-RepositoryFile "infra/n8n/compute/scripts/deploy-release.sh"
$redeployWorkflow = Read-RepositoryFile ".github/workflows/n8n-redeploy.yml"
$applyWorkflow = Read-RepositoryFile ".github/workflows/n8n-apply.yml"
$validateWorkflow = Read-RepositoryFile ".github/workflows/n8n-validate.yml"
$canonicalPlanValues = Read-RepositoryFile "infra/n8n/tools/canonical-plan-values.py"

# OpenTofu now models only the private steady-state runtime and its managed edge.
$opentofu = $variables + $locals + $gcp + $compute + $iam + $cloudflare + $outputs
Assert-NotMatch $opentofu 'legacy_|runtime_origin|google_cloud_run_v2_service|google_sql_|google_vpc_access_connector|google_service_networking_connection|google_certificate_manager_' "Retired runtime source must not remain in OpenTofu."
Assert-Match $variables 'variable\s+"compute_machine_type"[\s\S]*?default\s*=\s*"e2-custom-medium-6144"' "The shared VM must default to e2-custom-medium-6144."
Assert-Match $variables 'variable\s+"compute_data_disk_size_gb"[\s\S]*?default\s*=\s*30' "The n8n data disk must default to 30 GiB."
Assert-Match $locals 'github_deployer_project_roles\s*=\s*toset\(\[' "The current deployer roles must be a fixed steady-state set."
Assert-NotMatch $locals 'roles/(run\.admin|cloudsql\.admin|certificatemanager\.|vpcaccess\.|servicenetworking\.|compute\.loadBalancerAdmin)' "No retired deployer role may survive in source."

# The host is private, durable, deletion-protected, and reachable administratively only through IAP/OS Login.
Assert-Match $compute 'resource\s+"google_compute_instance"\s+"n8n"' "The Compute Engine runtime VM is missing."
Assert-Match $compute 'name\s*=\s*"abpiv-runtime-vm"' "The VM must use the approved stable name."
Assert-Match $compute 'deletion_protection\s*=\s*true' "The private runtime VM must retain deletion protection."
Assert-Match $compute 'enable-oslogin\s*=\s*"TRUE"' "OS Login must remain enabled."
Assert-Match $compute 'network_interface\s*\{[\s\S]*subnetwork[\s\S]*stack_type\s*=\s*"IPV4_ONLY"\s*\}' "The VM must remain on the private subnet without an access_config block."
Assert-NotMatch $compute 'access_config\s*\{' "The shared runtime VM must never receive a public IP."
Assert-Match $compute 'shielded_instance_config[\s\S]*enable_secure_boot\s*=\s*true[\s\S]*enable_vtpm\s*=\s*true' "The VM must remain shielded with Secure Boot and vTPM."
Assert-Match $compute 'attached_disk[\s\S]*google_compute_disk\.n8n_data\.id' "The independent n8n data disk must remain attached."
Assert-Match $compute 'resource\s+"google_compute_router_nat"\s+"n8n"' "Private egress must remain behind Cloud NAT."
Assert-Match $compute 'source_ranges\s*=\s*\["35\.235\.240\.0/20"\]' "SSH ingress must remain restricted to the IAP range."
Assert-Match $firewall '169\.254\.169\.254/32[\s\S]*DOCKER-USER[\s\S]*--jump DROP' "Containers must remain blocked from the VM metadata identity."

# The edge has one private Tunnel origin, strict public-path controls, and Access on the editor.
Assert-Match $cloudflare 'cloudflare_zero_trust_tunnel_cloudflared"\s+"n8n"' "The managed n8n Tunnel is missing."
if ([regex]::Matches($cloudflare, '(?m)^\s*type\s*=\s*"CNAME"\s*$').Count -ne 2) {
    $failures.Add("Both production hostnames must remain fixed Tunnel CNAMEs.")
}
Assert-Match $cloudflare 'forms_firewall_custom[\s\S]*n8n_forms_block_non_public_paths' "The forms hostname must continue blocking non-public paths."
Assert-Match $cloudflare 'forms_rate_limit[\s\S]*n8n_forms_ip_rate_limit' "The forms hostname must retain rate limiting."
Assert-Match $cloudflare 'cloudflare_zero_trust_access_application"\s+"editor"' "The editor must remain behind Cloudflare Access."

# PostgreSQL, n8n, and Nginx are pinned, isolated, bounded, and all have meaningful Docker health signals.
Assert-Match $compose 'postgres@sha256:57c72fd2a128e416c7fcc499958864df5301e940bca0a56f58fddf30ffc07777' "PostgreSQL must remain pinned by digest."
Assert-Match $compose 'n8n@sha256:a119e2e660cf728c8641cdd199c8129cee7e762241627c05be21563d5bbb3fea' "n8n must remain pinned by digest."
Assert-Match $compose 'nginx@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de' "Nginx must remain pinned by digest."
Assert-Match $compose "fetch\('http://127\.0\.0\.1:5678/healthz/readiness'\)[\s\S]*if\(!r\.ok\)process\.exit\(1\)" "n8n health must probe its readiness endpoint with the pinned image's Node runtime."
Assert-Match $compose 'pg_isready --username=n8n --dbname=n8n' "PostgreSQL must retain its readiness healthcheck."
Assert-Match $compose 'wget --quiet --spider[\s\S]*127\.0\.0\.1:8080/healthz' "Nginx must retain its local healthcheck."
Assert-Match $compose '"127\.0\.0\.1:8080:8080"' "Only loopback ingress may be published on the host."
Assert-Match $compose '(?m)^\s*internal:\s*true\s*$' "The application backend network must remain internal."
Assert-Match $compose 'x-logging:[\s\S]*max-size:\s*"10m"[\s\S]*max-file:\s*"3"' "Container logs must remain bounded."
Assert-NotMatch $compose '(?m)^\s*env_file:' "Secrets must not enter persistent Docker environment metadata."

# Secrets, backup/restore, mode persistence, and monitoring remain operational after transition code is removed.
Assert-Match $secretLoader 'metadata\.google\.internal[\s\S]*secretmanager\.googleapis\.com' "The runtime must load secrets directly from Secret Manager through its metadata identity."
Assert-Match $secretLoader 'mktemp /run/n8n/[\s\S]*chmod 0600[\s\S]*unset access_token encryption_key postgres_password tunnel_token' "Runtime secrets must stay in root-only tmpfs files and be unset after use."
Assert-Match $backup 'maintenance-ready[\s\S]*pg_dump[\s\S]*SHA256SUMS[\s\S]*gcloud storage cp[\s\S]*sha256sum --check' "Daily backup must quiesce writes and round-trip verify the complete package."
Assert-Match $restore 'restore-daily-abpiv-n8n[\s\S]*sha256sum --check[\s\S]*pg_restore[\s\S]*remains stopped pending acceptance' "Restore must require typed authority, verify integrity, and stop before acceptance."
Assert-Match $runtimeService 'ExecStart=/opt/abpiv-n8n/scripts/start-on-boot\.sh' "Systemd startup must honor the persisted runtime mode."
Assert-Match $runtimeBoot 'active\|maintenance\|stopped[\s\S]*runtime-mode\.sh' "Boot startup must dispatch only a known persisted mode."
Assert-Match $runtimeMode 'active\)[\s\S]*up --detach --wait --force-recreate n8n nginx[\s\S]*active-ready' "Active mode must wait for every runtime container and local ingress readiness."
Assert-Match $backupTimer 'OnCalendar=\*-\*-\* 06:30:00 America/New_York' "The verified daily backup timer must remain enabled."
Assert-Match $observation 'State\.Health\.Status[\s\S]*/healthz/readiness' "Operator observation must enforce container health and proxied readiness."
Assert-Match $monitor 'condition=container_(missing|unhealthy)[\s\S]*/healthz/readiness' "Ongoing monitoring must alert on missing/unhealthy containers and readiness failures."

# Release and infrastructure workflows remain main-only, serialized, confirmation-gated, and review-bound.
Assert-Match $redeployWorkflow 'Deploy release while preserving runtime mode[\s\S]*sudo env RELEASE_DIR=/tmp/abpiv-n8n-release /tmp/abpiv-n8n-release/scripts/deploy-release\.sh' "Release deployment must execute the newly uploaded deploy logic."
Assert-NotMatch $redeployWorkflow 'sudo env RELEASE_DIR=/tmp/abpiv-n8n-release /opt/abpiv-n8n/scripts/deploy-release\.sh' "Release deployment must not execute stale installed deploy logic."
Assert-Match $deployRelease 'config --quiet[\s\S]*pull --quiet[\s\S]*systemctl daemon-reload[\s\S]*case "\$current_mode"' "A release must validate, pull, install units, and preserve runtime mode."
Assert-Match $applyWorkflow 'options:\s*\[plan, apply\]' "Infrastructure planning and applying must remain separate dispatches."
Assert-Match $applyWorkflow "environment:\s*\$\{\{ inputs\.mode == 'apply' && 'production' \|\| 'production-plan' \}\}" "Infrastructure plan and apply must use separately protected environments."
Assert-Match $applyWorkflow 'reviewed_commit_sha[\s\S]*reviewed_manifest_sha256[\s\S]*COMPLIANT / APPROVED / READY' "Infrastructure apply must bind exact independently reviewed evidence."
Assert-Match $applyWorkflow 'canonical-plan-values\.py[\s\S]*infrastructure-manifest\.txt[\s\S]*sha256sum' "The review manifest must bind non-sensitive resolved values and exact actions."
Assert-Match $applyWorkflow "if:\s*inputs\.mode == 'apply'[\s\S]*apply -input=false -auto-approve infrastructure\.tfplan" "Only the reviewed apply dispatch may execute its freshly regenerated plan."
Assert-Match $applyWorkflow 'Prove full-root convergence[\s\S]*-detailed-exitcode' "Every infrastructure apply must finish with a full-root no-op proof."
Assert-Match $applyWorkflow 'verify-runtime\.sh[\s\S]*workflows\.lobst3rs\.com[\s\S]*forms\.allanbpediniv\.com' "Infrastructure operations must gate on private runtime health and public controls."
Assert-Match $applyWorkflow 'if:\s*always\(\)[\s\S]*rm -f "\$TOFU_DIR/infrastructure\.tfplan"' "Runner cleanup must remove the saved OpenTofu plan from the module directory."
Assert-Match $canonicalPlanValues 'before_sensitive[\s\S]*after_sensitive[\s\S]*after_unknown[\s\S]*replace_paths[\s\S]*sort_keys=True' "Plan evidence must redact sensitive prior and desired values while binding both states and transition metadata."
Assert-Match $validateWorkflow 'canonical-plan-values\.py[\s\S]*unittest discover' "CI must compile the plan-evidence helper and run its tests."

foreach ($workflowPath in @(
    ".github/workflows/n8n-apply.yml",
    ".github/workflows/n8n-redeploy.yml",
    ".github/workflows/plausible-redeploy.yml",
    ".github/workflows/plausible-cutover.yml"
)) {
    $workflow = Read-RepositoryFile $workflowPath
    Assert-Match $workflow 'group:\s*abpiv-shared-runtime-mutation' "$workflowPath must serialize every shared-host mutation."
    Assert-Match $workflow 'cancel-in-progress:\s*false' "$workflowPath must never cancel an in-progress shared-host mutation."
    Assert-Match $workflow "github\.ref == 'refs/heads/main'" "$workflowPath must refuse live dispatches outside main."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Compute runtime contract failed with $($failures.Count) violation(s)."
}

Write-Host "Compute runtime contract passed."
