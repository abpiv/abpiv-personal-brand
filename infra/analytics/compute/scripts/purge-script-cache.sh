#!/usr/bin/env bash
set -euo pipefail

: "${SCRIPT_CACHE_URL:?Set SCRIPT_CACHE_URL to the exact Worker subrequest URL}"
: "${SCRIPT_CACHE_ZONE_ID:?Set SCRIPT_CACHE_ZONE_ID to the owning Cloudflare zone}"
: "${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN for the scoped purge}"

jq --null-input --compact-output --arg url "$SCRIPT_CACHE_URL" '{files:[$url]}' | \
  curl --fail --silent --show-error --max-time 30 --request POST \
    "https://api.cloudflare.com/client/v4/zones/$SCRIPT_CACHE_ZONE_ID/purge_cache" \
    --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    --header 'Content-Type: application/json' \
    --data-binary @- | \
  jq --exit-status '.success == true' >/dev/null
