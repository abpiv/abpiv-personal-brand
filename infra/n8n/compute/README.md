# Private n8n runtime operations

This directory is the release payload for production n8n on `abpiv-runtime-vm`. PostgreSQL, n8n, and Nginx run in an isolated Docker Compose project. Cloudflare Tunnel is the only application ingress path; the VM has no public IP, Nginx binds only to `127.0.0.1:8080`, and neither n8n nor PostgreSQL publishes a host port.

## Durable and ephemeral state

The attached `abpiv-n8n-data` disk is mounted fail-closed at `/srv/n8n` and contains:

- `postgres/` for PostgreSQL data;
- `state/` for n8n application state;
- `binary/` for filesystem binary data;
- `backups/` for temporary daily-backup staging; and
- `migration/` for recoverable pre-restore snapshots.

Secrets are never stored on that disk. The VM identity loads them from Secret Manager into `/run/n8n` and `/run/cloudflared`, which are root-only tmpfs paths. Compose mounts the minimum required files read-only. The n8n entrypoint copies its two inputs into the container's private tmpfs under the unprivileged runtime identity before starting n8n.

## Runtime modes

`scripts/runtime-mode.sh` accepts only:

- `active`: PostgreSQL, n8n, Nginx, Tunnel, backup timer, and health timer are active; `/healthz` returns `active-ready`.
- `maintenance`: PostgreSQL, Nginx, and Tunnel remain available while n8n is stopped; `/healthz` returns `maintenance-ready`.
- `stopped`: the Compose project and Tunnel are stopped and tmpfs secret files are removed.

The selected mode is persisted in `/etc/abpiv-n8n/mode`. The systemd service delegates boot recovery to `start-on-boot.sh`, which refuses unknown values and restores only the persisted mode.

## Release deployment

Dispatch `n8n-redeploy.yml` from exact `main` with:

- `action=deploy`;
- `confirm_action=deploy-private-n8n-runtime`; and
- `confirm_runtime_secret_access=access-n8n-runtime-secrets`.

The protected `production` gate must be approved. The workflow uploads the exact `compute/` tree over IAP and executes the newly uploaded `deploy-release.sh`, not the previously installed copy. The script validates Compose, pulls pinned images, installs reviewed systemd units, reloads systemd, and restores the pre-deployment runtime mode. Temporary release artifacts are removed in an `always()` step.

Use `action=provision` only to rebuild the approved host from the existing OpenTofu resources. It requires `provision-private-n8n-vm` and `store-tunnel-token`, stores the Tunnel token without logging or retaining it, installs the host controls, rehearses PostgreSQL restore, and leaves the production containers stopped.

## Health and monitoring

All three containers must report Docker health `healthy`:

- PostgreSQL uses `pg_isready` against the n8n database.
- n8n uses the pinned image's Node runtime to fetch its local `/healthz/readiness` endpoint and fails on transport or non-success status.
- Nginx probes its loopback `/healthz` route with the editor Host header.

`verify-runtime.sh` checks all three health signals, disk identity, secret non-persistence in Docker metadata, local forms/editor controls, Tunnel activity, and credential decryption without printing plaintext. `monitor-runtime.sh` records restart counters, alerts on missing or unhealthy containers, checks proxied readiness latency, and reports an inactive Tunnel. `observe-runtime.sh` adds bounded CPU, memory, swap, OOM, latency, and shared Plausible checks for an operator-selected interval.

## Backup and restore

The daily timer runs at 06:30 America/New_York. `backup.sh` changes Nginx to maintenance, stops n8n, creates a PostgreSQL custom dump plus n8n-state and binary-data archives, writes and checks `SHA256SUMS`, restores active service, uploads the package to the private versioned backup bucket, downloads it to a temporary directory, and verifies the checksum manifest again.

`restore-backup.sh` requires:

```text
CONFIRM_RESTORE=restore-daily-abpiv-n8n
```

It accepts only a fully downloaded package, verifies checksums and archive paths, enters maintenance, takes a local pre-restore snapshot, replaces PostgreSQL/state/binary data, and deliberately leaves n8n stopped pending manual acceptance. Restoration is a production data mutation and requires separate owner authority; the infrastructure and release workflows do not dispatch it.

## Host safety

- The data disk UUID must match `/etc/abpiv-n8n/data-disk.uuid`; boot-disk fallback is rejected.
- Docker's `DOCKER-USER` chain blocks containers from the GCE metadata endpoint. Docker startup reapplies the rule.
- The backend network is internal. Only Nginx joins the dedicated ingress bridge and publishes one loopback mapping.
- Images are pinned by immutable digest, logs are bounded, containers use `no-new-privileges`, and secret values are excluded from persistent Docker metadata.
- Deployment preserves runtime mode; it never silently activates a stopped or maintenance runtime.
