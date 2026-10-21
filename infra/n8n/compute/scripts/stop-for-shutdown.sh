#!/usr/bin/env bash
set -euo pipefail

# Preserve the enabled/active intent across an ordinary host shutdown. Manual
# operator shutdown uses runtime-mode.sh stopped, which also disables boot activation.
docker compose --project-directory /opt/abpiv-n8n --file /opt/abpiv-n8n/docker-compose.yml down --remove-orphans
rm -f /run/n8n/runtime.env /run/n8n/postgres.env /run/n8n/postgres-password /run/n8n/encryption-key /run/cloudflared/token
