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
4. After normal preview-to-main promotion, manually run **Analytics Proxy** on
   `main` with `confirm_deploy=deploy`. This publishes only the existing Worker,
   retaining its Plausible variables and secrets. It does not apply OpenTofu or
   change DNS, routes, or either analytics database.
5. Confirm the preview hostname has an `/_analytics/*` route to `analytics-proxy`
   before enabling preview collection. The October 30 read found only the production
   route; preview routing still needs configuration in the owning Cloudflare setup.
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

The storage repair discovered on October 30, 2026 is owned by a separate agent.
Live activation and event acceptance must wait for that repair; these source
changes do not modify the shared disk or Obsidian backups.

Local validation on October 30 passed: site typecheck and production build,
homepage-insights check, and all 12 Worker tests. A real-browser check against a
local collector confirmed exactly two page views (initial load and client-side
navigation), correct destination page titles, one outbound-link event, preserved
UTM attribution, and removal of unrelated query parameters and fragments. This
checks website behavior; it is not evidence of live OpenPanel ingestion.
