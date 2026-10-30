# Personal website analytics

The site supports OpenPanel through its existing same-origin analytics Worker.
Activation is controlled by the public `OPENPANEL_CLIENT_ID` build variable in
each GitHub deployment environment. Without this variable, the existing Plausible
integration remains active. With it, only OpenPanel is initialized.

## Collection

- The pinned `@openpanel/web` SDK is bundled with the site assets.
- Initial visits and client-side navigation produce `screen_view` events.
- Outbound links produce `link_out` events.
- Session recording, automatic attribute events, and user identification are not enabled.
- Page URLs retain UTM attribution only. Other query parameters and fragments are removed;
  referrer and outbound-link query parameters are also removed.
- The SDK runs only on the configured `SITE_URL` origin in a production build.
  Local development and unrelated Pages artifact domains do not report visits.
- Browser collection uses `/_analytics/openpanel/track` and its `/device-id`
  subpath. The Worker forwards to the personal OpenPanel collection gateway.
  It does not forward website cookies, authorization, Access credentials, or
  caller-supplied IP headers. The gateway independently checks client IDs and origins.
- Legacy Plausible routes remain available for cached pages and other existing consumers.

## Activation order

1. Verify the personal OpenPanel service is healthy and collection is enabled.
2. Create a dedicated production website project and write client for
   `https://allanbpediniv.com`. Use a separate project/client for
   `https://content-site.lobst3rs.com` so preview visits do not enter production reports.
3. Add those exact origins and write-client IDs to the gateway's existing
   `origins.conf` and `clients.conf`, preserving existing entries. Validate and reload
   only the OpenPanel router. Keep secrets and read credentials out of the browser.
4. Run **Analytics Proxy** on `preview` with `target=preview` and
   `confirm_deploy=deploy`. This publishes `analytics-proxy-preview` at the
   preview collection route without changing the production Worker.
   After validation and normal preview-to-main promotion, run it on `main` with
   `target=production` and approve GitHub's production environment review.
   Production publication retains its existing Plausible variables and secrets.
   Neither deployment applies OpenTofu, changes DNS, or modifies either database.
5. Confirm `allanbpediniv.com/_analytics/*` points to `analytics-proxy`, and
   `content-site.lobst3rs.com/_analytics/*` points to `analytics-proxy-preview`.
   The production route is represented in the existing analytics OpenTofu
   configuration. The preview route is set through the existing authorized
   Cloudflare operator connection in the `lobst3rs.com` zone. Route management is
   separate from CI: the existing analytics deploy token can publish code but
   cannot manage routes in the preview zone. Wrangler intentionally omits routes
   and preserves their existing assignments; do not broaden the CI token.
6. Set environment-scoped `OPENPANEL_CLIENT_ID` variables and deploy the content
   site through **Content Site**, preview first and production after validation.
7. Verify a fresh visit, an internal navigation, and an outbound-link click arrive
   in the matching project. Check page URLs, referrers, sessions, and absence of
   duplicate page views. A successful build or HTTP response alone is insufficient.

The dedicated Worker deployment uses `CLOUDFLARE_ANALYTICS_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` from the existing production environment/repository settings.
The Worker source and generated artifact remain the same files consumed by the
existing analytics OpenTofu resource, avoiding two different source definitions.

Rollback the site's OpenPanel activation by removing that environment's public
client-ID variable and redeploying the prior website configuration. This restores
the previous Plausible instrumentation without deleting OpenPanel data.

## Checks

Run the content site's typecheck, build, and homepage-insights check. Also run
the analytics Worker's typecheck, build, and tests, and ensure `dist/index.js`
matches the generated output. The proxy tests cover successful collection,
authentication isolation, blocked operations, body limits, and upstream failures.

The storage repair discovered on October 30, 2026 was completed by a separate
agent. Fresh checks confirmed all nine OpenPanel components healthy, about 28 GB
free, and collection enabled. Website activation does not modify the shared disk
or Obsidian backups.

The `ABPIV` organization now has separate `personal-website` and
`personal-website-preview` projects, with exact production/preview origins and
write-client IDs in the collection gateway allowlists. Browser clients contain
only the public write ID; their associated secrets remain in native credential
storage. Live website event acceptance is recorded after deployment.

Local validation on October 30 passed: site typecheck and production build,
homepage-insights check, and all 12 Worker tests. A real-browser check against a
local collector confirmed exactly two page views (initial load and client-side
navigation), correct destination page titles, one outbound-link event, preserved
UTM attribution, and removal of unrelated query parameters and fragments. This
checks website behavior; it is not evidence of live OpenPanel ingestion.
