# Shared Analytics Infrastructure

This directory contains operator documentation and configuration examples for the shared Plausible Community Edition analytics stack.

The collection Worker also supports the personal OpenPanel gateway through
`/_analytics/openpanel/track`. See the [website OpenPanel setup](../../content-site/OPENPANEL.md)
for its activation sequence and checks. Existing Plausible routes and infrastructure
remain intact.

## Architecture

- Plausible CE dashboard: `https://analytics.lobst3rs.com`
- Public collector route convention: `https://<site-domain>/_analytics/*`
- Initial site domain: `allanbpediniv.com`
- Initial public analytics route: `https://allanbpediniv.com/_analytics/*`
- GCP project: `abpiv-personal-brand`
- GCP VM: `us-east1`, `e2-small`
- Access email: `allanblankpedin@gmail.com`
- SMTP: not configured in v1
- Backups: daily encrypted backups to Google Cloud Storage

The dashboard is an operator-only surface served at `analytics.lobst3rs.com` behind Cloudflare Access. Public website analytics requests should stay same-origin through each site's `/_analytics/*` route and be proxied to Plausible by Cloudflare Worker routing.

## Prepared shared-host migration (not yet live)

`compute/` defines a stopped, isolated Plausible/PostgreSQL/ClickHouse/Nginx project for `abpiv-runtime-vm`. It does not change the current analytics DNS, Worker, Access application, Tunnel, or old VM by itself. The target uses its own 80 GiB non-auto-delete data disk mounted by UUID at `/srv/plausible`; only Nginx binds `127.0.0.1:8000`, and runtime values are read from Secret Manager into `/run/plausible` tmpfs through file mounts rather than Docker environment metadata. Target backups use the new shared private, versioned, seven-day bucket; the old Plausible backup bucket remains with the rollback stack.

`plausible-cutover.yml` is the only prepared migration path. It is independently review- and approval-gated, stops the old writer, proves maintenance through the existing same-origin Worker route, creates an age-encrypted package containing a PostgreSQL custom dump, a native ClickHouse backup, and Plausible application state, then requires exact source/target PostgreSQL counts, ClickHouse counts, and state checksums. The target cannot become active if any comparison fails. On failure it restores the old connector and old containers; on success it keeps the old VM intact but stopped for rollback.

No current-state statement in this file should be read as evidence that the shared-host preparation or cutover has run.

## Current Deployed State

As of 2026-05-26, the initial stack is live:

- `https://analytics.lobst3rs.com` is reachable through Cloudflare Access.
- `https://allanbpediniv.com/_analytics/js/script.js` returns the Plausible browser script.
- `https://allanbpediniv.com/_analytics/api/event` accepts event POSTs and returns `202`.
- `content-site/docusaurus.config.ts` injects the production script with both `data-domain="allanbpediniv.com"` and `data-api="/_analytics/api/event"`.

The `data-api` attribute is not optional. Without it, the Plausible script posts to `/api/event` on the site origin, which produced `405 Method Not Allowed` on Cloudflare Pages.

## Required GitHub Settings

Repository variables:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_ZONE_ID_ALLANBPEDINIV`
- `CLOUDFLARE_ZONE_ID_LOBST3RS`
- `GCP_PROJECT_ID`
- `GCP_REGION`
- `GCP_SERVICE_ACCOUNT`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `PLAUSIBLE_HOSTNAME`
- `ANALYTICS_ACCESS_ALLOWED_EMAIL`
- `ANALYTICS_PRIMARY_SITE_DOMAIN`
- `ANALYTICS_PROXY_ROUTE`

Repository secrets:

- `CLOUDFLARE_ANALYTICS_API_TOKEN`
- `CLOUDFLARE_API_TOKEN`

Future repository secrets:

- `SOPS_AGE_KEY`, only if GitHub Actions needs to decrypt SOPS-managed files.

GCP authentication uses Workload Identity Federation through `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT`. Do not add a `GOOGLE_APPLICATION_CREDENTIALS_JSON` repository secret for this infrastructure.

Analytics validation runs from the `Site and Analytics` GitHub Actions workflow when `infra/analytics/**`, `content-site/**`, or the workflow file changes. Production deploys can pause on the GitHub `production` environment until `BrewDogDev` approves them.

The GitHub deployer service account also needs standing VM provisioning access so `Provision Analytics Host` can rebuild or repair the private Plausible host through IAP:

- `roles/compute.viewer`
- `roles/compute.instanceAdmin.v1`
- `roles/compute.networkAdmin`
- `roles/compute.securityAdmin`
- `roles/compute.osAdminLogin`
- `roles/iap.tunnelResourceAccessor`
- `roles/storage.admin`
- `roles/iam.serviceAccountUser` on `plausible-analytics-vm@abpiv-personal-brand.iam.gserviceaccount.com`

These roles let the workflow locate and converge the VM, SSH through IAP with OS Login, act as only the analytics VM service account during SSH, manage the Plausible backup bucket, and install or restart Docker, Plausible CE, and `cloudflared`.

## First Admin Setup

1. Apply the analytics infrastructure.
2. Visit `https://analytics.lobst3rs.com` through Cloudflare Access.
3. Create the first Plausible admin user.
4. Disable public registration through the configured Plausible environment setting.

Because SMTP is not configured in v1, account and recovery flows that depend on email delivery are not available initially.

## Future Website Onboarding

1. Add a site entry to the OpenTofu locals or configuration for the new site domain.
2. Apply the Cloudflare Worker route for `https://<site-domain>/_analytics/*`.
3. Add the site manually in Plausible CE.
4. Add the tiny same-origin script adapter to the website.
5. Verify in browser DevTools that analytics requests use only the site domain, for example `https://allanbpediniv.com/_analytics/*` for the initial site.

There should be no browser-visible analytics requests to non-site domains from public websites.

## Operator Workflows

- `Site and Analytics`: validates analytics infrastructure, tests the Worker, builds the content site, and deploys Cloudflare Pages.
- `Apply Analytics Infrastructure`: manual `workflow_dispatch`; run with `confirm_apply=apply` to apply OpenTofu changes after reviewing them.
- `Provision Analytics Host`: manual `workflow_dispatch`; run with `confirm_provision=provision` to converge the Plausible VM and `cloudflared`.

The provisioning workflow currently performs the VM convergence inline over IAP SSH. The Ansible directory contains the intended configuration structure and templates, but do not assume the production workflow is executing Ansible unless that workflow is updated.

## Verification Commands

```bash
curl -sS -L https://allanbpediniv.com/info/ -o /tmp/abpiv-info.html -w '%{http_code} %{url_effective}\n'
rg -n 'data-api=|_analytics/js/script.js|/api/event' /tmp/abpiv-info.html
curl -sS -o /tmp/abpiv-analytics-response.txt -w '%{http_code} %{content_type}\n' \
  -X POST https://allanbpediniv.com/_analytics/api/event \
  -H 'content-type: text/plain' \
  --data '{"n":"pageview","u":"https://allanbpediniv.com/info/","d":"allanbpediniv.com","r":null}'
cat /tmp/abpiv-analytics-response.txt
```

Expected result: the page returns `200`, the HTML includes `data-api=/_analytics/api/event`, the event POST returns `202`, and the response body is `ok`.

## Restore Procedure

At a high level:

1. Stop the Plausible services on the analytics VM.
2. Restore Postgres data from the encrypted GCS backup artifact.
3. Restore ClickHouse data from the encrypted GCS backup artifact.
4. Start the Plausible services.
5. Confirm the dashboard loads and pageview ingestion works through the same-origin `/_analytics/*` route.

Keep restore runbooks and exact commands aligned with the deployed OpenTofu, service manager, and backup implementation once those files exist.
