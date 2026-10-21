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
$compute = Read-RepositoryFile "infra/n8n/opentofu/compute.tf"
$locals = Read-RepositoryFile "infra/n8n/opentofu/locals.tf"
$iam = Read-RepositoryFile "infra/n8n/opentofu/iam.tf"
$allowlist = Read-RepositoryFile "infra/n8n/tools/assert-plan-allowlist.py"
$n8nCutover = Read-RepositoryFile ".github/workflows/n8n-cutover.yml"
$compose = Read-RepositoryFile "infra/analytics/compute/docker-compose.yml"
$provision = Read-RepositoryFile "infra/analytics/compute/scripts/provision-host.sh"
$deployRelease = Read-RepositoryFile "infra/analytics/compute/scripts/deploy-release.sh"
$secretLoader = Read-RepositoryFile "infra/analytics/compute/scripts/load-runtime-secrets.sh"
$export = Read-RepositoryFile "infra/analytics/compute/scripts/export-legacy-plausible.sh"
$restore = Read-RepositoryFile "infra/analytics/compute/scripts/restore-migration.sh"
$restoreBackup = Read-RepositoryFile "infra/analytics/compute/scripts/restore-backup.sh"
$backupPackage = Read-RepositoryFile "infra/analytics/compute/scripts/create-backup-package.sh"
$verify = Read-RepositoryFile "infra/analytics/compute/scripts/verify-migration.sh"
$runtimeMode = Read-RepositoryFile "infra/analytics/compute/scripts/runtime-mode.sh"
$prepareCutover = Read-RepositoryFile "infra/analytics/compute/scripts/prepare-cutover-runtime.sh"
$verifyRestored = Read-RepositoryFile "infra/analytics/compute/scripts/verify-restored-runtime.sh"
$waitForLocalRuntime = Read-RepositoryFile "infra/analytics/compute/scripts/wait-for-local-runtime.sh"
$purgeScriptCache = Read-RepositoryFile "infra/analytics/compute/scripts/purge-script-cache.sh"
$plausibleTunnelUnit = Read-RepositoryFile "infra/analytics/compute/systemd/abpiv-plausible-cloudflared.service"
$activeNginx = Read-RepositoryFile "infra/analytics/compute/nginx/active.conf"
$precommitNginx = Read-RepositoryFile "infra/analytics/compute/nginx/precommit.conf"
$firewall = Read-RepositoryFile "infra/n8n/compute/scripts/configure-container-firewall.sh"
$cutover = Read-RepositoryFile ".github/workflows/plausible-cutover.yml"
$plausibleRedeploy = Read-RepositoryFile ".github/workflows/plausible-redeploy.yml"
$rehearsal = Read-RepositoryFile "infra/analytics/tests/restore-rehearsal.sh"
$validateWorkflow = Read-RepositoryFile ".github/workflows/n8n-validate.yml"

# The approved shared host starts at 1 sustained shared-core vCPU / 6 GiB and has a safe 2 vCPU / 8 GiB fallback.
Assert-Match $variables 'variable\s+"compute_machine_type"[\s\S]*?default\s*=\s*"e2-custom-medium-6144"' "The shared runtime must default to e2-custom-medium-6144."
Assert-Match $n8nCutover 'e2-custom-medium-6144\|e2-standard-2' "n8n cutover retries must accept only the approved shared-host sizes."
Assert-Match $n8nCutover '--machine-type e2-standard-2' "The capacity fallback must resize to e2-standard-2."
Assert-NotMatch $rehearsal '-v /opt:/host-opt' "The Linux CI rehearsal must not stage its Compose runtime through a helper-container host bind."
Assert-Match $rehearsal 'host_paths_owned=false[\s\S]*root_command[\s\S]*tar --extract[\s\S]*/opt/abpiv-plausible' "The rehearsal must track ownership and stage its runtime directly on the Linux host."
Assert-NotMatch $rehearsal 'chmod 0400 /run/plausible/\*' "The rehearsal must not rely on an unprivileged shell expanding root-owned secret paths."
Assert-NotMatch $rehearsal '"\$\{compose\[@\]\}" cp[\s\S]{0,200}clickhouse:/var/lib/clickhouse/backups' "The rehearsal must not stage root-owned ClickHouse restore archives through docker compose cp."
Assert-Match $rehearsal 'install -m 0600 -o 101 -g 101[\s\S]*clickhouse-data/backups/fixture\.zip[\s\S]*clickhouse-data/backups/daily-fixture\.zip' "Both rehearsal archives must be readable only by the ClickHouse runtime identity."
Assert-NotMatch $rehearsal '(?m)^\s*cd /srv/plausible/state\s*$' "The unprivileged rehearsal shell must not enter Plausible-owned state directly."
Assert-Match $rehearsal 'capture_state_evidence\(\)[\s\S]*root_command[\s\S]*bash -o pipefail -c' "State evidence must be captured through the root wrapper after ownership is restored."
Assert-NotMatch $rehearsal '(?m)^(find /srv/plausible/state|tar --extract[^\r\n]*--directory /srv/plausible/state|chown -hR 999:65533 /srv/plausible/state)' "Daily state replacement must not access Plausible-owned paths as the runner."
Assert-Match $rehearsal 'root_command\[@\][\s\S]{0,100}env PACKAGE_DIR=[\s\S]{0,300}create-backup-package\.sh[\s\S]{0,200}chown -R' "The production-equivalent daily package must run as root and return its artifacts to the runner."
Assert-Match $validateWorkflow 'validation_fixture_paths_owned=false[\s\S]*cleanup_validation_fixtures[\s\S]*rm -rf[\s\S]*/srv/plausible' "Static Compose validation must remove only its owned host fixtures before the restore rehearsal starts."

# Plausible gets its own durable non-auto-delete disk on the same private VM.
Assert-Match $variables 'variable\s+"plausible_data_disk_size_gb"[\s\S]*?default\s*=\s*80' "The Plausible data disk must default to 80 GiB."
Assert-Match $compute 'resource\s+"google_compute_disk"\s+"plausible_data"' "The independent Plausible data disk is missing."
Assert-Match $compute 'attached_disk[\s\S]*google_compute_disk\.plausible_data\.id' "The Plausible data disk must attach to abpiv-runtime-vm."
Assert-Match $locals 'compute_plausible_data_disk_name\s*=\s*"abpiv-plausible-data"' "The Plausible disk must have a stable device name."
Assert-Match $allowlist 'google_compute_disk\\\.plausible_data' "Additive-plan enforcement must allowlist the Plausible disk explicitly."

# Secret metadata and access exist without secret versions or values in OpenTofu.
Assert-Match $compute 'google_secret_manager_secret"\s+"plausible_runtime"' "Plausible runtime secret metadata is missing."
Assert-Match $locals 'plausible_runtime_secrets[\s\S]*secret_key_base[\s\S]*postgres_password[\s\S]*tunnel_token[\s\S]*backup_age_key' "Every Plausible runtime and backup secret must have a metadata contract."
Assert-Match $iam 'compute_plausible_secret_accessor' "The shared VM identity must receive Plausible secret access."
Assert-Match $iam 'compute_backup_object_user' "The shared VM identity must access the private seven-day shared backup bucket."
Assert-Match $iam 'github_deployer_plausible_runtime_service_account_user' "The gated deployer must be allowed to use OS Login against the exact old Plausible VM identity."

# Plausible, PostgreSQL, ClickHouse, and Nginx are pinned and isolated from n8n and the host network.
Assert-Match $compose 'ghcr\.io/plausible/community-edition@sha256:4c2553516d09e3c7b1b9c39cca04a04c28c871f525adc8dbb7a2a8a20fed0857' "Plausible must remain on the deployed v2.1.4 digest for migration."
Assert-Match $compose 'postgres@sha256:16bc17c64a573ef34162af9298258d1aec548232985b33ed7b1eac33ba35c229' "Plausible PostgreSQL must use the exact immutable image observed on the legacy source."
Assert-Match $cutover "postgres\) target_ref='docker\.io/library/postgres@sha256:16bc17c64a573ef34162af9298258d1aec548232985b33ed7b1eac33ba35c229'" "Plausible cutover must compare the target to the same exact legacy PostgreSQL image."
Assert-Match $compose 'clickhouse-server@sha256:f226fe41f0578968b7f68a54b902d203ff4decfddfccb97c89fe5bfc36a51b66' "ClickHouse must use the deployed pinned digest."
Assert-Match $compose 'nginx@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de' "Plausible ingress must use the pinned Nginx digest."
if ([regex]::Matches($compose, '(?m)^    ports:\s*$').Count -ne 1) {
    $failures.Add("Plausible Compose must declare exactly one service-level host-port block.")
}
Assert-Match $compose '(?ms)^  nginx:\r?\n(?:(?!^  \S).)*?^    ports:\r?\n      - "127\.0\.0\.1:8000:8000"\r?\n    volumes:' "Only Plausible Nginx may publish the sole exact loopback origin mapping."
if ([regex]::Matches($compose, '(?m)^      - "127\.0\.0\.1:8000:8000"\s*$').Count -ne 1) {
    $failures.Add("Plausible Compose must contain exactly one published mapping, bound to loopback port 8000.")
}
Assert-Match $compose '(?m)^\s*internal:\s*true\s*$' "The Plausible backend network must be internal."
Assert-Match $compose 'nginx:[\s\S]*?networks:\s*\r?\n\s*-\s*backend\s*\r?\n\s*-\s*ingress' "Plausible Nginx must join both the internal backend and the dedicated host-ingress bridge."
Assert-Match $compose '(?m)^  ingress:\r?\n    driver: bridge\r?\n    driver_opts:\r?\n      com\.docker\.network\.bridge\.enable_icc: "false"\r?\n      com\.docker\.network\.bridge\.enable_ip_masquerade: "false"\s*$' "The Plausible ingress bridge must publish loopback traffic without inter-container communication or outbound masquerading."
if ([regex]::Matches($compose, '(?m)^\s*-\s*ingress\s*$').Count -ne 1) {
    $failures.Add("Only Plausible Nginx may join the dedicated host-ingress bridge.")
}
Assert-Match $compose '/srv/plausible/' "All Plausible durable data must live on its attached disk."
Assert-Match $activeNginx 'resolver\s+127\.0\.0\.11[\s\S]*server\s+plausible:8000\s+resolve;' "Active Plausible ingress must defer backend lookup to Docker DNS so Nginx can start before the app."
Assert-Match $compose 'CONFIG_DIR:\s*/run/secrets' "Plausible must use its supported file-based secret loader."
Assert-Match $compose 'POSTGRES_PASSWORD_FILE:\s*/run/secrets/POSTGRES_PASSWORD' "Plausible PostgreSQL must read its password from a file."
Assert-NotMatch $compose '(?m)^\s*env_file:' "Plausible secrets must not be resolved into Docker metadata through env_file."
Assert-Match $compose 'x-logging:[\s\S]*driver:\s*local[\s\S]*max-size:\s*"10m"[\s\S]*max-file:\s*"3"' "Plausible container logs must use the exact bounded local-driver policy."
if ([regex]::Matches($compose, 'logging:\s*\*default-logging').Count -ne 4) {
    $failures.Add("Every Plausible project service must use the bounded logging policy.")
}

# The host refuses boot-disk fallback and preparation leaves the production Plausible stack stopped.
Assert-Match $provision 'findmnt[\s\S]*UUID' "Plausible provisioning must verify the mounted data-disk UUID."
Assert-NotMatch $provision 'nofail' "The Plausible data disk mount must fail closed."
Assert-Match $provision 'down --remove-orphans' "Additive Plausible preparation must leave its containers stopped."
Assert-Match $plausibleRedeploy 'Deploy release while preserving the Plausible runtime mode[\s\S]*sudo env RELEASE_DIR=/tmp/abpiv-plausible-release /tmp/abpiv-plausible-release/scripts/deploy-release\.sh' "Plausible release deployment must execute the uploaded deploy script so deployment logic can update itself."
Assert-NotMatch $plausibleRedeploy 'sudo env RELEASE_DIR=/tmp/abpiv-plausible-release /opt/abpiv-plausible/scripts/deploy-release\.sh' "Plausible release deployment must not execute the previously installed deploy script."
Assert-Match $deployRelease 'docker compose[\s\S]*config --quiet[\s\S]*pull --quiet[\s\S]*for unit in /opt/abpiv-plausible/systemd/\*[\s\S]*install -m 0644[\s\S]*systemctl daemon-reload[\s\S]*case "\$current_mode"' "Plausible release deployment must validate first, install reviewed systemd units, reload systemd, and only then preserve the runtime mode."
Assert-Match $secretLoader '/run/plausible/SECRET_KEY_BASE' "Plausible secrets must be loaded only into host tmpfs."
Assert-Match $secretLoader '/run/plausible/DATABASE_URL' "The database URL containing the password must exist only in host tmpfs."
Assert-Match $plausibleTunnelUnit '(?m)^ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token-file /run/plausible/TUNNEL_TOKEN\s*$' "Plausible cloudflared must parse the root-only token file as a run-subcommand option."
Assert-NotMatch $plausibleTunnelUnit '(?m)^(Environment|EnvironmentFile)=|TUNNEL_TOKEN=' "Plausible cloudflared must not expose the Tunnel token through systemd environment metadata."
Assert-Match $firewall '169\.254\.169\.254/32' "The shared firewall must target the GCE metadata endpoint."
Assert-Match $firewall 'DOCKER-USER[\s\S]*--jump DROP' "Plausible containers must be blocked from the shared VM metadata identity."
Assert-Match $runtimeMode 'maintenance[\s\S]*abpiv-container-firewall --check[\s\S]*systemctl enable abpiv-plausible\.service abpiv-plausible-cloudflared\.service' "Plausible maintenance must enforce metadata isolation and persist fail-closed reboot recovery."
Assert-Match $waitForLocalRuntime 'maintenance-ready\|precommit-ready\|active-ready[\s\S]*seq 1 30[\s\S]*--max-time 2[\s\S]*healthz/readiness[\s\S]*sleep 1' "Local Plausible ingress readiness must use a bounded host-port retry."
Assert-Match $waitForLocalRuntime 'done\s+echo "Plausible local ingress did not reach[\s\S]*docker port abpiv-plausible-nginx-1 8000/tcp >&2 \|\| true[\s\S]*exit 1\s*$' "Safe host-port diagnostics must run only after retry exhaustion and preserve terminal failure."
Assert-Match $waitForLocalRuntime "docker inspect --format 'ports=\{\{json \.NetworkSettings\.Ports\}\} networks=\{\{json \.NetworkSettings\.Networks\}\}'[\s\S]{0,100}abpiv-plausible-nginx-1 >&2 \|\| true" "Host-port diagnostics must inspect only the fixed Nginx container's safe port and network fields."
Assert-Match $waitForLocalRuntime "ss --listening --tcp --numeric \| grep -E '\(\^State\|:8000\[\[:space:\]\]\)' >&2 \|\| true" "Host listener diagnostics must remain numeric, port-8000-only, and non-blocking."
Assert-Match $waitForLocalRuntime "iptables --wait 5 --table nat --list-rules DOCKER \| grep -F -- '--dport 8000' >&2 \|\| true" "Docker NAT diagnostics must remain restricted to port 8000 and non-blocking."
if ([regex]::Matches($waitForLocalRuntime, 'docker inspect').Count -ne 1) {
    $failures.Add("The host-port helper must contain exactly one narrowly formatted Docker inspect command.")
}
Assert-Match $runtimeMode 'wait-for-local-runtime\.sh maintenance-ready false[\s\S]*wait-for-local-runtime\.sh active-ready true' "Plausible maintenance and active transitions must tolerate bounded host-port publication delay."
Assert-Match $prepareCutover 'wait-for-local-runtime\.sh precommit-ready true' "Plausible precommit transition must wait for host ingress and application readiness."
Assert-Match $verifyRestored 'wait-for-local-runtime\.sh maintenance-ready false' "Sealed restore verification must tolerate bounded host-port publication delay."

# Export proves all existing relational, analytics, and application data entered the encrypted package.
Assert-Match $export 'pg_dump[\s\S]*--format=custom' "The old Plausible PostgreSQL database must be exported in custom format."
Assert-Match $export 'BACKUP DATABASE plausible_events_db' "The old ClickHouse analytics database must use a native backup."
Assert-Match $export 'source-postgres-counts\.tsv' "The source PostgreSQL table counts must be recorded."
Assert-Match $export 'source-clickhouse-counts\.tsv' "The source ClickHouse table counts must be recorded."
Assert-Match $export 'clickhouse_container[\s\S]*docker exec "\$clickhouse_container" clickhouse-client' "ClickHouse count queries must not consume the table-list input stream."
Assert-NotMatch $export 'done\s*<\s*<\([^\r\n]*clickhouse-client' "ClickHouse table enumeration must fail closed instead of hiding process-substitution failures."
Assert-Match $export 'plausible-state\.tar' "The Plausible application state must be archived."
Assert-Match $export 'source-state-entries\.bin' "The source state package must record files, directories, and symbolic-link targets."
Assert-Match $export 'sha256sum[\s\S]*age --encrypt' "The source migration package must be checksummed and encrypted before leaving the old VM."
Assert-Match $export 'plausible-migration-packages' "The source must retain only the encrypted handoff package for transfer."
Assert-Match $cutover 'gcloud storage cp[\s\S]*plausible-migration\.tar\.age' "The encrypted migration package must be uploaded to the private backup bucket."

# Restore rejects incomplete data, restores both databases and state, and compares source/target evidence.
Assert-Match $restore 'age --decrypt' "The target must decrypt the retained migration package."
Assert-Match $restore 'sha256sum[\s\S]*--check' "The target must verify the complete inner checksum manifest."
Assert-Match $restore 'pg_restore' "The target must restore PostgreSQL from the migration dump."
Assert-Match $restore 'RESTORE DATABASE plausible_events_db' "The target must restore the ClickHouse analytics database."
Assert-Match $restore 'plausible-state\.tar' "The target must restore Plausible application state."
Assert-Match $verify 'cmp[\s\S]*source-postgres-counts[\s\S]*target-postgres-counts' "PostgreSQL counts must match source evidence."
Assert-Match $verify 'cmp[\s\S]*source-clickhouse-counts[\s\S]*target-clickhouse-counts' "ClickHouse counts must match source evidence."
Assert-Match $backupPackage 'source-postgres-counts\.tsv[\s\S]*source-clickhouse-counts\.tsv[\s\S]*source-state-entries\.bin' "Daily backup packages must carry restorable evidence for every data class."
Assert-Match $restoreBackup 'plausible/daily/\*/plausible-backup\.tar\.age[\s\S]*restore-plausible-daily-backup' "Production daily restore must require an exact object and typed confirmation."

# Cutover has separate gates, proves maintenance through the existing Tunnel, and always retains the old VM for rollback.
Assert-Match $cutover 'confirm_runtime_secret_access' "Plausible secret access needs a typed gate."
Assert-Match $cutover 'confirm_data_movement' "Plausible data movement needs a typed gate."
Assert-Match $cutover 'confirm_tunnel_transition' "Moving the existing Tunnel connector needs a typed gate."
Assert-Match $cutover 'confirm_script_cache_purge:[\s\S]*description:\s*Type purge-plausible-script-cache-for-cutover to authorize up to six exact Worker-subrequest cache purges at the reviewed routing-proof boundaries\.[\s\S]*required:\s*true' "Purging the exact Worker subrequest cache at up to six routing-proof boundaries needs an accurately scoped typed gate."
Assert-Match $cutover 'COMPLIANT / APPROVED / READY' "Plausible cutover needs independent rigorous approval."
Assert-Match $cutover 'plausible-analytics-vm' "The workflow must operate the exact old Plausible VM."
Assert-Match $cutover 'abpiv-runtime-vm' "The workflow must operate the exact new shared VM."
Assert-Match $cutover 'name:\s*Quiesce the old Plausible origin[\s\S]*name:\s*Start the shared target in maintenance mode' "The old Tunnel connector and writer must stop before the target connector starts, preventing dual live connectors."
Assert-Match $cutover 'SCRIPT_CACHE_URL:\s*https://\$\{\{ vars\.PLAUSIBLE_HOSTNAME \|\| ''analytics\.lobst3rs\.com'' \}\}/js/script\.js[\s\S]*SCRIPT_CACHE_ZONE_ID:\s*\$\{\{ vars\.CLOUDFLARE_ZONE_ID_LOBST3RS \}\}' "The cache purge must target the Worker fetch URL in the upstream lobst3rs.com zone, not the end-user URL."
Assert-Match $cutover 'name:\s*Prove the exact Worker subrequest cache purge before downtime[\s\S]*name:\s*Start the 60-minute production window' "The exact Worker-subrequest cache purge permission and source refill must be proven before downtime starts."
Assert-Match $cutover 'name:\s*Start the shared target in maintenance mode[\s\S]*name:\s*Purge the exact Worker subrequest cache after the connector transition[\s\S]*name:\s*Prove the public same-origin route is in maintenance' "The stale Worker-subrequest cache must be purged after the target connector starts and before its maintenance response is checked."
Assert-Match $cutover 'name:\s*Open event writes only on the canonical target[\s\S]*name:\s*Purge the exact Worker subrequest cache before active verification[\s\S]*name:\s*Verify active public routing' "Active public verification must purge the precommit script cache after writes open."
Assert-Match $cutover 'name:\s*Rollback plausible-analytics-vm[\s\S]*systemctl is-active --quiet cloudflared\.service[\s\S]*purge-script-cache\.sh[\s\S]*consecutive=0' "Precommit rollback must purge the target script cache after restoring the source connector and before public polling."
Assert-Match $cutover 'name:\s*Recover the canonical target[\s\S]*runtime-mode\.sh active[\s\S]*purge-script-cache\.sh[\s\S]*curl --fail' "Postcommit recovery must purge stale script responses after restoring the target and before public verification."
Assert-Match $cutover 'name:\s*Create and round-trip the first encrypted shared-host backup[\s\S]*backup\.sh[\s\S]*purge-script-cache\.sh[\s\S]*curl --fail' "Final backup acceptance must purge stale script responses before its public routing proof."
if ([regex]::Matches($cutover, 'purge-script-cache\.sh').Count -ne 6) {
    $failures.Add("Plausible cutover must invoke the exact cache-purge helper at all six routing-proof boundaries.")
}
if ([regex]::Matches($cutover, 'CLOUDFLARE_API_TOKEN:\s*\$\{\{ secrets\.CLOUDFLARE_API_TOKEN \}\}').Count -ne 6) {
    $failures.Add("The known-working Cloudflare API token must be exposed only at the six cache-purge boundaries.")
}
Assert-NotMatch $cutover '(?m)^  CLOUDFLARE_API_TOKEN:' "The Cloudflare API token must not be available at workflow scope."
Assert-NotMatch $cutover 'CLOUDFLARE_ANALYTICS_API_TOKEN' "Plausible cutover must not use the historically failed analytics-specific token."
Assert-Match $purgeScriptCache 'jq --null-input --compact-output --arg url "\$SCRIPT_CACHE_URL" ''\{files:\[\$url\]\}''[\s\S]*curl --fail --silent --show-error[\s\S]*api\.cloudflare\.com/client/v4/zones/\$SCRIPT_CACHE_ZONE_ID/purge_cache[\s\S]*Authorization: Bearer \$CLOUDFLARE_API_TOKEN[\s\S]*jq --exit-status ''\.success == true''' "The cache-purge helper must purge only the exact Worker subrequest URL and fail closed unless Cloudflare confirms success."
Assert-Match $cutover '2700' "Plausible migration must roll back when it misses minute 45."
Assert-Match $cutover 'rollback[\s\S]*plausible-analytics-vm' "Failure handling must restore the old Plausible origin."
Assert-Match $cutover 'steps\.commit\.outputs\.committed != ''true''' "Old-origin rollback must close once the verified target becomes the canonical writer."
Assert-Match $cutover 'steps\.commit\.outputs\.committed == ''true''[\s\S]*runtime-mode\.sh active' "A post-acceptance failure must recover the canonical target without reversing new data."
Assert-Match $cutover 'jobs:[\s\S]*cutover:[\s\S]*timeout-minutes:\s*220' "The Plausible cutover job must retain the reviewed 220-minute hard-timeout budget."
Assert-Match $cutover 'steps:\s*\r?\n\s*- id:\s*job_budget[\s\S]*?start_epoch=\$\(date \+%s\)[\s\S]*?\r?\n\s*- uses:\s*actions/checkout@v4' "The hard-timeout budget clock must be the first declared cutover step, before checkout."
Assert-Match $cutover 'steps\.job_budget\.outputs\.start_epoch[\s\S]*-lt 1800[\s\S]*id:\s*transition' "Plausible cutover must preserve the reviewed hard-timeout reserve before attempting the connector transition."
Assert-Match $cutover 'id:\s*resize_modes[\s\S]{0,400}timeout-minutes:\s*5' "The post-commit fallback-mode capture must have a bounded timeout inside the recovery budget."
Assert-Match $precommitNginx 'limit_except GET[\s\S]*deny all' "Plausible precommit ingress must deny analytics event writes."
Assert-Match $prepareCutover 'precommit\.conf[\s\S]*wait-for-local-runtime\.sh precommit-ready true' "The restored Plausible app must be proven behind read-only ingress before commit."
Assert-Match $cutover 'prepare-cutover-runtime\.sh[\s\S]*id: commit[\s\S]*runtime-mode\.sh active' "The Plausible canonical boundary must follow read-only readiness and precede event exposure."
Assert-Match $cutover 'target_isolated=false[\s\S]*abpiv-plausible-cloudflared\.service[\s\S]*refusing to start the old connector' "Rollback must prove the target connector inactive before starting the old connector."
Assert-Match $cutover 'target_image_id" != "\$source_image_id[\s\S]*source_repo_digests[\s\S]*target_repo_digests[\s\S]*Image identity mismatch' "A pinned-image preflight failure must report safe source and target image evidence before any transition."
Assert-Match $cutover "steps\.resize_modes\.outputs\.n8n_mode[\s\S]*runtime-mode\.sh" "Post-resize recovery must restore the captured n8n mode."
Assert-NotMatch $cutover 'instances delete|terraform destroy|tofu[^\r\n]*apply' "Plausible cutover must never delete either VM or apply infrastructure."

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Shared runtime contract failed with $($failures.Count) violation(s)."
}

Write-Host "Shared runtime contract passed."
