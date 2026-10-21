data "cloudflare_zones" "editor" {
  count = var.enable_cloudflare_edge && local.editor_enabled && var.editor_zone_id == "" ? 1 : 0

  account = {
    id = var.cloudflare_account_id
  }
  name      = var.editor_zone_name
  max_items = 1
}

resource "cloudflare_dns_record" "forms" {
  count = var.enable_cloudflare_edge ? 1 : 0

  zone_id = var.allanbpediniv_zone_id
  name    = var.forms_hostname
  content = "${cloudflare_zero_trust_tunnel_cloudflared.n8n[0].id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "editor" {
  count = var.enable_cloudflare_edge && local.editor_enabled ? 1 : 0

  zone_id = local.editor_cloudflare_zone_id
  name    = var.editor_hostname
  content = "${cloudflare_zero_trust_tunnel_cloudflared.n8n[0].id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "n8n" {
  count = var.enable_cloudflare_edge ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "abpiv-n8n-compute"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "n8n" {
  count = var.enable_cloudflare_edge ? 1 : 0

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.n8n[0].id
  source     = "cloudflare"

  config = {
    ingress = concat(
      [
        {
          hostname = var.forms_hostname
          service  = "http://127.0.0.1:8080"
        },
      ],
      local.editor_enabled ? [
        {
          hostname = var.editor_hostname
          service  = "http://127.0.0.1:8080"
        },
      ] : [],
      [
        {
          service = "http_status:404"
        },
      ]
    )
  }
}

resource "cloudflare_ruleset" "forms_firewall_custom" {
  count = var.enable_cloudflare_edge ? 1 : 0

  zone_id     = var.allanbpediniv_zone_id
  name        = "n8n public forms protection"
  description = "Allow only public n8n form and production webhook paths on the forms hostname, then challenge suspicious clients."
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      ref         = "n8n_forms_block_non_public_paths"
      description = "Block editor, API, static UI, and other non-public n8n paths on the public forms hostname."
      expression  = "(http.host eq \"${var.forms_hostname}\" and not (${local.public_forms_path_expression}))"
      action      = "block"
    },
    {
      ref         = "n8n_forms_suspicious_clients"
      description = "Managed challenge suspicious non-verified-bot requests to public n8n forms and production webhooks."
      expression  = "(${local.public_forms_request_expression} and not cf.client.bot and cf.threat_score gt ${var.forms_threat_score_challenge_threshold})"
      action      = "managed_challenge"
    },
  ]
}

resource "cloudflare_ruleset" "forms_rate_limit" {
  count = var.enable_cloudflare_edge ? 1 : 0

  zone_id     = var.allanbpediniv_zone_id
  name        = "n8n public forms rate limiting"
  description = "Rate limits public n8n forms traffic by client IP and Cloudflare colo."
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [{
    ref         = "n8n_forms_ip_rate_limit"
    description = "Block clients that exceed public forms request thresholds."
    expression  = local.public_forms_request_expression
    action      = "block"

    ratelimit = {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = var.forms_rate_limit_period_seconds
      requests_per_period = var.forms_rate_limit_requests_per_period
      mitigation_timeout  = var.forms_rate_limit_mitigation_seconds
    }
  }]
}

resource "cloudflare_ruleset" "editor_origin_tls" {
  count = var.enable_cloudflare_edge && local.editor_enabled ? 1 : 0

  zone_id     = local.editor_cloudflare_zone_id
  name        = "n8n editor origin TLS"
  description = "Force Cloudflare to use strict HTTPS to the n8n editor origin."
  kind        = "zone"
  phase       = "http_config_settings"

  rules = [{
    ref         = "n8n_editor_origin_tls_strict"
    description = "Use strict origin TLS for the private n8n editor hostname."
    expression  = "http.host eq \"${var.editor_hostname}\""
    action      = "set_config"

    action_parameters = {
      ssl = "strict"
    }
  }]
}

resource "cloudflare_zero_trust_organization" "n8n" {
  count = var.enable_cloudflare_edge && local.editor_enabled && var.manage_cloudflare_access_organization ? 1 : 0

  account_id              = var.cloudflare_account_id
  name                    = var.cloudflare_access_organization_name
  auth_domain             = var.cloudflare_access_auth_domain
  session_duration        = "24h"
  deny_unmatched_requests = false
}

resource "cloudflare_zero_trust_access_service_token" "n8n_mcp" {
  count = var.enable_cloudflare_edge && local.editor_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "ABPIV Codex n8n MCP"
  duration   = var.editor_mcp_service_token_duration

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_zero_trust_access_application" "editor" {
  count = var.enable_cloudflare_edge && local.editor_enabled ? 1 : 0

  account_id                = var.cloudflare_account_id
  name                      = "n8n editor"
  domain                    = var.editor_hostname
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
  app_launcher_visible      = false
  options_preflight_bypass  = true

  policies = [
    {
      name       = "Allow n8n MCP service token"
      decision   = "non_identity"
      precedence = 1
      include = [
        {
          service_token = {
            token_id = cloudflare_zero_trust_access_service_token.n8n_mcp[0].id
          }
        }
      ]
    },
    {
      name       = "Allow n8n operators"
      decision   = "allow"
      precedence = 2
      include    = local.editor_access_include_rules
    }
  ]

  lifecycle {
    precondition {
      condition     = length(local.editor_access_include_rules) > 0
      error_message = "Set editor_access_allowed_emails or editor_access_allowed_group_ids when editor_hostname is set."
    }
  }

  depends_on = [
    cloudflare_zero_trust_organization.n8n,
  ]
}
